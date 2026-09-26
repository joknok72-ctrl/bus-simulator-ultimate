class_name TrafficSignals
extends Node3D
## Traffic lights for every intersection of the city grid.
##
## All signals run on one shared clock with two phases: first the north-south streets
## (travel along Z) get green, then the east-west streets (travel along X); each green is
## followed by a yellow and a short all-red safety gap. Traffic cars stop at the white line
## when their light is red (see TrafficCar), and the bus is penalised for entering a crossing
## on red (see Game._check_red_light).
##
## Every approach that has a road gets a stop line (before the crosswalk the road shader
## paints) and two signal heads aimed at the approaching traffic: a primary head on a pole at
## the stop line, read while driving up to the crossing, and a repeater on a mast arm over the
## far right corner, read from the driver's seat while waiting at the line. The whole city
## (80 approaches) is baked into ONE mesh: the lamps of all north-south signals share three
## materials and all east-west lamps share three more, so switching a phase is six material
## updates and the signals cost about ten draw calls.

enum Axis { NS, EW }              # NS = travel along Z, EW = travel along X
enum Light { RED, YELLOW, GREEN } # top-to-bottom order of the lamps in a signal head

const GREEN_TIME := 8.0
const YELLOW_TIME := 2.0
const ALL_RED_TIME := 0.6         # both axes red between phases
const HALF_CYCLE := GREEN_TIME + YELLOW_TIME + ALL_RED_TIME
const CYCLE := HALF_CYCLE * 2.0
## The stop line is painted this far before the edge of the intersection square: just before
## the 2.6 m crosswalk of the road shader, so waiting vehicles keep the crossing clear.
const STOP_LINE_OFFSET := 4.2
## Entering a crossing this soon after the light turned red is still tolerated (reaction time).
const RED_GRACE := 0.35
const NO_NODE := Vector2i(-1, -1)

const POLE_HEIGHT := 6.0          # mast-arm pole (far corner)
const ARM_Y := 5.85
const HEAD_Y := 5.15
const HEAD_X := 3.5               # lateral position of the mast-arm head: between the two approach lanes
const NEAR_POLE_HEIGHT := 4.2     # primary signal pole (kerb, at the stop line)
const NEAR_HEAD_Y := 3.4
const LAMP_COLORS: Array[Color] = [Color(1.0, 0.16, 0.1), Color(1.0, 0.72, 0.08), Color(0.15, 0.95, 0.35)]
const LAMP_OFF := Color(0.15, 0.15, 0.16)   # unlit lenses: dark, with a hint of their colour

## Phase clock in seconds; advances on physics ticks (so it pauses with the game).
var time := 0.0
var night := false
## Number of signalised approaches built (a 5x5 grid has 80).
var approaches := 0
var mesh_instance: MeshInstance3D

var _lamp_mats: Array = []        # [axis][Light] -> StandardMaterial3D shared by every head of that axis
var _lit: Array[int] = [-1, -1]   # currently lit lamp per axis (avoids touching materials every tick)
var _metal: StandardMaterial3D
var _housing: StandardMaterial3D
var _backplate: StandardMaterial3D
var _line_mat: StandardMaterial3D


# ---------------------------------------------------------------- phase logic (static, testable)
## Light shown to traffic travelling along `axis` when the clock reads `t`.
static func light_at(t: float, axis: int) -> int:
	var phase := fposmod(t - _axis_shift(axis), CYCLE)
	if phase < GREEN_TIME:
		return Light.GREEN
	if phase < GREEN_TIME + YELLOW_TIME:
		return Light.YELLOW
	return Light.RED


## Seconds the light for `axis` has been red at clock `t` (0 when it is not red).
static func red_seconds_at(t: float, axis: int) -> float:
	var phase := fposmod(t - _axis_shift(axis), CYCLE)
	return maxf(0.0, phase - GREEN_TIME - YELLOW_TIME)


## Clock value at which the light for `axis` turns green `seconds` later (used to start a route
## with a known phase).
static func time_before_green(axis: int, seconds: float) -> float:
	return fposmod(_axis_shift(axis) - seconds, CYCLE)


static func _axis_shift(axis: int) -> float:
	return HALF_CYCLE if axis == Axis.EW else 0.0


## Axis of travel for a (roughly axis-aligned) direction.
static func axis_of(dir: Vector3) -> int:
	return Axis.EW if absf(dir.x) > absf(dir.z) else Axis.NS


