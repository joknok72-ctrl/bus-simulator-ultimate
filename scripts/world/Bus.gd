class_name Bus
extends VehicleBody3D
## الباص القابل للقيادة: فيزياء VehicleBody3D + جسم low-poly مولّد + أبواب + راحة الركاب.
## Game Feel: استجابة فورية للتحكم، ميل الجسم، صوت محرك يتبع السرعة، اهتزاز عند الصدم.

signal collided(impulse: float)
signal doors_changed(open: bool)
signal comfort_event(kind: String, severity: float)  # "brake", "turn", "bump"
signal flipped_recovered()

var data: Dictionary
var bus_id := "mini"

# مدخلات التحكم (0..1 / -1..1)
var throttle_input := 0.0
var brake_input := 0.0
var steer_input := 0.0
var handbrake := false

var doors_open := false
var speed_kmh := 0.0
var speed_ms := 0.0
var _prev_velocity := Vector3.ZERO
var _steer_current := 0.0
var _wheels: Array[VehicleWheel3D] = []
var _body_mesh: Node3D
var _door_left: MeshInstance3D
var _door_left2: MeshInstance3D
var _door_target := 0.0
var _door_anim := 0.0
var _headlights: Array[SpotLight3D] = []
var _brake_lights: Array[MeshInstance3D] = []
var _mat_brake: StandardMaterial3D
var _skid_timer := 0.0
var _collision_cooldown := 0.0
var _last_lateral_g := 0.0
var _prev_forward_speed := 0.0
var _decel_smooth := 0.0
var _lat_smooth := 0.0
var _comfort_cooldown := 0.0
var _flip_timer := 0.0

# معاملات مشتقة من البيانات + الترقيات
var _engine_force := 0.0
var _brake_force := 0.0
var _max_speed_ms := 0.0
var _steer_max := 0.6
var _comfort_tolerance := 1.0

func setup(id: String) -> void:
	bus_id = id
	data = BusData.get_bus(id)
	var eng_lvl := GameState.upgrade_level("engine")
	var brk_lvl := GameState.upgrade_level("brakes")
	var sus_lvl := GameState.upgrade_level("suspension")
	_engine_force = float(data["engine_power"]) * float(data["mass"]) / 100.0 * (1.0 + 0.15 * eng_lvl)
	_brake_force = float(data["brake_force"]) * float(data["mass"]) / 100.0 * (1.0 + 0.2 * brk_lvl)
	_max_speed_ms = float(data["max_speed"]) / 3.6
	_steer_max = float(data["steer_angle"])
	_comfort_tolerance = 1.0 + 0.25 * sus_lvl
	mass = float(data["mass"])
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.9, 0)
	collision_layer = 2
	collision_mask = 1 | 4 | 8
	contact_monitor = true
	max_contacts_reported = 4
	linear_damp = 0.05
	angular_damp = 1.5
	_build_body()
	_build_wheels()
	body_entered.connect(_on_body_entered)

