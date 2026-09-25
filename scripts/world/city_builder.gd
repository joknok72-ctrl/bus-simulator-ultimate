class_name CityBuilder
extends Node3D
## Procedurally builds the whole city for a route: ground, roads, sidewalks,
## buildings, parks, trees, street lamps, boundary walls, sky/lighting, bus stops,
## the terminal and ambient traffic. Deterministic per route (seeded RNG) so a
## route always looks the same.

const PALETTE: Array[Color] = [
	Color(0.82, 0.76, 0.66), Color(0.66, 0.68, 0.72), Color(0.62, 0.32, 0.26),
	Color(0.5, 0.58, 0.68), Color(0.86, 0.8, 0.6), Color(0.36, 0.4, 0.46),
	Color(0.75, 0.55, 0.45), Color(0.92, 0.92, 0.9),
]

var stops: Array[BusStop] = []
var terminal: BusStop
var route_points: PackedVector3Array = PackedVector3Array()
var night := false
var time_of_day := "day"
var route: Dictionary = {}
var sun: DirectionalLight3D
var world_env: WorldEnvironment
var cars: Array[TrafficCar] = []

var _rng := RandomNumberGenerator.new()
var _building_mats: Array[ShaderMaterial] = []
var _stop_positions: PackedVector3Array = PackedVector3Array()


func build(route_def: Dictionary, quality: int) -> void:
	route = route_def
	time_of_day = String(route.get("time_of_day", "day"))
	night = time_of_day == "night"
	_rng.seed = hash(String(route.id))
	route_points = CityLayout.route_polyline(route.path)
	_build_materials()
	_build_environment(quality)
	_build_ground()
	_build_roads()
	_build_stops()
	_build_blocks()
	_build_props()
	_build_boundary()
	_build_traffic()


# ---------------------------------------------------------------- environment
func _build_environment(quality: int) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_sky_affect = 0.4
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = quality >= 1
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 120.0
	match time_of_day:
		"sunset":
			sky_mat.sky_top_color = Color(0.25, 0.3, 0.55)
			sky_mat.sky_horizon_color = Color(0.98, 0.6, 0.35)
			sky_mat.ground_horizon_color = Color(0.9, 0.55, 0.35)
			sky_mat.ground_bottom_color = Color(0.2, 0.15, 0.15)
			sky_mat.sun_angle_max = 20.0
			env.fog_light_color = Color(0.95, 0.65, 0.45)
			env.fog_density = 0.004
			env.ambient_light_energy = 0.9
			sun.light_color = Color(1.0, 0.72, 0.45)
			sun.light_energy = 1.1
			sun.rotation_degrees = Vector3(-14.0, 50.0, 0.0)
		"night":
			sky_mat.sky_top_color = Color(0.015, 0.02, 0.06)
			sky_mat.sky_horizon_color = Color(0.08, 0.09, 0.16)
			sky_mat.ground_horizon_color = Color(0.06, 0.06, 0.1)
			sky_mat.ground_bottom_color = Color(0.01, 0.01, 0.02)
			sky_mat.sun_angle_max = 8.0
			env.fog_light_color = Color(0.08, 0.09, 0.15)
			env.fog_density = 0.006
			env.ambient_light_energy = 0.55
			sun.light_color = Color(0.65, 0.72, 1.0)
			sun.light_energy = 0.28
			sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
		_:
			sky_mat.sky_top_color = Color(0.3, 0.52, 0.86)
			sky_mat.sky_horizon_color = Color(0.72, 0.82, 0.92)
			sky_mat.ground_horizon_color = Color(0.7, 0.76, 0.8)
			sky_mat.ground_bottom_color = Color(0.25, 0.28, 0.3)
			env.fog_light_color = Color(0.78, 0.86, 0.95)
			env.fog_density = 0.0018
			env.ambient_light_energy = 1.0
			sun.light_color = Color(1.0, 0.96, 0.9)
			sun.light_energy = 1.25
			sun.rotation_degrees = Vector3(-52.0, 35.0, 0.0)
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	add_child(sun)


