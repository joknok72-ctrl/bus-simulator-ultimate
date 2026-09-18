class_name Traffic
extends Node3D
## سيارات AI تسير على شبكة الطرق + إشارات مرور عند التقاطعات.
## للأداء: عدد محدود من السيارات، حركة كينماتيكية بسيطة، تصادم عبر Area.

signal red_light_violation()

const BLOCK := RouteData.BLOCK
const N := RouteData.GRID_N
const LANE := 3.4
const CAR_COUNT := 14
const LIGHT_CYCLE := 9.0   # ثواني لكل اتجاه

var cars: Array[Dictionary] = []
var lights: Array[Dictionary] = []   # {pos, node, mats:[ns, ew], state}
var _time := 0.0
var _bus: Bus
var night := false
var _car_mats: Array[StandardMaterial3D] = []
var _rng := RandomNumberGenerator.new()
var _violation_cooldown := 0.0
var _bus_prev_cell := Vector2i(-99, -99)
var _bus_prev_pos := Vector3.ZERO
var enabled_lights := true

func setup(bus: Bus, is_night: bool, with_lights: bool) -> void:
	_bus = bus
	night = is_night
	enabled_lights = with_lights
	_rng.seed = 99
	var palette := [Color(0.9, 0.9, 0.92), Color(0.15, 0.15, 0.18), Color(0.75, 0.15, 0.15), Color(0.2, 0.35, 0.7), Color(0.55, 0.55, 0.6), Color(0.85, 0.6, 0.15)]
	for c in palette:
		var m := StandardMaterial3D.new()
		m.albedo_color = c if not is_night else c.darkened(0.3)
		m.roughness = 0.4
		m.metallic = 0.3
		_car_mats.append(m)
	_spawn_cars()
	if with_lights:
		_build_lights()

# ------------------------------------------------------------------ السيارات
func _spawn_cars() -> void:
	for i in range(CAR_COUNT):
		var car := _make_car_node()
		add_child(car)
		var horizontal := i % 2 == 0
		var line := _rng.randi_range(0, N - 1)
		var dir := 1.0 if _rng.randf() < 0.5 else -1.0
		var c := (line - 2) * BLOCK
		var span := BLOCK * (N - 1) * 0.5
		var along := _rng.randf_range(-span, span)
		cars.append({
			"node": car, "horizontal": horizontal, "line": line, "dir": dir,
			"along": along, "speed": _rng.randf_range(9.0, 14.0), "base_speed": 0.0,
			"stopped": false,
		})
		cars[-1]["base_speed"] = cars[-1]["speed"]
		_place_car(cars[-1])

func _make_car_node() -> Node3D:
	var root := Node3D.new()
	var mat := _car_mats[_rng.randi_range(0, _car_mats.size() - 1)]
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.3, 0.45, 0.6)
	glass.roughness = 0.1
	var wheel := StandardMaterial3D.new()
	wheel.albedo_color = Color(0.08, 0.08, 0.09)
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.8, 0.6, 4.2)
	body.mesh = bm
	body.material_override = mat
	body.position = Vector3(0, 0.6, 0)
	root.add_child(body)
	var cabin := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(1.6, 0.55, 2.2)
	cabin.mesh = cm
	cabin.material_override = glass
	cabin.position = Vector3(0, 1.15, 0.1)
	root.add_child(cabin)
	for sx in [-0.85, 0.85]:
		for sz in [-1.35, 1.35]:
			var w := MeshInstance3D.new()
			var wm := CylinderMesh.new()
			wm.top_radius = 0.32
			wm.bottom_radius = 0.32
			wm.height = 0.25
			wm.radial_segments = 8
			w.mesh = wm
			w.material_override = wheel
			w.rotation_degrees = Vector3(0, 0, 90)
			w.position = Vector3(sx, 0.32, sz)
			root.add_child(w)
	if night:
		var lamp := StandardMaterial3D.new()
		lamp.albedo_color = Color(1, 1, 0.9)
		lamp.emission_enabled = true
		lamp.emission = Color(1, 0.95, 0.8)
		lamp.emission_energy_multiplier = 2.5
		for sx in [-0.6, 0.6]:
			var l := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(0.3, 0.15, 0.05)
			l.mesh = lm
			l.material_override = lamp
			l.position = Vector3(sx, 0.6, -2.1)
			root.add_child(l)
	# جسم تصادم كي يصطدم به الباص (StaticBody يتحرك — كافٍ للمحاكاة الخفيفة)
	var sb := AnimatableBody3D.new()
	sb.collision_layer = 4
	sb.collision_mask = 0
	sb.sync_to_physics = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.8, 1.4, 4.2)
	cs.shape = bs
	cs.position = Vector3(0, 0.8, 0)
	sb.add_child(cs)
	root.add_child(sb)
	return root

