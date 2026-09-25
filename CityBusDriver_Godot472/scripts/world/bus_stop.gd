class_name BusStop
extends Node3D
## A bus stop: shelter, sign, painted stop zone on the road and waiting passengers.
## The node origin is the point in the right lane where the bus should stop;
## -Z is the direction of travel and +X points to the curb.

const ZONE_HALF_LENGTH := 8.0
const ZONE_HALF_WIDTH := 2.7
const CURB_X := CityLayout.CURB - CityLayout.OUTER_LANE   # distance from lane centre to the curb

var index: int = 0
var waiting: Array[Passenger] = []
var served: bool = false
var is_terminal: bool = false

var _zone: MeshInstance3D
var _zone_mat: StandardMaterial3D
var _pulse := 0.0
var _active := false


func setup(idx: int, world_pos: Vector3, travel_dir: Vector3, passenger_count: int, night: bool, terminal: bool = false) -> void:
	index = idx
	is_terminal = terminal
	global_position = world_pos
	look_at(world_pos + travel_dir, Vector3.UP)
	_build_zone()
	if terminal:
		_build_terminal(night)
	else:
		_build_shelter(night)
		_spawn_passengers(passenger_count)


func _build_zone() -> void:
	_zone_mat = StandardMaterial3D.new()
	_zone_mat.albedo_color = Color(1.0, 0.85, 0.2, 0.45)
	_zone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_zone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_zone_mat.emission_enabled = true
	_zone_mat.emission = Color(1.0, 0.8, 0.2)
	_zone_mat.emission_energy_multiplier = 0.6
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(ZONE_HALF_WIDTH * 2.0, ZONE_HALF_LENGTH * 2.0)
	_zone = MeshInstance3D.new()
	_zone.mesh = mesh
	_zone.material_override = _zone_mat
	_zone.position = Vector3(0, 0.04, 0)
	add_child(_zone)
	# Dashed white border around the zone.
	var border_mat := MeshFactory.mat(Color(0.95, 0.95, 0.95), 0.9)
	for side in [-1.0, 1.0]:
		MeshFactory.box(self, Vector3(0.18, 0.02, ZONE_HALF_LENGTH * 2.0), Vector3(side * ZONE_HALF_WIDTH, 0.03, 0), border_mat)
		MeshFactory.box(self, Vector3(ZONE_HALF_WIDTH * 2.0, 0.02, 0.18), Vector3(0, 0.03, side * ZONE_HALF_LENGTH), border_mat)


func _build_shelter(night: bool) -> void:
	var metal := MeshFactory.mat(Color(0.25, 0.27, 0.3), 0.4, 0.7)
	var roof_mat := MeshFactory.mat(Color(0.85, 0.2, 0.2), 0.6)
	var glass := MeshFactory.glass_mat(Color(0.5, 0.7, 0.85, 0.35))
	var x := CURB_X + 1.6
	# poles
	for z in [-2.2, 2.2]:
		MeshFactory.cylinder(self, 0.06, 2.6, Vector3(x + 0.9, 1.3, z), metal)
		MeshFactory.cylinder(self, 0.06, 2.6, Vector3(x - 0.9, 1.3, z), metal)
	# roof
	MeshFactory.box(self, Vector3(2.4, 0.12, 5.2), Vector3(x, 2.66, 0), roof_mat)
	# back glass panel
	MeshFactory.box(self, Vector3(0.06, 2.2, 4.6), Vector3(x + 0.95, 1.4, 0), glass)
	# bench
	MeshFactory.box(self, Vector3(0.5, 0.08, 3.2), Vector3(x + 0.5, 0.5, 0), MeshFactory.mat(Color(0.55, 0.38, 0.2), 0.8))
	MeshFactory.box(self, Vector3(0.08, 0.5, 3.0), Vector3(x + 0.72, 0.25, 0), metal)
	# sign pole with the stop number
	var sign_x := CURB_X + 0.5
	MeshFactory.cylinder(self, 0.05, 3.0, Vector3(sign_x, 1.5, -3.6), metal)
	var sign_mat := MeshFactory.mat(Color(0.98, 0.8, 0.15), 0.5, 0.0, Color(1.0, 0.8, 0.2), 1.2 if night else 0.0)
	MeshFactory.box(self, Vector3(0.06, 0.7, 0.9), Vector3(sign_x, 2.85, -3.6), sign_mat)
	var label := Label3D.new()
	label.text = "BUS %d" % (index + 1)
	label.font_size = 64
	label.pixel_size = 0.006
	label.modulate = Color(0.1, 0.1, 0.12)
	label.outline_size = 0
	label.position = Vector3(sign_x - 0.05, 2.85, -3.6)
	label.rotation.y = -PI * 0.5
	label.double_sided = true
	add_child(label)
	# Light under the roof at night.
	if night:
		MeshFactory.box(self, Vector3(1.6, 0.06, 3.0), Vector3(x, 2.58, 0), MeshFactory.mat(Color(1, 1, 0.9), 0.3, 0.0, Color(1.0, 0.95, 0.8), 2.5))