func _build_materials() -> void:
	_building_mats.clear()
	var shader: Shader = load("res://shaders/building.gdshader")
	for i in PALETTE.size():
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("base_color", PALETTE[i])
		m.set_shader_parameter("window_color", Color(0.1, 0.14, 0.2) if not night else Color(0.05, 0.06, 0.09))
		m.set_shader_parameter("window_emission", 1.6 if night else (0.25 if time_of_day == "sunset" else 0.0))
		m.set_shader_parameter("window_density", Vector2(0.45 + 0.05 * (i % 3), 0.33))
		m.set_shader_parameter("lit_ratio", 0.55)
		_building_mats.append(m)


# ---------------------------------------------------------------- ground and roads
func _build_ground() -> void:
	var grass_color := Color(0.3, 0.46, 0.24) if not night else Color(0.08, 0.12, 0.08)
	var ground := MeshFactory.plane(self, Vector2(900, 900), Vector3(0, -0.02, 0), MeshFactory.mat(grass_color, 1.0))
	ground.name = "Ground"
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	body.add_child(cs)
	add_child(body)


func _build_roads() -> void:
	var road_shader: Shader = load("res://shaders/road.gdshader")
	var seg_len := CityLayout.BLOCK - CityLayout.ROAD_WIDTH
	var seg_mat := ShaderMaterial.new()
	seg_mat.shader = road_shader
	seg_mat.set_shader_parameter("road_length", seg_len)
	seg_mat.set_shader_parameter("road_width", CityLayout.ROAD_WIDTH)
	seg_mat.set_shader_parameter("lane_width", CityLayout.LANE_WIDTH)
	var seg_mesh := PlaneMesh.new()
	seg_mesh.size = Vector2(CityLayout.ROAD_WIDTH, seg_len)
	seg_mesh.material = seg_mat
	var inter_mesh := PlaneMesh.new()
	inter_mesh.size = Vector2(CityLayout.ROAD_WIDTH, CityLayout.ROAD_WIDTH)
	inter_mesh.material = MeshFactory.mat(Color(0.16, 0.16, 0.17), 0.95)
	var roads := Node3D.new()
	roads.name = "Roads"
	add_child(roads)
	var n := CityLayout.GRID_N
	for j in n:
		for i in n:
			var p := CityLayout.node_pos(Vector2i(i, j))
			var inter := MeshInstance3D.new()
			inter.mesh = inter_mesh
			inter.position = p + Vector3(0, 0.01, 0)
			roads.add_child(inter)
			if i < n - 1:
				var mi := MeshInstance3D.new()
				mi.mesh = seg_mesh
				mi.position = p + Vector3(CityLayout.BLOCK * 0.5, 0.01, 0)
				mi.rotation.y = PI * 0.5
				roads.add_child(mi)
			if j < n - 1:
				var mi2 := MeshInstance3D.new()
				mi2.mesh = seg_mesh
				mi2.position = p + Vector3(0, 0.01, CityLayout.BLOCK * 0.5)
				roads.add_child(mi2)


# ---------------------------------------------------------------- stops
func _build_stops() -> void:
	stops.clear()
	_stop_positions.clear()
	var path: Array = route.path
	var stop_defs: Array = route.stops
	var passengers: Array = route.passengers
	for i in stop_defs.size():
		var seg: int = stop_defs[i][0]
		var frac: float = stop_defs[i][1]
		var a: Vector2i = path[seg]
		var b: Vector2i = path[seg + 1]
		var pos := CityLayout.lane_point(a, b, frac)
		var dir := CityLayout.seg_dir(a, b)
		var stop := BusStop.new()
		stop.name = "Stop%d" % (i + 1)
		add_child(stop)
		var count: int = passengers[i] if i < passengers.size() else 3
		stop.setup(i, pos, dir, count, night)
		stops.append(stop)
		_stop_positions.append(pos)
	# Terminal near the end of the last segment.
	var last_a: Vector2i = path[path.size() - 2]
	var last_b: Vector2i = path[path.size() - 1]
	var seg_length := CityLayout.node_pos(last_a).distance_to(CityLayout.node_pos(last_b))
	var t_frac := 1.0 - 14.0 / seg_length
	var t_pos := CityLayout.lane_point(last_a, last_b, t_frac)
	terminal = BusStop.new()
	terminal.name = "Terminal"
	add_child(terminal)
	terminal.setup(stops.size(), t_pos, CityLayout.seg_dir(last_a, last_b), 0, night, true)
	_stop_positions.append(t_pos)