func _flat(color: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m

func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _build_body() -> void:
	var L: float = data["length"]
	var W: float = data["width"]
	var H: float = data["height"]
	var col: Color = data["color"]
	_body_mesh = Node3D.new()
	_body_mesh.name = "BodyMesh"
	add_child(_body_mesh)
	var body_mat := _flat(col, 0.45, 0.1)
	var glass := _flat(Color(0.35, 0.55, 0.75, 0.85), 0.1, 0.3)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var dark := _flat(Color(0.12, 0.12, 0.14), 0.7)
	var white := _flat(Color(0.95, 0.95, 0.95), 0.5)
	# الهيكل الرئيسي (المقدمة نحو -Z)
	var floor_y := 0.55
	var body_h := H - floor_y - 0.25
	_box(Vector3(W, body_h, L), Vector3(0, floor_y + body_h * 0.5, 0), body_mat, _body_mesh)
	# السقف
	_box(Vector3(W - 0.15, 0.25, L - 0.2), Vector3(0, H - 0.125, 0), white, _body_mesh)
	# شريط النوافذ الجانبية
	var win_y := floor_y + body_h * 0.62
	_box(Vector3(W + 0.04, body_h * 0.42, L * 0.82), Vector3(0, win_y, -0.15), glass, _body_mesh)
	# الزجاج الأمامي
	_box(Vector3(W - 0.2, body_h * 0.55, 0.06), Vector3(0, win_y - 0.1, L * 0.5 + 0.01), glass, _body_mesh)
	# الزجاج الخلفي
	_box(Vector3(W - 0.4, body_h * 0.35, 0.06), Vector3(0, win_y, -L * 0.5 - 0.01), glass, _body_mesh)
	# الصدّام الأمامي/الخلفي
	_box(Vector3(W + 0.05, 0.3, 0.2), Vector3(0, floor_y, -L * 0.5), dark, _body_mesh)
	_box(Vector3(W + 0.05, 0.3, 0.2), Vector3(0, floor_y, L * 0.5), dark, _body_mesh)
	# لوحة رقم الخط (أمام أعلى)
	_box(Vector3(W * 0.7, 0.3, 0.05), Vector3(0, H - 0.45, L * 0.5 + 0.03), _make_sign_mat(), _body_mesh)
	# الأبواب (الجهة اليمنى +X) — بابان
	var door_mat := _flat(col.darkened(0.15), 0.4)
	_door_left = _box(Vector3(0.06, body_h * 0.85, 1.2), Vector3(W * 0.5 + 0.02, floor_y + body_h * 0.45, L * 0.5 - 1.4), door_mat, _body_mesh)
	_door_left2 = _box(Vector3(0.06, body_h * 0.85, 1.2), Vector3(W * 0.5 + 0.02, floor_y + body_h * 0.45, -L * 0.15), door_mat, _body_mesh)
	# المصابيح الأمامية
	var lamp := _flat(Color(1, 0.98, 0.85), 0.2)
	lamp.emission_enabled = true
	lamp.emission = Color(1, 0.95, 0.7)
	lamp.emission_energy_multiplier = 2.0
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.35, 0.2, 0.08), Vector3(sx * (W * 0.5 - 0.35), floor_y + 0.35, L * 0.5 + 0.05), lamp, _body_mesh)
		var sl := SpotLight3D.new()
		sl.position = Vector3(sx * (W * 0.5 - 0.35), floor_y + 0.35, L * 0.5 + 0.1)
		sl.rotation_degrees = Vector3(-8, 0, 0)
		sl.spot_range = 40
		sl.spot_angle = 35
		sl.light_energy = 0.0
		sl.light_color = Color(1, 0.95, 0.8)
		sl.shadow_enabled = false
		_body_mesh.add_child(sl)
		_headlights.append(sl)
	# أضواء الفرامل
	_mat_brake = _flat(Color(0.6, 0.05, 0.05), 0.3)
	_mat_brake.emission_enabled = true
	_mat_brake.emission = Color(1, 0.1, 0.1)
	_mat_brake.emission_energy_multiplier = 0.0
	for sx in [-1.0, 1.0]:
		_brake_lights.append(_box(Vector3(0.3, 0.22, 0.08), Vector3(sx * (W * 0.5 - 0.3), floor_y + 0.4, -L * 0.5 - 0.05), _mat_brake, _body_mesh))
	# مرايا
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.12, 0.3, 0.2), Vector3(sx * (W * 0.5 + 0.2), win_y, L * 0.5 - 0.4), dark, _body_mesh)
	# شكل التصادم
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(W, H - floor_y + 0.1, L)
	cs.shape = bs
	cs.position = Vector3(0, floor_y + (H - floor_y) * 0.5, 0)
	add_child(cs)

func _make_sign_mat() -> StandardMaterial3D:
	var m := _flat(Color(0.1, 0.1, 0.12), 0.3)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.6, 0.1)
	m.emission_energy_multiplier = 1.2
	return m