func _place_car(car: Dictionary) -> void:
	var c := (int(car["line"]) - 2) * BLOCK
	var d: float = car["dir"]
	var along: float = car["along"]
	var node: Node3D = car["node"]
	if car["horizontal"]:
		# يسير على محور X؛ الحارة اليمنى بالنسبة لاتجاهه
		node.position = Vector3(along, 0.0, c + LANE * d)
		node.rotation.y = PI / 2 if d > 0 else -PI / 2
	else:
		node.position = Vector3(c - LANE * d, 0.0, along)
		node.rotation.y = 0.0 if d < 0 else PI

func _process(delta: float) -> void:
	_time += delta
	_violation_cooldown -= delta
	_update_lights()
	var span := BLOCK * (N - 1) * 0.5 + 10.0
	for car in cars:
		var speed: float = car["speed"]
		var node: Node3D = car["node"]
		# توقف عند الإشارة الحمراء قبل التقاطع
		var target_speed: float = car["base_speed"]
		if enabled_lights and _should_stop_for_light(car):
			target_speed = 0.0
		# توقف إذا كان الباص أمامه مباشرة
		if _bus and _obstacle_ahead(car, _bus.global_position, 9.0):
			target_speed = 0.0
		# توقف إذا كانت سيارة أخرى أمامه
		for other in cars:
			if other == car or other["horizontal"] != car["horizontal"] or other["line"] != car["line"] or other["dir"] != car["dir"]:
				continue
			var gap: float = (float(other["along"]) - float(car["along"])) * float(car["dir"])
			if gap > 0.0 and gap < 7.0:
				target_speed = min(target_speed, float(other["speed"]) * 0.9)
		speed = move_toward(speed, target_speed, delta * (12.0 if target_speed < speed else 5.0))
		car["speed"] = speed
		car["along"] = float(car["along"]) + speed * delta * float(car["dir"])
		if absf(float(car["along"])) > span:
			car["along"] = -signf(float(car["along"])) * span
			# إعادة تدوير: غيّر الخط أحياناً
			if _rng.randf() < 0.5:
				car["line"] = _rng.randi_range(0, N - 1)
		_place_car(car)
	_check_bus_violation()

func _obstacle_ahead(car: Dictionary, pos: Vector3, dist: float) -> bool:
	var node: Node3D = car["node"]
	var to := pos - node.global_position
	var fwd := -node.global_transform.basis.z
	var ahead := to.dot(fwd)
	if ahead < 0.0 or ahead > dist:
		return false
	var lateral := absf(to.dot(node.global_transform.basis.x))
	return lateral < 3.0

# ------------------------------------------------------------------ الإشارات
func _build_lights() -> void:
	var pole := StandardMaterial3D.new()
	pole.albedo_color = Color(0.25, 0.26, 0.3)
	var housing := StandardMaterial3D.new()
	housing.albedo_color = Color(0.1, 0.1, 0.1)
	# إشارات فقط عند التقاطعات الداخلية (1..3) لتقليل العدد
	for i in range(1, N - 1):
		for j in range(1, N - 1):
			var center := RouteData.grid_to_world(i, j)
			var group := Node3D.new()
			group.position = center
			add_child(group)
			var mats: Array = []
			# أربعة أعمدة عند الزوايا؛ كل عمود يعرض حالة الاتجاه القادم نحوه
			var corners := [Vector3(-8.5, 0, -8.5), Vector3(8.5, 0, -8.5), Vector3(8.5, 0, 8.5), Vector3(-8.5, 0, 8.5)]
			for k in range(4):
				var p := MeshInstance3D.new()
				var pm := CylinderMesh.new()
				pm.top_radius = 0.1
				pm.bottom_radius = 0.12
				pm.height = 4.5
				pm.radial_segments = 6
				p.mesh = pm
				p.material_override = pole
				p.position = corners[k] + Vector3(0, 2.25, 0)
				group.add_child(p)
				var h := MeshInstance3D.new()
				var hm := BoxMesh.new()
				hm.size = Vector3(0.4, 1.0, 0.4)
				h.mesh = hm
				h.material_override = housing
				h.position = corners[k] + Vector3(0, 4.7, 0)
				group.add_child(h)
				# لمبة واحدة تتغير لونها (أبسط وأخف)
				var lamp := MeshInstance3D.new()
				var lm := SphereMesh.new()
				lm.radius = 0.16
				lm.height = 0.32
				lm.radial_segments = 8
				lm.rings = 4
				lamp.mesh = lm
				var mat := StandardMaterial3D.new()
				mat.emission_enabled = true
				mat.emission_energy_multiplier = 2.5
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				lamp.material_override = mat
				# الزوايا 0,2 تخدم حركة على محور Z (NS)، الزوايا 1,3 تخدم محور X (EW)
				lamp.position = corners[k] + Vector3(0, 4.7, 0) + Vector3(0.25, 0, 0)
				group.add_child(lamp)
				mats.append(mat)
			lights.append({"cell": Vector2i(i, j), "pos": center, "mats": mats, "ns_green": true})