func _build_terminal(night: bool) -> void:
	var metal := MeshFactory.mat(Color(0.25, 0.27, 0.3), 0.4, 0.7)
	var x := CURB_X + 2.2
	# Arch over the sidewalk with a TERMINAL sign.
	MeshFactory.cylinder(self, 0.12, 5.0, Vector3(x - 1.5, 2.5, 0), metal)
	MeshFactory.cylinder(self, 0.12, 5.0, Vector3(x + 1.5, 2.5, 0), metal)
	var sign_mat := MeshFactory.mat(Color(0.15, 0.65, 0.35), 0.5, 0.0, Color(0.2, 0.9, 0.4), 1.5 if night else 0.0)
	MeshFactory.box(self, Vector3(3.6, 1.0, 0.2), Vector3(x, 5.2, 0), sign_mat)
	var label := Label3D.new()
	label.text = "TERMINAL"
	label.font_size = 72
	label.pixel_size = 0.008
	label.modulate = Color(1, 1, 1)
	label.outline_size = 6
	label.outline_modulate = Color(0, 0.2, 0.1)
	label.position = Vector3(x, 5.2, -0.12)
	label.double_sided = true
	add_child(label)
	# Flags on the poles.
	var flag_mat := MeshFactory.mat(Color(0.95, 0.95, 0.95), 0.9)
	MeshFactory.box(self, Vector3(0.9, 0.5, 0.04), Vector3(x - 1.05, 5.9, 0), flag_mat)
	MeshFactory.box(self, Vector3(0.9, 0.5, 0.04), Vector3(x + 1.95, 5.9, 0), flag_mat)
	_zone_mat.albedo_color = Color(0.3, 0.9, 0.5, 0.45)
	_zone_mat.emission = Color(0.3, 0.9, 0.5)


func _spawn_passengers(count: int) -> void:
	for i in count:
		var p := Passenger.new()
		add_child(p)
		p.position = Vector3(CURB_X + randf_range(0.6, 2.4), 0.0, randf_range(-3.2, 3.2))
		p.rotation.y = randf_range(-0.6, 0.6) + PI * 0.5
		waiting.append(p)


## True when the bus centre is inside the painted stop zone.
func is_bus_in_zone(bus_global_pos: Vector3) -> bool:
	var local := to_local(bus_global_pos)
	return absf(local.z) < ZONE_HALF_LENGTH and absf(local.x) < ZONE_HALF_WIDTH


## Signed distance the bus has travelled past the stop along the travel direction.
func distance_past(bus_global_pos: Vector3) -> float:
	return -to_local(bus_global_pos).z


## Random point on the sidewalk next to the stop (for alighting passengers).
func sidewalk_point() -> Vector3:
	return to_global(Vector3(CURB_X + randf_range(0.8, 2.6), 0.0, randf_range(-4.0, 4.0)))


func set_active(active: bool) -> void:
	_active = active
	_zone.visible = active or not served


func mark_served() -> void:
	served = true
	_active = false
	_zone.visible = false


func _process(delta: float) -> void:
	if _active and _zone.visible:
		_pulse += delta * 3.0
		_zone_mat.emission_energy_multiplier = 0.6 + 0.5 * (0.5 + 0.5 * sin(_pulse))
		_zone_mat.albedo_color.a = 0.35 + 0.25 * (0.5 + 0.5 * sin(_pulse))