func _build_wheels() -> void:
	var L: float = data["length"]
	var W: float = data["width"]
	var wheel_r := 0.5
	var wheel_mat := _flat(Color(0.08, 0.08, 0.09), 0.9)
	var rim_mat := _flat(Color(0.7, 0.7, 0.72), 0.3, 0.6)
	var positions := [
		[Vector3(-W * 0.5 + 0.15, wheel_r, L * 0.5 - 1.3), true],
		[Vector3(W * 0.5 - 0.15, wheel_r, L * 0.5 - 1.3), true],
		[Vector3(-W * 0.5 + 0.15, wheel_r, -L * 0.5 + 1.6), false],
		[Vector3(W * 0.5 - 0.15, wheel_r, -L * 0.5 + 1.6), false],
	]
	if L >= 14.0:
		positions.append([Vector3(-W * 0.5 + 0.15, wheel_r, -L * 0.1), false])
		positions.append([Vector3(W * 0.5 - 0.15, wheel_r, -L * 0.1), false])
	for p in positions:
		var w := VehicleWheel3D.new()
		w.position = p[0]
		w.use_as_steering = p[1]
		w.use_as_traction = not p[1] or L < 8.0
		w.wheel_radius = wheel_r
		w.wheel_rest_length = 0.25
		w.suspension_stiffness = 60.0
		w.suspension_travel = 0.3
		w.suspension_max_force = mass * 12.0
		w.damping_compression = 1.2
		w.damping_relaxation = 1.6
		w.wheel_friction_slip = 3.2
		w.wheel_roll_influence = 0.02
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = wheel_r
		cyl.bottom_radius = wheel_r
		cyl.height = 0.35
		cyl.radial_segments = 12
		mi.mesh = cyl
		mi.material_override = wheel_mat
		mi.rotation_degrees = Vector3(0, 0, 90)
		w.add_child(mi)
		var rim := MeshInstance3D.new()
		var rc := CylinderMesh.new()
		rc.top_radius = wheel_r * 0.55
		rc.bottom_radius = wheel_r * 0.55
		rc.height = 0.37
		rc.radial_segments = 8
		rim.mesh = rc
		rim.material_override = rim_mat
		rim.rotation_degrees = Vector3(0, 0, 90)
		w.add_child(rim)
		add_child(w)
		_wheels.append(w)

func set_headlights(on: bool) -> void:
	for h in _headlights:
		h.light_energy = 2.5 if on else 0.0

func _physics_process(delta: float) -> void:
	speed_ms = linear_velocity.length()
	speed_kmh = speed_ms * 3.6
	var forward_speed := linear_velocity.dot(global_transform.basis.z)  # الأمام = +Z (اتجاه engine_force الموجب في VehicleBody3D)
	# ---- التوجيه: أسرع عند السرعات المنخفضة (للاصطفاف)، محدود عند السرعات العالية (ثبات)
	var speed_factor := clampf(1.0 - speed_kmh / 140.0, 0.35, 1.0)
	var sens: float = float(GameState.settings.get("steer_sensitivity", 1.0))
	var target_steer := steer_input * _steer_max * speed_factor * sens
	_steer_current = move_toward(_steer_current, target_steer, delta * 3.5)
	steering = _steer_current
	# ---- القوة: لا يتجاوز السرعة القصوى + تراجع عند الفرملة والباص متوقف
	var doors_block := doors_open
	var eff_throttle := 0.0 if doors_block else throttle_input
	if forward_speed < _max_speed_ms:
		var falloff := clampf(1.0 - forward_speed / _max_speed_ms, 0.15, 1.0)
		engine_force = eff_throttle * _engine_force * falloff
	else:
		engine_force = 0.0
	# ---- الفرامل / الرجوع للخلف
	if brake_input > 0.0:
		if forward_speed > 0.8:
			brake = brake_input * _brake_force
			engine_force = 0.0
		else:
			# الباص شبه متوقف: الفرامل تعمل كرجوع للخلف (بسرعة محدودة)
			brake = 0.0
			if not doors_block and forward_speed > -4.0:
				engine_force = -brake_input * _engine_force * 0.45
	else:
		brake = 0.0
	if handbrake or doors_open:
		brake = max(brake, _brake_force * 0.6)
	# مقاومة طبيعية
	if throttle_input <= 0.01 and brake_input <= 0.01 and not handbrake:
		brake = _brake_force * 0.02
	# ---- ثبات: مقاومة الانقلاب (anti-roll) + تعافٍ تلقائي إذا انقلب
	var up := global_transform.basis.y
	var tilt := up.angle_to(Vector3.UP)
	if tilt > 0.05 and tilt < 1.4:
		var corr := up.cross(Vector3.UP)
		apply_torque(corr * mass * 18.0 * tilt)
		angular_velocity.x *= 0.96
		angular_velocity.z *= 0.96
	if tilt > 1.4:
		_flip_timer += delta
		if _flip_timer > 1.5:
			_flip_timer = 0.0
			var fwd := global_transform.basis.z
			fwd.y = 0.0
			if fwd.length() < 0.1:
				fwd = Vector3.FORWARD
			reset_to(Vector3(global_position.x, 0.0, global_position.z), fwd.normalized())
			flipped_recovered.emit()
	else:
		_flip_timer = 0.0
	# ---- Game Feel: أضواء الفرامل
	_mat_brake.emission_energy_multiplier = 3.0 if (brake_input > 0.05 or handbrake) else 0.0
	# ---- راحة الركاب: تسارع مُنعَّم (فلتر) لتجنب ضجيج الفيزياء
	var decel_raw: float = (_prev_forward_speed - forward_speed) / maxf(delta, 0.0001) / 9.81  # موجب = فرملة
	_decel_smooth = lerpf(_decel_smooth, decel_raw, 0.25)
	var lat_raw: float = absf(angular_velocity.y * forward_speed) / 9.81  # تسارع جانبي = v·ω
	_lat_smooth = lerpf(_lat_smooth, lat_raw, 0.25)
	_comfort_cooldown -= delta
	if _comfort_cooldown <= 0.0:
		if _decel_smooth > 0.35 * _comfort_tolerance and speed_kmh > 8.0:
			comfort_event.emit("brake", _decel_smooth)
			_comfort_cooldown = 0.6
			if _decel_smooth > 0.7 and _skid_timer <= 0.0:
				AudioFX.play("skid", -8.0, randf_range(0.9, 1.1), 0.8)
				_skid_timer = 1.0
		elif _lat_smooth > 0.3 * _comfort_tolerance and speed_kmh > 15.0:
			comfort_event.emit("turn", _lat_smooth)
			_comfort_cooldown = 0.6
	_prev_forward_speed = forward_speed
	_prev_velocity = linear_velocity
	_skid_timer -= delta
	_collision_cooldown -= delta
	# ---- الأبواب (تحريك)
	_door_target = 1.0 if doors_open else 0.0
	_door_anim = move_toward(_door_anim, _door_target, delta * 2.5)
	if _door_left:
		var W: float = data["width"]
		_door_left.position.x = W * 0.5 + 0.02 + _door_anim * 0.35
		_door_left.rotation.y = _door_anim * 0.9
		_door_left2.position.x = W * 0.5 + 0.02 + _door_anim * 0.35
		_door_left2.rotation.y = _door_anim * 0.9
	# ---- صوت المحرك
	var rpm_ratio := clampf(forward_speed / _max_speed_ms, 0.0, 1.0)
	AudioFX.engine_update(rpm_ratio, eff_throttle)