## World position and heading for the bus at the start of the route.
func get_spawn_transform() -> Transform3D:
	var path: Array = route.path
	var a: Vector2i = path[0]
	var b: Vector2i = path[1]
	var dir := CityLayout.seg_dir(a, b)
	var seg_length := CityLayout.node_pos(a).distance_to(CityLayout.node_pos(b))
	var pos := CityLayout.lane_point(a, b, 12.0 / seg_length)
	var xf := Transform3D.IDENTITY
	xf.origin = pos
	xf = xf.looking_at(pos + dir, Vector3.UP)
	return xf


# ---------------------------------------------------------------- blocks
func _build_blocks() -> void:
	var blocks := Node3D.new()
	blocks.name = "Blocks"
	add_child(blocks)
	var n := CityLayout.GRID_N - 1
	var cell_half := (CityLayout.BLOCK - CityLayout.ROAD_WIDTH) * 0.5
	var inner_half := cell_half - CityLayout.SIDEWALK
	var sidewalk_mat := MeshFactory.mat(Color(0.62, 0.6, 0.58) if not night else Color(0.3, 0.3, 0.32), 0.95)
	var park_mat := MeshFactory.mat(Color(0.26, 0.5, 0.22) if not night else Color(0.07, 0.13, 0.07), 1.0)
	var half_city := CityLayout.half_extent()
	for by in n:
		for bx in n:
			var center := CityLayout.node_pos(Vector2i(bx, by)) + Vector3(CityLayout.BLOCK * 0.5, 0, CityLayout.BLOCK * 0.5)
			# Sidewalk ring.
			var sw_y := 0.08
			var edge := cell_half - CityLayout.SIDEWALK * 0.5
			MeshFactory.box(blocks, Vector3(cell_half * 2.0, 0.16, CityLayout.SIDEWALK), center + Vector3(0, sw_y, -edge), sidewalk_mat)
			MeshFactory.box(blocks, Vector3(cell_half * 2.0, 0.16, CityLayout.SIDEWALK), center + Vector3(0, sw_y, edge), sidewalk_mat)
			MeshFactory.box(blocks, Vector3(CityLayout.SIDEWALK, 0.16, inner_half * 2.0), center + Vector3(-edge, sw_y, 0), sidewalk_mat)
			MeshFactory.box(blocks, Vector3(CityLayout.SIDEWALK, 0.16, inner_half * 2.0), center + Vector3(edge, sw_y, 0), sidewalk_mat)
			var is_park := _rng.randf() < 0.2
			if is_park:
				MeshFactory.box(blocks, Vector3(inner_half * 2.0, 0.12, inner_half * 2.0), center + Vector3(0, 0.06, 0), park_mat)
				_build_park(blocks, center, inner_half)
				continue
			# Ground slab for the lot.
			MeshFactory.box(blocks, Vector3(inner_half * 2.0, 0.1, inner_half * 2.0), center + Vector3(0, 0.05, 0), MeshFactory.mat(Color(0.42, 0.4, 0.4) if not night else Color(0.16, 0.16, 0.18), 0.95))
			var lot := inner_half
			var dist_factor := 1.0 - clampf(center.length() / (half_city * 1.3), 0.0, 1.0)
			for ly in 2:
				for lx in 2:
					if _rng.randf() < 0.12:
						continue
					var lot_center := center + Vector3((lx - 0.5) * lot, 0, (ly - 0.5) * lot)
					var w := _rng.randf_range(11.0, lot - 3.0)
					var d := _rng.randf_range(11.0, lot - 3.0)
					var h := _rng.randf_range(7.0, 14.0) + dist_factor * _rng.randf_range(8.0, 34.0)
					var jitter := Vector3(_rng.randf_range(-1.0, 1.0), 0, _rng.randf_range(-1.0, 1.0))
					var pos := lot_center + jitter
					var mi := MeshFactory.box(blocks, Vector3(w, h, d), pos + Vector3(0, h * 0.5, 0), _building_mats[_rng.randi() % _building_mats.size()])
					mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
					# Roof details.
					if _rng.randf() < 0.6:
						MeshFactory.box(blocks, Vector3(w * 0.3, 2.0, d * 0.3), pos + Vector3(_rng.randf_range(-w * 0.2, w * 0.2), h + 1.0, _rng.randf_range(-d * 0.2, d * 0.2)), MeshFactory.mat(Color(0.5, 0.5, 0.52), 0.9))
					if h > 30.0:
						MeshFactory.cylinder(blocks, 0.15, 5.0, pos + Vector3(0, h + 2.5, 0), MeshFactory.mat(Color(0.8, 0.1, 0.1), 0.5, 0.0, Color(1, 0.1, 0.1), 3.0 if night else 0.0), Vector3.ZERO, 6)
					MeshFactory.static_box(blocks, Vector3(w, h, d), pos + Vector3(0, h * 0.5, 0))


