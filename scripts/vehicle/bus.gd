class_name Bus
extends CharacterBody3D
## The player's city bus. Arcade-style kinematic vehicle model tuned for touch
## controls: throttle/brake pedals, steering in -1..1, doors and horn.
## -Z is forward. Emits signals consumed by the mission controller.

signal collided(strength: float)
signal doors_changed(open: bool)
signal horn_sounded()

# --- tuning ---------------------------------------------------------------
const MAX_SPEED := 22.0            # m/s (~80 km/h)
const MAX_REVERSE := 4.5
const ENGINE_ACCEL := 4.2
const REVERSE_ACCEL := 2.5
const BRAKE_DECEL := 9.0
const ENGINE_BRAKE := 1.4
const DRAG := 0.045
const WHEELBASE := 6.4
const MAX_STEER_LOW := deg_to_rad(38.0)
const MAX_STEER_HIGH := deg_to_rad(9.0)
const STEER_RATE := deg_to_rad(95.0)
const STEER_RETURN_RATE := deg_to_rad(140.0)
const WHEEL_RADIUS := 0.55
const REVERSE_HOLD_TIME := 0.45

# --- inputs (set every frame by the controller) -----------------------------
var input_throttle := 0.0
var input_brake := 0.0
var input_steer := 0.0

# --- state -------------------------------------------------------------------
var speed := 0.0                   # signed, m/s, positive forward
var steer_angle := 0.0
var doors_open := false
var reverse_gear := false
var engine_on := true
var damage := 0.0                  # 0..100
var night := false

var _vertical_velocity := 0.0
var _reverse_hold := 0.0
var _collision_cooldown := 0.0
var _door_tween: Tween
var _horn_cooldown := 0.0

# --- visual nodes --------------------------------------------------------------
var body_pivot: Node3D
var wheel_pivots: Array[Node3D] = []      # steering pivots (front wheels)
var wheel_spinners: Array[Node3D] = []    # rolling wheels
var door_front: Node3D
var door_rear: Node3D
var headlights: Array[SpotLight3D] = []
var brake_light_mat: StandardMaterial3D
var reverse_light_mat: StandardMaterial3D
var chase_mount: Node3D
var driver_mount: Node3D
var top_mount: Node3D
var livery_color := Color(0.85, 0.16, 0.14)


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	floor_snap_length = 0.4
	up_direction = Vector3.UP
	safe_margin = 0.02
	body_pivot = get_node_or_null("BodyPivot")
	if body_pivot == null:
		body_pivot = Node3D.new()
		body_pivot.name = "BodyPivot"
		add_child(body_pivot)
	chase_mount = get_node_or_null("Mounts/ChaseMount")
	driver_mount = get_node_or_null("Mounts/DriverMount")
	top_mount = get_node_or_null("Mounts/TopMount")
	_build_visual()


func configure(color: Color, is_night: bool) -> void:
	livery_color = color
	night = is_night
	# Rebuild the paintwork with the chosen livery.
	for child in body_pivot.get_children():
		child.queue_free()
	wheel_pivots.clear()
	wheel_spinners.clear()
	headlights.clear()
	_build_visual()