## Grid node whose intersection square (the road width, plus `margin`) contains `point`, or
## NO_NODE when the point is on a street or inside a block.
static func intersection_at(point: Vector3, margin: float = 0.0) -> Vector2i:
	var half := CityLayout.half_extent()
	var i := roundi((point.x + half) / CityLayout.BLOCK)
	var j := roundi((point.z + half) / CityLayout.BLOCK)
	if i < 0 or j < 0 or i >= CityLayout.GRID_N or j >= CityLayout.GRID_N:
		return NO_NODE
	var c := CityLayout.node_pos(Vector2i(i, j))
	var reach := CityLayout.CURB + margin
	if absf(point.x - c.x) <= reach and absf(point.z - c.z) <= reach:
		return Vector2i(i, j)
	return NO_NODE


## Signed distance (m) from `front_point` to the stop line of the approach into `node` along
## `dir`; negative once the point is over the line.
static func stop_line_distance(node: Vector2i, dir: Vector3, front_point: Vector3) -> float:
	return (CityLayout.node_pos(node) - front_point).dot(dir) - CityLayout.CURB - STOP_LINE_OFFSET


# ---------------------------------------------------------------- instance API
func light_for(axis: int) -> int:
	return light_at(time, axis)


func red_seconds(axis: int) -> float:
	return red_seconds_at(time, axis)


func set_time(t: float) -> void:
	time = t
	_apply_lamps()


## The signalised intersection ahead of a vehicle at `pos` driving along `forward`
## (`front_offset` metres from `pos` to its front bumper). Returns
## {node, axis, distance, light} where distance is from the bumper to the stop line (negative
## once the bumper is over it), or {} when the vehicle is not on a street or no approach is ahead.
func next_signal_ahead(pos: Vector3, forward: Vector3, front_offset: float) -> Dictionary:
	var axis := axis_of(forward)
	var s := signf(forward.x if axis == Axis.EW else forward.z)
	if s == 0.0:
		return {}
	var half := CityLayout.half_extent()
	var n := CityLayout.GRID_N
	# The street the vehicle drives along (nearest grid line across the travel axis) ...
	var cross := pos.z if axis == Axis.EW else pos.x
	var j := roundi((cross + half) / CityLayout.BLOCK)
	if j < 0 or j >= n or absf(cross - (j * CityLayout.BLOCK - half)) > CityLayout.CURB + 1.5:
		return {}
	# ... and the first intersection centre ahead of the front bumper along it.
	var along := pos.x if axis == Axis.EW else pos.z
	var front := along + s * front_offset
	var u := (front + half) / CityLayout.BLOCK
	var i := ceili(u + 0.0001) if s > 0.0 else floori(u - 0.0001)
	if i < 0 or i >= n:
		return {}
	var from_i := i - int(s)
	if from_i < 0 or from_i >= n:
		return {}   # coming from outside the grid: no road, no signal
	var node := Vector2i(i, j) if axis == Axis.EW else Vector2i(j, i)
	var centre := CityLayout.node_pos(node)
	var c_along := centre.x if axis == Axis.EW else centre.z
	var distance := s * (c_along - front) - CityLayout.CURB - STOP_LINE_OFFSET
	return {"node": node, "axis": axis, "distance": distance, "light": light_for(axis)}


# ---------------------------------------------------------------- building
func build(is_night: bool, start_time: float) -> void:
	night = is_night
	_build_materials()
	var merger := MeshMerger.new()
	var n := CityLayout.GRID_N
	approaches = 0
	for j in n:
		for i in n:
			var node := Vector2i(i, j)
			for d in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
				# Traffic arriving along d comes from the neighbour behind the crossing; no
				# neighbour means no road and no signal on that side.
				var from := node - Vector2i(int(d.x), int(d.z))
				if from.x < 0 or from.x >= n or from.y < 0 or from.y >= n:
					continue
				_add_approach(merger, node, d)
				approaches += 1
	mesh_instance = merger.instance(self, "SignalsMesh")
	# Thin poles and arms: their shadows are hardly visible but would cost a second pass over
	# ~30k triangles (19 draw calls on route 1) - like the roads, the signals cast none.
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lit[0] = -1
	_lit[1] = -1
	set_time(start_time)


func _build_materials() -> void:
	_metal = MeshFactory.mat(Color(0.3, 0.32, 0.35), 0.5, 0.6)
	_housing = MeshFactory.mat(Color(0.13, 0.13, 0.14), 0.7)
	_backplate = MeshFactory.mat(Color(0.05, 0.05, 0.06), 0.9)
	_line_mat = MeshFactory.mat(Color(0.95, 0.95, 0.95), 0.9)
	_lamp_mats.clear()
	for axis in 2:
		var row: Array[StandardMaterial3D] = []
		for k in 3:
			# Dedicated (uncached) materials: their colour and emission are toggled at runtime.
			# Unshaded, like the guide arrow: a lit lens must stay a saturated red/amber/green
			# instead of washing out to white in direct sunlight.
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.emission_enabled = true
			m.emission = LAMP_COLORS[k]
			row.append(m)
		_lamp_mats.append(row)