func _light_phase(cell: Vector2i) -> Dictionary:
	## يرجع {ns_green:bool, ew_green:bool, yellow:bool}
	var offset := float((cell.x + cell.y) % 2) * LIGHT_CYCLE
	var t := fmod(_time + offset, LIGHT_CYCLE * 2.0)
	var ns := t < LIGHT_CYCLE
	var local := fmod(t, LIGHT_CYCLE)
	var yellow := local > LIGHT_CYCLE - 2.0
	return {"ns_green": ns, "ew_green": not ns, "yellow": yellow}

func _update_lights() -> void:
	for l in lights:
		var ph := _light_phase(l["cell"])
		var mats: Array = l["mats"]
		for k in range(4):
			var serves_ns := (k % 2 == 0)
			var green: bool = ph["ns_green"] if serves_ns else ph["ew_green"]
			var col := Color(0.2, 1.0, 0.3)
			if green and ph["yellow"]:
				col = Color(1.0, 0.8, 0.1)
			elif not green:
				col = Color(1.0, 0.15, 0.1)
			var m: StandardMaterial3D = mats[k]
			m.emission = col
			m.albedo_color = col

func _is_red_for(pos: Vector3, moving_along_z: bool) -> bool:
	## هل الإشارة حمراء لمن يتحرك على محور Z (أو X) عند أقرب تقاطع؟
	for l in lights:
		var d: Vector3 = pos - l["pos"]
		if absf(d.x) < 12.0 and absf(d.z) < 12.0:
			var ph := _light_phase(l["cell"])
			var green: bool = ph["ns_green"] if moving_along_z else ph["ew_green"]
			return not green or ph["yellow"]
	return false

func _should_stop_for_light(car: Dictionary) -> bool:
	var node: Node3D = car["node"]
	var pos := node.position
	var d: float = car["dir"]
	var along: float = car["along"]
	# التقاطع القادم على مساره
	var next := (floor((along + BLOCK * 2.0) / BLOCK) + (1 if d > 0 else 0)) * BLOCK - BLOCK * 2.0
	if d < 0:
		next = ceil((along + BLOCK * 2.0) / BLOCK - 1.0) * BLOCK - BLOCK * 2.0 + BLOCK * 0.0
		next = (floor((along + BLOCK * 2.0) / BLOCK)) * BLOCK - BLOCK * 2.0
	var dist := (next - along) * d
	if dist < 9.0 and dist > 6.0:
		var cell := Vector2i.ZERO
		var stop_pos := Vector3.ZERO
		if car["horizontal"]:
			cell = Vector2i(int(round(next / BLOCK)) + 2, int(car["line"]))
			stop_pos = Vector3(next, 0, pos.z)
		else:
			cell = Vector2i(int(car["line"]), int(round(next / BLOCK)) + 2)
			stop_pos = Vector3(pos.x, 0, next)
		if cell.x < 1 or cell.x > N - 2 or cell.y < 1 or cell.y > N - 2:
			return false
		return _is_red_for(stop_pos, not car["horizontal"])
	return false

func _check_bus_violation() -> void:
	if not enabled_lights or not _bus or _violation_cooldown > 0.0:
		return
	var pos := _bus.global_position
	var cell := Vector2i(int(round(pos.x / BLOCK)) + 2, int(round(pos.z / BLOCK)) + 2)
	var center := RouteData.grid_to_world(cell.x, cell.y)
	var inside := absf(pos.x - center.x) < 7.0 and absf(pos.z - center.z) < 7.0
	if inside and cell != _bus_prev_cell and _bus.speed_kmh > 6.0:
		# دخل التقاطع للتو: تحقق من لون الإشارة للاتجاه الذي دخل منه
		var vel := _bus.linear_velocity
		var along_z := absf(vel.z) > absf(vel.x)
		if cell.x >= 1 and cell.x <= N - 2 and cell.y >= 1 and cell.y <= N - 2:
			var ph := _light_phase(cell)
			var green: bool = ph["ns_green"] if along_z else ph["ew_green"]
			if not green:
				_violation_cooldown = 6.0
				red_light_violation.emit()
		_bus_prev_cell = cell
	elif not inside:
		_bus_prev_cell = Vector2i(-99, -99)