# ---------------------------------------------------------------- visuals
func _build_visual() -> void:
	var paint := MeshFactory.mat(livery_color, 0.35, 0.3)
	var trim := MeshFactory.mat(Color(0.92, 0.92, 0.94), 0.4, 0.2)
	var dark := MeshFactory.mat(Color(0.08, 0.08, 0.09), 0.85)
	var glass := MeshFactory.glass_mat(Color(0.2, 0.32, 0.45, 0.72))
	var chrome := MeshFactory.mat(Color(0.75, 0.77, 0.8), 0.2, 0.9)
	var L := 11.0
	var W := 2.5
	# Lower body
	MeshFactory.box(body_pivot, Vector3(W, 1.3, L), Vector3(0, 1.15, 0), paint)
	# Upper body (window band) with white roof stripe
	MeshFactory.box(body_pivot, Vector3(W - 0.04, 1.25, L - 0.02), Vector3(0, 2.4, 0), glass)
	MeshFactory.box(body_pivot, Vector3(W, 0.32, L), Vector3(0, 3.16, 0), trim)
	# Pillars between windows
	for i in 6:
		var z := -L * 0.5 + 1.2 + i * 1.75
		MeshFactory.box(body_pivot, Vector3(W + 0.02, 1.25, 0.14), Vector3(0, 2.4, z), paint)
	# Roof and AC unit
	MeshFactory.box(body_pivot, Vector3(W - 0.3, 0.14, L - 0.4), Vector3(0, 3.38, 0), trim)
	MeshFactory.box(body_pivot, Vector3(1.4, 0.35, 2.2), Vector3(0, 3.6, 1.0), trim)
	# Front: windshield, bumper, destination sign
	MeshFactory.box(body_pivot, Vector3(W - 0.2, 1.9, 0.08), Vector3(0, 2.15, -L * 0.5 - 0.01), glass)
	MeshFactory.box(body_pivot, Vector3(W, 0.45, 0.3), Vector3(0, 0.62, -L * 0.5 - 0.1), dark)
	MeshFactory.box(body_pivot, Vector3(W - 0.5, 0.3, 0.08), Vector3(0, 3.2, -L * 0.5 - 0.02), MeshFactory.mat(Color(0.95, 0.65, 0.1), 0.4, 0.0, Color(1.0, 0.7, 0.1), 2.0))
	# Rear bumper and engine grille
	MeshFactory.box(body_pivot, Vector3(W, 0.45, 0.3), Vector3(0, 0.62, L * 0.5 + 0.1), dark)
	MeshFactory.box(body_pivot, Vector3(W - 0.6, 0.9, 0.06), Vector3(0, 1.4, L * 0.5 + 0.02), dark)
	# Headlights
	var head_mat := MeshFactory.mat(Color(1, 1, 0.95), 0.2, 0.0, Color(1.0, 0.95, 0.85), 3.0 if night else 0.3)
	for x in [-0.85, 0.85]:
		MeshFactory.box(body_pivot, Vector3(0.45, 0.28, 0.08), Vector3(x, 1.05, -L * 0.5 - 0.03), head_mat)
	# Tail lights (brake) and reverse lights
	brake_light_mat = StandardMaterial3D.new()
	brake_light_mat.albedo_color = Color(0.75, 0.08, 0.08)
	brake_light_mat.emission_enabled = true
	brake_light_mat.emission = Color(1.0, 0.1, 0.1)
	brake_light_mat.emission_energy_multiplier = 0.3
	reverse_light_mat = StandardMaterial3D.new()
	reverse_light_mat.albedo_color = Color(0.9, 0.9, 0.9)
	reverse_light_mat.emission_enabled = true
	reverse_light_mat.emission = Color(1, 1, 1)
	reverse_light_mat.emission_energy_multiplier = 0.0
	for x in [-0.9, 0.9]:
		MeshFactory.box(body_pivot, Vector3(0.4, 0.3, 0.06), Vector3(x, 1.3, L * 0.5 + 0.03), brake_light_mat)
		MeshFactory.box(body_pivot, Vector3(0.25, 0.18, 0.06), Vector3(x, 0.98, L * 0.5 + 0.03), reverse_light_mat)
	# Mirrors
	for x in [-1.45, 1.45]:
		MeshFactory.box(body_pivot, Vector3(0.12, 0.45, 0.25), Vector3(x, 2.5, -L * 0.5 + 0.6), dark)
		MeshFactory.box(body_pivot, Vector3(0.06, 0.4, 0.04), Vector3(x + (0.05 if x < 0 else -0.05), 2.5, -L * 0.5 + 0.5), chrome)
	# Doors on the right side (curb side). Two door leaves per door.
	door_front = Node3D.new()
	door_front.position = Vector3(W * 0.5 + 0.02, 0, -L * 0.5 + 1.9)
	body_pivot.add_child(door_front)
	door_rear = Node3D.new()
	door_rear.position = Vector3(W * 0.5 + 0.02, 0, 0.8)
	body_pivot.add_child(door_rear)
	for door in [door_front, door_rear]:
		MeshFactory.box(door, Vector3(0.06, 2.1, 1.3), Vector3(0, 1.6, 0), MeshFactory.mat(livery_color.darkened(0.15), 0.4, 0.3))
		MeshFactory.box(door, Vector3(0.07, 1.0, 1.1), Vector3(0, 2.0, 0), glass)
	# Door frames (dark openings visible when doors slide open)
	for z in [door_front.position.z, door_rear.position.z]:
		MeshFactory.box(body_pivot, Vector3(0.04, 2.2, 1.4), Vector3(W * 0.5 - 0.06, 1.55, z), dark)
	# Interior: seats and driver
	var seat_mat := MeshFactory.mat(Color(0.2, 0.3, 0.55), 0.9)
	for i in 5:
		var z := -L * 0.5 + 3.4 + i * 1.5
		MeshFactory.box(body_pivot, Vector3(0.9, 0.9, 0.5), Vector3(-0.7, 1.8, z), seat_mat)
		MeshFactory.box(body_pivot, Vector3(0.9, 0.9, 0.5), Vector3(0.7, 1.8, z), seat_mat)
	MeshFactory.box(body_pivot, Vector3(0.7, 0.9, 0.5), Vector3(-0.75, 1.85, -L * 0.5 + 1.6), MeshFactory.mat(Color(0.15, 0.15, 0.18)))
	MeshFactory.cylinder(body_pivot, 0.22, 0.04, Vector3(-0.75, 2.05, -L * 0.5 + 1.0), dark, Vector3(PI * 0.35, 0, 0), 14)
	# Wheels: 2 front (steer) + 4 rear (dual)
	var rim := MeshFactory.mat(Color(0.7, 0.7, 0.72), 0.3, 0.8)
	var tire := MeshFactory.mat(Color(0.06, 0.06, 0.07), 0.95)
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(side * 1.0, WHEEL_RADIUS, -L * 0.5 + 1.9)
		body_pivot.add_child(pivot)
		var spinner := _make_wheel(pivot, tire, rim, side)
		wheel_pivots.append(pivot)
		wheel_spinners.append(spinner)
		var rear := Node3D.new()
		rear.position = Vector3(side * 1.0, WHEEL_RADIUS, L * 0.5 - 2.6)
		body_pivot.add_child(rear)
		wheel_spinners.append(_make_wheel(rear, tire, rim, side))
	# Headlight spots (only at night)
	if night:
		for x in [-0.85, 0.85]:
			var spot := SpotLight3D.new()
			spot.position = Vector3(x, 1.1, -L * 0.5)
			spot.rotation_degrees = Vector3(-6.0, 0, 0)
			spot.spot_range = 45.0
			spot.spot_angle = 32.0
			spot.light_energy = 4.0
			spot.light_color = Color(1.0, 0.95, 0.85)
			spot.shadow_enabled = false
			body_pivot.add_child(spot)
			headlights.append(spot)