func _build_park(parent: Node3D, center: Vector3, inner_half: float) -> void:
	var tree_mesh := MeshFactory.tree_mesh(Color(0.2, 0.5, 0.2) if not night else Color(0.05, 0.14, 0.06))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = tree_mesh
	var count := 10
	mm.instance_count = count
	for i in count:
		var pos := center + Vector3(_rng.randf_range(-inner_half + 3.0, inner_half - 3.0), 0.1, _rng.randf_range(-inner_half + 3.0, inner_half - 3.0))
		var xf := Transform3D(Basis.from_euler(Vector3(0, _rng.randf_range(0, TAU), 0)).scaled(Vector3.ONE * _rng.randf_range(0.8, 1.3)), pos)
		mm.set_instance_transform(i, xf)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	parent.add_child(mmi)
	# Fountain in the middle.
	var stone := MeshFactory.mat(Color(0.7, 0.7, 0.72), 0.8)
	MeshFactory.cylinder(parent, 3.2, 0.6, center + Vector3(0, 0.4, 0), stone, Vector3.ZERO, 20)
	MeshFactory.cylinder(parent, 2.7, 0.3, center + Vector3(0, 0.7, 0), MeshFactory.glass_mat(Color(0.3, 0.6, 0.9, 0.7)), Vector3.ZERO, 20)
	MeshFactory.cylinder(parent, 0.4, 2.2, center + Vector3(0, 1.4, 0), stone, Vector3.ZERO, 10)
	# Paths.
	var path_mat := MeshFactory.mat(Color(0.72, 0.66, 0.55), 1.0)
	MeshFactory.box(parent, Vector3(inner_half * 2.0, 0.02, 2.5), center + Vector3(0, 0.13, 0), path_mat)
	MeshFactory.box(parent, Vector3(2.5, 0.02, inner_half * 2.0), center + Vector3(0, 0.13, 0), path_mat)
	MeshFactory.static_box(parent, Vector3(6.4, 2.0, 6.4), center + Vector3(0, 1.0, 0))


# ---------------------------------------------------------------- props
func _build_props() -> void:
	var n := CityLayout.GRID_N - 1
	var cell_half := (CityLayout.BLOCK - CityLayout.ROAD_WIDTH) * 0.5
	var tree_xforms: Array[Transform3D] = []
	var lamp_xforms: Array[Transform3D] = []
	var edge := cell_half - CityLayout.SIDEWALK * 0.5
	for by in n:
		for bx in n:
			var center := CityLayout.node_pos(Vector2i(bx, by)) + Vector3(CityLayout.BLOCK * 0.5, 0, CityLayout.BLOCK * 0.5)
			# Lamps at the four corners of every block, facing the road.
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var lp := center + Vector3(sx * edge, 0.16, sz * edge)
					lamp_xforms.append(Transform3D(Basis.from_euler(Vector3(0, atan2(-sx, -sz) + PI, 0)), lp))
			# Trees along the sidewalks.
			var spacing := 12.0
			var count := int((cell_half * 2.0 - 8.0) / spacing)
			for k in count:
				var offset := -cell_half + 6.0 + k * spacing
				for candidate in [
					center + Vector3(offset, 0.16, -edge), center + Vector3(offset, 0.16, edge),
					center + Vector3(-edge, 0.16, offset), center + Vector3(edge, 0.16, offset)]:
					if _near_stop(candidate, 9.0) or _rng.randf() < 0.25:
						continue
					var s := _rng.randf_range(0.8, 1.25)
					tree_xforms.append(Transform3D(Basis.from_euler(Vector3(0, _rng.randf_range(0, TAU), 0)).scaled(Vector3.ONE * s), candidate))
	_add_multimesh(MeshFactory.tree_mesh(Color(0.22, 0.52, 0.22) if not night else Color(0.05, 0.14, 0.06)), tree_xforms, "Trees")
	_add_multimesh(MeshFactory.lamp_mesh(night), lamp_xforms, "Lamps")