func toggle_doors() -> bool:
	## يرجع true إذا تغيّرت حالة الأبواب (يُمنع الفتح أثناء الحركة السريعة)
	if not doors_open and speed_kmh > 4.0:
		return false
	doors_open = not doors_open
	AudioFX.play("door_open" if doors_open else "door_close", -4.0)
	if doors_open:
		AudioFX.play("air_brake", -10.0)
	Haptics.light()
	doors_changed.emit(doors_open)
	return true

func _on_body_entered(body: Node) -> void:
	if _collision_cooldown > 0.0:
		return
	var impulse := speed_ms
	if impulse < 1.2:
		return
	_collision_cooldown = 0.8
	AudioFX.play("crash", clampf(-14.0 + impulse, -14.0, 2.0), randf_range(0.85, 1.15))
	Haptics.heavy()
	comfort_event.emit("bump", impulse / 5.0)
	collided.emit(impulse)

func reset_to(pos: Vector3, dir: Vector3) -> void:
	## يضع الباص في موضع واتجاه معيّنين (الأمام = -Z)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	var basis := Basis.looking_at(-dir, Vector3.UP)  # الأمام (+Z) نحو dir
	global_transform = Transform3D(basis, pos + Vector3(0, 0.6, 0))
	_prev_velocity = Vector3.ZERO
	_prev_forward_speed = 0.0
	_decel_smooth = 0.0
	_lat_smooth = 0.0
	_steer_current = 0.0
	steering = 0.0

func front_position() -> Vector3:
	return global_position + global_transform.basis.z * float(data["length"]) * 0.5

func door_position() -> Vector3:
	## موقع الباب الأمامي (الجهة اليمنى)
	var L: float = data["length"]
	var W: float = data["width"]
	return global_position + global_transform.basis.x * (W * 0.5) + global_transform.basis.z * (L * 0.5 - 1.4)