## One approach into `node` for traffic travelling along `d`, built in a local frame whose
## -Z is the travel direction and +X the driver's right (curb side), with the intersection
## centre at the origin.
func _add_approach(merger: MeshMerger, node: Vector2i, d: Vector3) -> void:
	var xf := Transform3D(Basis.looking_at(d, Vector3.UP), CityLayout.node_pos(node))
	var curb := CityLayout.CURB
	var axis := axis_of(d)
	var line_z := curb + STOP_LINE_OFFSET
	# Stop line across the two approach lanes (between the centre line and the edge line).
	_add_box(merger, xf, Vector3(curb - 0.7, 0.02, 0.45), Vector3(curb * 0.5, 0.03, line_z), _line_mat)
	# Primary signal: a pole on the kerb at the stop line with the head at 3.4 m, facing the
	# approaching traffic. Big in the windshield while driving up; beside the bumper (and
	# out of sight) once at the line, which is what the far-side repeater is for.
	var near_x := curb + 1.0
	var near_z := line_z - 0.5
	merger.add(_cylinder(0.09, NEAR_POLE_HEIGHT, 8), Transform3D(xf.basis, xf * Vector3(near_x, 0.16 + NEAR_POLE_HEIGHT * 0.5, near_z)), _metal)
	_add_box(merger, xf, Vector3(0.16, 0.1, 0.1), Vector3(near_x - 0.16, NEAR_HEAD_Y, near_z), _metal)   # bracket
	_add_head(merger, xf, Vector3(near_x - 0.4, NEAR_HEAD_Y, near_z), axis)
	# Repeater: mast-arm pole on the far right corner of the crossing (on the sidewalk, clear
	# of the street lamp at the block corner), arm reaching over the approach lanes.
	var pole_x := curb + 1.2
	var pole_z := -(curb + 3.0)
	merger.add(_cylinder(0.12, POLE_HEIGHT, 8), Transform3D(xf.basis, xf * Vector3(pole_x, 0.16 + POLE_HEIGHT * 0.5, pole_z)), _metal)
	var arm_len := pole_x - HEAD_X
	_add_box(merger, xf, Vector3(arm_len + 0.12, 0.14, 0.14), Vector3((pole_x + HEAD_X) * 0.5, ARM_Y, pole_z), _metal)
	_add_head(merger, xf, Vector3(HEAD_X, HEAD_Y, pole_z), axis)


## A signal head centred at `at` (approach frame): housing, black backplate behind it and
## three lenses with visors on the face that looks at the approaching traffic (+Z here).
func _add_head(merger: MeshMerger, xf: Transform3D, at: Vector3, axis: int) -> void:
	_add_box(merger, xf, Vector3(0.44, 1.18, 0.34), at, _housing)
	_add_box(merger, xf, Vector3(0.78, 1.5, 0.04), at + Vector3(0, 0, -0.19), _backplate)
	var lamp_basis := xf.basis * Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0))   # cylinder axis along local Z
	for k in 3:
		var y := at.y + 0.37 - k * 0.37
		merger.add(_cylinder(0.15, 0.06, 8), Transform3D(lamp_basis, xf * Vector3(at.x, y, at.z + 0.17)), _lamp_mats[axis][k])
		_add_box(merger, xf, Vector3(0.38, 0.03, 0.24), Vector3(at.x, y + 0.18, at.z + 0.28), _housing)


func _add_box(merger: MeshMerger, xf: Transform3D, size: Vector3, local_pos: Vector3, material: Material) -> void:
	merger.add_box(size, xf * local_pos, material, xf.basis)


## Poles stand in the ground and lenses sit against the housing, so the bottom cap is never
## seen and left out.
static func _cylinder(radius: float, height: float, segments: int) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 0
	mesh.cap_bottom = false
	return mesh


# ---------------------------------------------------------------- running
func _physics_process(delta: float) -> void:
	time += delta
	_apply_lamps()


func _apply_lamps() -> void:
	if _lamp_mats.is_empty():
		return
	for axis in 2:
		var lit := light_for(axis)
		if lit == _lit[axis]:
			continue
		_lit[axis] = lit
		for k in 3:
			var m: StandardMaterial3D = _lamp_mats[axis][k]
			var on := k == lit
			m.albedo_color = LAMP_COLORS[k] if on else LAMP_OFF.lerp(LAMP_COLORS[k], 0.2)
			m.emission_energy_multiplier = (1.4 if night else 0.5) if on else 0.0