func _make_wheel(parent: Node3D, tire: Material, rim: Material, side: float) -> Node3D:
	var spinner := Node3D.new()
	parent.add_child(spinner)
	var mesh := CylinderMesh.new()
	mesh.top_radius = WHEEL_RADIUS
	mesh.bottom_radius = WHEEL_RADIUS
	mesh.height = 0.42
	mesh.radial_segments = 18
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = tire
	mi.rotation.z = PI * 0.5
	spinner.add_child(mi)
	var hub := CylinderMesh.new()
	hub.top_radius = WHEEL_RADIUS * 0.55
	hub.bottom_radius = WHEEL_RADIUS * 0.55
	hub.height = 0.44
	hub.radial_segments = 12
	var hub_mi := MeshInstance3D.new()
	hub_mi.mesh = hub
	hub_mi.material_override = rim
	hub_mi.rotation.z = PI * 0.5
	spinner.add_child(hub_mi)
	# Visible spoke so the wheel rotation reads well.
	MeshFactory.box(spinner, Vector3(0.46, 0.12, WHEEL_RADIUS * 1.1), Vector3(0, 0, 0), MeshFactory.mat(Color(0.3, 0.3, 0.32), 0.5, 0.5))
	return spinner


# ---------------------------------------------------------------- physics
func _physics_process(delta: float) -> void:
	_collision_cooldown = maxf(0.0, _collision_cooldown - delta)
	_horn_cooldown = maxf(0.0, _horn_cooldown - delta)
	var throttle := clampf(input_throttle, 0.0, 1.0)
	var brake := clampf(input_brake, 0.0, 1.0)
	var steer := clampf(input_steer, -1.0, 1.0)
	if doors_open or not engine_on:
		throttle = 0.0
		brake = maxf(brake, 1.0 if doors_open else 0.0)
	# Reverse: keep holding the brake while standing still and the bus backs up slowly.
	if brake > 0.3 and speed <= 0.05 and throttle <= 0.0 and not doors_open:
		_reverse_hold += delta
	else:
		_reverse_hold = 0.0
	reverse_gear = _reverse_hold > REVERSE_HOLD_TIME
	# Longitudinal dynamics
	var accel := 0.0
	if throttle > 0.0:
		if speed < -0.05:
			accel += throttle * BRAKE_DECEL
		else:
			accel += throttle * ENGINE_ACCEL * (1.0 - clampf(speed / MAX_SPEED, 0.0, 0.95))
	if reverse_gear:
		accel -= brake * REVERSE_ACCEL * (1.0 - clampf(absf(speed) / MAX_REVERSE, 0.0, 0.95))
	elif brake > 0.0 and absf(speed) > 0.01:
		accel -= signf(speed) * brake * BRAKE_DECEL
	if throttle <= 0.0 and not reverse_gear and absf(speed) > 0.01:
		accel -= signf(speed) * ENGINE_BRAKE
	accel -= speed * DRAG
	var new_speed := speed + accel * delta
	# Braking must never flip the direction of motion.
	if not reverse_gear and throttle <= 0.0 and speed != 0.0 and signf(new_speed) != signf(speed):
		new_speed = 0.0
	speed = clampf(new_speed, -MAX_REVERSE, MAX_SPEED)
	if absf(speed) < 0.02 and throttle <= 0.0 and not reverse_gear:
		speed = 0.0
	# Steering
	var speed_ratio := clampf(absf(speed) / MAX_SPEED, 0.0, 1.0)
	var max_steer := lerpf(MAX_STEER_LOW, MAX_STEER_HIGH, speed_ratio)
	var target_steer := steer * max_steer
	var rate := STEER_RATE if absf(target_steer) > absf(steer_angle) else STEER_RETURN_RATE
	steer_angle = move_toward(steer_angle, target_steer, rate * delta)
	if absf(speed) > 0.01:
		var yaw_rate := speed / WHEELBASE * tan(steer_angle)
		rotate_y(-yaw_rate * delta)
	# Gravity / ground
	if is_on_floor():
		_vertical_velocity = 0.0
	else:
		_vertical_velocity -= 9.8 * delta
	var forward := -global_transform.basis.z
	var planned := forward * speed
	velocity = Vector3(planned.x, _vertical_velocity, planned.z)
	move_and_slide()
	# Collision response: compare what we wanted with what actually happened.
	var actual := get_real_velocity()
	var actual_flat := Vector3(actual.x, 0.0, actual.z)
	var lost := (planned - actual_flat).length()
	if lost > 1.2 and _collision_cooldown <= 0.0:
		var strength := lost
		speed = forward.dot(actual_flat) * 0.6
		_collision_cooldown = 0.6
		collided.emit(strength)
	elif lost > 0.3:
		speed = forward.dot(actual_flat)
	_update_visuals(delta, throttle, brake)