func _add_multimesh(mesh: Mesh, xforms: Array[Transform3D], node_name: String) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	add_child(mmi)


func _near_stop(pos: Vector3, radius: float) -> bool:
	for sp in _stop_positions:
		if sp.distance_to(pos) < radius:
			return true
	return false


# ---------------------------------------------------------------- boundary
func _build_boundary() -> void:
	var limit := CityLayout.half_extent() + CityLayout.CURB + 4.0
	var length := limit * 2.0 + 10.0
	var hedge := MeshFactory.mat(Color(0.2, 0.42, 0.2) if not night else Color(0.05, 0.12, 0.05), 1.0)
	for side in [-1.0, 1.0]:
		MeshFactory.box(self, Vector3(length, 1.4, 1.6), Vector3(0, 0.7, side * limit), hedge)
		MeshFactory.box(self, Vector3(1.6, 1.4, length), Vector3(side * limit, 0.7, 0), hedge)
		MeshFactory.static_box(self, Vector3(length, 8.0, 1.6), Vector3(0, 4.0, side * limit))
		MeshFactory.static_box(self, Vector3(1.6, 8.0, length), Vector3(side * limit, 4.0, 0))
	# Distant skyline for the horizon.
	var far := limit + 60.0
	var sky_mat := _building_mats[1]
	for i in 28:
		var angle := TAU * i / 28.0 + _rng.randf_range(-0.05, 0.05)
		var radius := far + _rng.randf_range(0.0, 80.0)
		var pos := Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		var h := _rng.randf_range(20.0, 70.0)
		var w := _rng.randf_range(14.0, 30.0)
		var mi := MeshFactory.box(self, Vector3(w, h, w), pos + Vector3(0, h * 0.5, 0), sky_mat, rad_to_deg(angle))
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


# ---------------------------------------------------------------- traffic
func _build_traffic() -> void:
	cars.clear()
	var count: int = int(route.get("traffic", 6))
	var n := CityLayout.GRID_N
	for i in count:
		# Random rectangle of blocks, driven clockwise (right turns only).
		var x0 := _rng.randi_range(0, n - 2)
		var x1 := _rng.randi_range(x0 + 1, n - 1)
		var y0 := _rng.randi_range(0, n - 2)
		var y1 := _rng.randi_range(y0 + 1, n - 1)
		var loop: Array = [Vector2i(x0, y0), Vector2i(x1, y0), Vector2i(x1, y1), Vector2i(x0, y1)]
		var lane := CityLayout.OUTER_LANE if _rng.randf() < 0.5 else CityLayout.INNER_LANE
		var pts := PackedVector3Array()
		for k in loop.size():
			var prev: Vector2i = loop[(k - 1 + loop.size()) % loop.size()]
			var cur: Vector2i = loop[k]
			var next: Vector2i = loop[(k + 1) % loop.size()]
			var d1 := CityLayout.seg_dir(prev, cur)
			var d2 := CityLayout.seg_dir(cur, next)
			pts.append(CityLayout.node_pos(cur) + CityLayout.right_of(d1) * lane + CityLayout.right_of(d2) * lane)
		var car := TrafficCar.new()
		car.name = "Car%d" % (i + 1)
		add_child(car)
		car.setup(pts, _rng.randi_range(0, 3), night, _rng.randf() < 0.2)
		cars.append(car)