func _update_visuals(delta: float, throttle: float, brake: float) -> void:
	# Wheel spin and steering.
	var spin := speed * delta / WHEEL_RADIUS
	for s in wheel_spinners:
		s.rotate_x(-spin)
	for p in wheel_pivots:
		p.rotation.y = -steer_angle
	# Body roll and pitch.
	var direction_sign := signf(speed) if absf(speed) > 0.01 else 1.0
	var target_roll := steer_angle * clampf(absf(speed) / 8.0, 0.0, 1.0) * 0.12 * direction_sign
	var target_pitch := -brake * 0.025 * direction_sign + throttle * 0.015
	body_pivot.rotation.z = lerpf(body_pivot.rotation.z, target_roll, 5.0 * delta)
	body_pivot.rotation.x = lerpf(body_pivot.rotation.x, target_pitch, 4.0 * delta)
	# Lights.
	if brake_light_mat:
		brake_light_mat.emission_energy_multiplier = 3.0 if brake > 0.1 else (0.8 if night else 0.3)
	if reverse_light_mat:
		reverse_light_mat.emission_energy_multiplier = 2.5 if (reverse_gear or speed < -0.05) else 0.0
	# Engine audio.
	var rpm := clampf(absf(speed) / MAX_SPEED, 0.0, 1.0) * 0.75 + throttle * 0.25
	AudioSynth.set_engine(rpm, throttle, engine_on)


# ---------------------------------------------------------------- actions
func toggle_doors() -> bool:
	if absf(speed) > 0.6:
		return false
	set_doors(not doors_open)
	return true


func set_doors(open: bool) -> void:
	if doors_open == open:
		return
	doors_open = open
	if _door_tween and _door_tween.is_valid():
		_door_tween.kill()
	_door_tween = create_tween().set_parallel(true)
	var offset := 1.05 if open else 0.0
	var out := 0.12 if open else 0.0
	var base_x := 2.5 * 0.5 + 0.02
	# Door leaves slide outwards and backwards along the body.
	_door_tween.tween_property(door_front, "position", Vector3(base_x + out, 0.0, -11.0 * 0.5 + 1.9 + offset), 0.55).set_trans(Tween.TRANS_SINE)
	_door_tween.tween_property(door_rear, "position", Vector3(base_x + out, 0.0, 0.8 + offset), 0.55).set_trans(Tween.TRANS_SINE)
	AudioSynth.play("door", -4.0)
	doors_changed.emit(open)


func honk() -> void:
	if _horn_cooldown > 0.0:
		return
	_horn_cooldown = 0.7
	AudioSynth.play("horn", -2.0, randf_range(0.97, 1.03))
	horn_sounded.emit()


func speed_kmh() -> float:
	return absf(speed) * 3.6


## World position of the front door (used by passengers).
func front_door_position() -> Vector3:
	return to_global(Vector3(1.8, 0.0, -11.0 * 0.5 + 1.9))


func rear_door_position() -> Vector3:
	return to_global(Vector3(1.8, 0.0, 0.8))


func apply_damage(amount: float) -> void:
	damage = clampf(damage + amount, 0.0, 100.0)


func stop_immediately() -> void:
	speed = 0.0
	input_throttle = 0.0
	input_brake = 0.0
