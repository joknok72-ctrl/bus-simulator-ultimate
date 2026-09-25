class_name Bus
extends CharacterBody3D
## The player's city bus. Arcade-style kinematic vehicle model tuned for touch
## controls: throttle/brake pedals, steering in -1..1, doors and horn.
## -Z is forward, +X is the curb (door) side. Emits signals consumed by the
## mission controller. The body is built from primitives in code, including a
## real cabin interior so the driver-seat camera has something to look at.

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
const HAND_WHEEL_MAX := deg_to_rad(150.0)   # visual steering wheel rotation at full lock

# --- body geometry (bus-local metres) ----------------------------------------
const LENGTH := 11.0
const WIDTH := 2.5
const FRONT_DOOR_Z := -LENGTH * 0.5 + 1.9
const REAR_DOOR_Z := 0.8
const FLOOR_Y := 1.03                  # top of the cabin floor
const CEILING_Y := 2.97                # underside of the cabin ceiling
const DASH_TOP_Y := 1.86               # driver-side dashboard top
const ENTRANCE_DASH_TOP_Y := 1.62      # lower panel on the door side
## Driver's eye point (left-hand drive), about 1.7 m behind the windshield and 0.75 m
## above the dashboard: the road, the dash top and the upper half of the steering wheel
## are all in frame, and no pillar or panel comes closer than ~0.3 m to the camera.
const DRIVER_EYE := Vector3(-0.72, 2.6, -3.75)
const HAND_WHEEL_POS := Vector3(-0.72, 2.06, -4.42)
const HAND_WHEEL_RADIUS := 0.22
const HAND_WHEEL_TILT := deg_to_rad(50.0)   # wheel axis tilted up towards the driver

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
var _hand_wheel_spin := 0.0

# --- visual nodes --------------------------------------------------------------
var body_pivot: Node3D
var wheel_pivots: Array[Node3D] = []      # steering pivots (front wheels)
var wheel_spinners: Array[Node3D] = []    # rolling wheels
var door_front: Node3D
var door_rear: Node3D
var headlights: Array[SpotLight3D] = []
var brake_light_mat: StandardMaterial3D
var reverse_light_mat: StandardMaterial3D
var hand_wheel: Node3D                    # cockpit steering wheel (rotates with input)
var smoke: CPUParticles3D                 # engine-bay smoke, grows with damage
var chase_mount: Node3D
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
	top_mount = get_node_or_null("Mounts/TopMount")
	_build_visual()
	_build_smoke()


func configure(color: Color, is_night: bool) -> void:
	livery_color = color
	night = is_night
	# Rebuild the paintwork with the chosen livery.
	for child in body_pivot.get_children():
		child.queue_free()
	wheel_pivots.clear()
	wheel_spinners.clear()
	headlights.clear()
	hand_wheel = null
	_build_visual()


# ---------------------------------------------------------------- visuals
## Everything that never moves relative to the body (shell, glass, interior, lights, mirrors)
## is baked into ONE mesh with one surface per material (see MeshMerger): ~15 draw calls
## instead of ~110. Doors, wheels and the cockpit steering wheel stay separate nodes
## because they are animated.
func _build_visual() -> void:
	var L := LENGTH
	var W := WIDTH
	var half_l := L * 0.5
	var half_w := W * 0.5
	var paint := MeshFactory.mat(livery_color, 0.35, 0.3)
	var paint_dark := MeshFactory.mat(livery_color.darkened(0.15), 0.4, 0.3)
	var trim := MeshFactory.mat(Color(0.92, 0.92, 0.94), 0.4, 0.2)
	var dark := MeshFactory.mat(Color(0.08, 0.08, 0.09), 0.85)
	var chrome := MeshFactory.mat(Color(0.75, 0.77, 0.8), 0.2, 0.9)
	# Side windows are tinted; the windshield is nearly clear so the driver view stays bright.
	# Low metallic: seen from the driver's seat at grazing angles the panes must not turn
	# into sky mirrors.
	var side_glass := MeshFactory.glass_mat(Color(0.3, 0.45, 0.6, 0.34), 0.05, 0.3)
	var front_glass := MeshFactory.glass_mat(Color(0.6, 0.75, 0.88, 0.12), 0.0, 0.35)
	var body := MeshMerger.new()
	_build_shell(body, L, W, half_l, half_w, paint, paint_dark, trim, dark, chrome, side_glass, front_glass)
	_build_interior(body, L, W, half_l, half_w, dark)
	# Opaque surfaces were added first, glass last, so the panes blend over the interior.
	body.instance(body_pivot, "Shell")
	_build_wheels(half_l)
	# Headlight spots (only at night)
	if night:
		for x in [-0.85, 0.85]:
			var spot := SpotLight3D.new()
			spot.position = Vector3(x, 1.1, -half_l)
			spot.rotation_degrees = Vector3(-6.0, 0, 0)
			spot.spot_range = 45.0
			spot.spot_angle = 32.0
			spot.light_energy = 4.0
			spot.light_color = Color(1.0, 0.95, 0.85)
			spot.shadow_enabled = false
			body_pivot.add_child(spot)
			headlights.append(spot)


func _build_shell(body: MeshMerger, L: float, W: float, half_l: float, half_w: float, paint: Material, paint_dark: Material,
		trim: Material, dark: Material, chrome: Material, side_glass: Material, front_glass: Material) -> void:
	var pillar := MeshFactory.mat(Color(0.12, 0.12, 0.13), 0.7)
	# Lower body (side skirts up to the window sill at y=1.8). It stops at the dashboard so the
	# deep windshield looks into the cabin instead of at a painted wall.
	var cab_z := -half_l + 0.95
	body.add_box(Vector3(W, 1.3, half_l - cab_z), Vector3(0, 1.15, (half_l + cab_z) * 0.5), paint)
	for side in [-1.0, 1.0]:
		body.add_box(Vector3(0.08, 1.3, cab_z + half_l), Vector3(side * (half_w - 0.04), 1.15, (cab_z - half_l) * 0.5), paint)
	# Front panel below the windshield, then the blacked-out A-pillars.
	body.add_box(Vector3(W, 0.66, 0.12), Vector3(0, 0.83, -half_l + 0.06), paint)
	for side in [-1.0, 1.0]:
		body.add_box(Vector3(0.1, 1.86, 0.12), Vector3(side * (half_w - 0.05), 2.09, -half_l + 0.06), pillar)
	# Rear corner pillars and window pillars on each side (thin - the cabin between them stays open).
	for side in [-1.0, 1.0]:
		body.add_box(Vector3(0.1, 1.2, 0.1), Vector3(side * (half_w - 0.05), 2.4, half_l - 0.05), pillar)
	for i in 6:
		var z := -half_l + 1.2 + i * 1.75
		for side in [-1.0, 1.0]:
			body.add_box(Vector3(0.1, 1.2, 0.12), Vector3(side * (half_w - 0.03), 2.4, z), pillar)
	# Roof band, roof and AC unit.
	body.add_box(Vector3(W, 0.32, L), Vector3(0, 3.16, 0), trim)
	body.add_box(Vector3(W - 0.3, 0.14, L - 0.4), Vector3(0, 3.38, 0), trim)
	body.add_box(Vector3(1.4, 0.35, 2.2), Vector3(0, 3.6, 1.0), trim)
	# Destination sign on the front roof band.
	body.add_box(Vector3(W - 0.5, 0.26, 0.06), Vector3(0, 3.16, -half_l - 0.02), MeshFactory.mat(Color(0.95, 0.65, 0.1), 0.4, 0.0, Color(1.0, 0.7, 0.1), 2.0))
	# Bumpers and rear engine grille.
	body.add_box(Vector3(W, 0.45, 0.3), Vector3(0, 0.62, -half_l - 0.1), dark)
	body.add_box(Vector3(W, 0.45, 0.3), Vector3(0, 0.62, half_l + 0.1), dark)
	body.add_box(Vector3(W - 0.6, 0.8, 0.06), Vector3(0, 1.35, half_l + 0.02), dark)
	# Headlights
	var head_mat := MeshFactory.mat(Color(1, 1, 0.95), 0.2, 0.0, Color(1.0, 0.95, 0.85), 3.0 if night else 0.3)
	for x in [-0.85, 0.85]:
		body.add_box(Vector3(0.45, 0.26, 0.06), Vector3(x, 0.95, -half_l - 0.03), head_mat)
	# Tail lights (brake) and reverse lights. The materials are shared by the merged surfaces,
	# so changing their emission later still lights the lamps up.
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
		body.add_box(Vector3(0.4, 0.3, 0.06), Vector3(x, 1.3, half_l + 0.03), brake_light_mat)
		body.add_box(Vector3(0.25, 0.18, 0.06), Vector3(x, 0.98, half_l + 0.03), reverse_light_mat)
	# Mirrors on short arms.
	for x in [-1.45, 1.45]:
		var inward := 1.0 if x < 0 else -1.0
		body.add_box(Vector3(0.12, 0.45, 0.25), Vector3(x, 2.5, -half_l + 0.6), dark)
		body.add_box(Vector3(0.06, 0.4, 0.04), Vector3(x + inward * 0.05, 2.5, -half_l + 0.5), chrome)
		body.add_box(Vector3(0.3, 0.04, 0.04), Vector3(x + inward * 0.18, 2.7, -half_l + 0.6), chrome)
	# Door frames (dark openings visible when doors slide open)
	for z in [FRONT_DOOR_Z, REAR_DOOR_Z]:
		body.add_box(Vector3(0.04, 2.2, 1.4), Vector3(half_w - 0.06, 1.55, z), dark)
	# Doors on the right side (curb side); each leaf is its own small mesh because it slides.
	door_front = Node3D.new()
	door_front.name = "DoorFront"
	door_front.position = Vector3(half_w + 0.02, 0, FRONT_DOOR_Z)
	body_pivot.add_child(door_front)
	door_rear = Node3D.new()
	door_rear.name = "DoorRear"
	door_rear.position = Vector3(half_w + 0.02, 0, REAR_DOOR_Z)
	body_pivot.add_child(door_rear)
	for door in [door_front, door_rear]:
		var leaf := MeshMerger.new()
		leaf.add_box(Vector3(0.06, 2.1, 1.3), Vector3(0, 1.6, 0), paint_dark)
		leaf.add_box(Vector3(0.07, 1.0, 1.1), Vector3(0, 2.0, 0), side_glass)
		leaf.instance(door, "Leaf")
	# Glass last (drawn after the opaque interior it is seen through).
	# Windshield: one clear pane from the bumper line up to the roof band.
	body.add_box(Vector3(W - 0.2, 1.86, 0.05), Vector3(0, 2.09, -half_l + 0.03), front_glass)
	# Side windows: thin panes (not a solid glass block) so the cabin is open inside.
	var glass_len := L - 0.14 - 0.04
	for side in [-1.0, 1.0]:
		body.add_box(Vector3(0.04, 1.2, glass_len), Vector3(side * (half_w - 0.02), 2.4, 0.05), side_glass)
	# Rear window.
	body.add_box(Vector3(W - 0.16, 1.2, 0.04), Vector3(0, 2.4, half_l - 0.02), side_glass)


func _build_interior(body: MeshMerger, L: float, W: float, half_l: float, _half_w: float, _dark: Material) -> void:
	var interior_dark := MeshFactory.mat(Color(0.13, 0.13, 0.15), 0.9)
	var dash_mat := MeshFactory.mat(Color(0.1, 0.1, 0.12), 0.85)
	var dash_top_mat := MeshFactory.mat(Color(0.2, 0.2, 0.22), 0.9)
	var floor_mat := MeshFactory.mat(Color(0.24, 0.25, 0.27), 0.95)
	var ceiling_mat := MeshFactory.mat(Color(0.88, 0.88, 0.86), 0.9, 0.0, Color(1.0, 0.95, 0.85), 0.3 if night else 0.0)
	var seat_mat := MeshFactory.mat(Color(0.2, 0.3, 0.55), 0.9)
	var rail_mat := MeshFactory.mat(Color(0.95, 0.75, 0.15), 0.4, 0.4)
	var rubber := MeshFactory.mat(Color(0.1, 0.1, 0.11), 0.95)
	# Floor and ceiling (their inner faces are what the driver camera sees).
	body.add_box(Vector3(W - 0.1, 0.06, L - 0.2), Vector3(0, FLOOR_Y - 0.03, 0), floor_mat)
	body.add_box(Vector3(W - 0.16, 0.03, L - 0.2), Vector3(0, CEILING_Y + 0.015, 0), ceiling_mat)
	# Dark header panel above the windshield (sun strip / destination sign housing). It reaches
	# back over the driver so the camera never looks at a bright ceiling at the top of the frame.
	body.add_box(Vector3(W - 0.2, 0.1, 0.7), Vector3(0, CEILING_Y - 0.05, -half_l + 0.42), interior_dark)
	# Interior wall panels below the windows. The outer shell is back-face culled from inside,
	# so without these the driver would see the road through the body under the side windows.
	var wall_mat := MeshFactory.mat(Color(0.3, 0.31, 0.34), 0.9)
	var wall_h := 1.8 - FLOOR_Y
	var wall_y := (1.8 + FLOOR_Y) * 0.5
	var wall_x := W * 0.5 - 0.11   # just inside the 0.08 m side skirts, no coplanar faces
	body.add_box(Vector3(0.04, wall_h, L - 0.3), Vector3(-wall_x, wall_y, 0.02), wall_mat)
	# Curb side: three panels that leave the two door openings free.
	var door_half := 0.72
	var segments := [
		[-half_l + 0.14, FRONT_DOOR_Z - door_half],
		[FRONT_DOOR_Z + door_half, REAR_DOOR_Z - door_half],
		[REAR_DOOR_Z + door_half, half_l - 0.14],
	]
	for seg in segments:
		var z0: float = seg[0]
		var z1: float = seg[1]
		if z1 - z0 < 0.05:
			continue
		body.add_box(Vector3(0.04, wall_h, z1 - z0), Vector3(wall_x, wall_y, (z0 + z1) * 0.5), wall_mat)
	# Driver-side dashboard (deep, tall) and the lower panel on the entrance side.
	var dash_front := -half_l + 0.07
	body.add_box(Vector3(1.15, DASH_TOP_Y - 1.1, 0.56), Vector3(-0.625, (DASH_TOP_Y + 1.1) * 0.5, dash_front + 0.28), dash_mat)
	body.add_box(Vector3(1.15, 0.04, 0.58), Vector3(-0.625, DASH_TOP_Y + 0.02, dash_front + 0.28), dash_top_mat)
	body.add_box(Vector3(1.25, ENTRANCE_DASH_TOP_Y - 1.1, 0.45), Vector3(0.575, (ENTRANCE_DASH_TOP_Y + 1.1) * 0.5, dash_front + 0.225), dash_mat)
	body.add_box(Vector3(1.25, 0.04, 0.47), Vector3(0.575, ENTRANCE_DASH_TOP_Y + 0.02, dash_front + 0.225), dash_top_mat)
	# Instrument binnacle on the dash in front of the driver, tilted towards the eye, with a glowing display.
	var binnacle_basis := Basis.from_euler(Vector3(deg_to_rad(-18.0), 0.0, 0.0))
	var binnacle_pos := Vector3(DRIVER_EYE.x, DASH_TOP_Y + 0.08, dash_front + 0.5)
	body.add_box(Vector3(0.46, 0.15, 0.14), binnacle_pos, interior_dark, binnacle_basis)
	body.add_box(Vector3(0.38, 0.09, 0.02), binnacle_pos + binnacle_basis * Vector3(0, 0.0, 0.075),
		MeshFactory.mat(Color(0.05, 0.09, 0.13), 0.3, 0.0, Color(0.3, 0.75, 1.0), 1.0 if night else 0.7), binnacle_basis)
	# Warm cabin light at night so the dashboard, wheel and seats are not pitch black.
	if night:
		var cabin_light := OmniLight3D.new()
		cabin_light.position = Vector3(-0.2, CEILING_Y - 0.12, -4.1)
		cabin_light.omni_range = 5.0
		cabin_light.light_energy = 0.9
		cabin_light.light_color = Color(1.0, 0.9, 0.75)
		cabin_light.shadow_enabled = false
		body_pivot.add_child(cabin_light)
	# Steering column (static) and the hand wheel (rotated in _update_visuals).
	var axis := Vector3(0, cos(HAND_WHEEL_TILT), sin(HAND_WHEEL_TILT))   # wheel axis, up towards the driver
	body.add_cylinder(0.035, 0.5, HAND_WHEEL_POS - axis * 0.25, interior_dark, Vector3(HAND_WHEEL_TILT, 0, 0), 8)
	hand_wheel = Node3D.new()
	hand_wheel.name = "HandWheel"
	hand_wheel.position = HAND_WHEEL_POS
	hand_wheel.rotation.x = HAND_WHEEL_TILT
	body_pivot.add_child(hand_wheel)
	var wheel_mesh := MeshMerger.new()
	var rim := TorusMesh.new()
	rim.inner_radius = HAND_WHEEL_RADIUS - 0.03
	rim.outer_radius = HAND_WHEEL_RADIUS + 0.03
	rim.rings = 32
	rim.ring_segments = 10
	wheel_mesh.add(rim, Transform3D.IDENTITY, rubber)
	wheel_mesh.add_cylinder(0.075, 0.06, Vector3.ZERO, interior_dark, Vector3.ZERO, 12)
	for spoke_angle in [PI * 0.5, -PI * 0.5, PI]:
		var arm := Basis(Vector3.UP, spoke_angle)
		wheel_mesh.add_box(Vector3(0.05, 0.03, HAND_WHEEL_RADIUS), arm * Vector3(0, 0, -HAND_WHEEL_RADIUS * 0.5), interior_dark, arm)
	# Top marker on the rim so the rotation reads well.
	wheel_mesh.add_box(Vector3(0.05, 0.04, 0.07), Vector3(0, 0, -HAND_WHEEL_RADIUS), MeshFactory.mat(Color(0.9, 0.3, 0.25), 0.5))
	wheel_mesh.instance(hand_wheel, "Mesh")
	# Driver seat on a raised platform (the eye point sits above the cushion).
	body.add_box(Vector3(0.9, 0.22, 0.9), Vector3(DRIVER_EYE.x, FLOOR_Y + 0.11, -3.8), interior_dark)
	body.add_box(Vector3(0.6, 0.14, 0.55), Vector3(DRIVER_EYE.x, 1.62, -3.8), rubber)
	body.add_box(Vector3(0.6, 0.8, 0.12), Vector3(DRIVER_EYE.x, 2.1, -3.47), rubber)
	# Passenger seats: cushion + backrest, no seat in front of the rear door.
	for i in 5:
		var z := -half_l + 3.4 + i * 1.5
		for x in [-0.72, 0.72]:
			if x > 0.0 and absf(z - REAR_DOOR_Z) < 0.95:
				continue
			body.add_box(Vector3(0.3, 0.42, 0.3), Vector3(x, FLOOR_Y + 0.21, z), interior_dark)
			body.add_box(Vector3(0.85, 0.12, 0.5), Vector3(x, 1.5, z), seat_mat)
			body.add_box(Vector3(0.85, 0.7, 0.1), Vector3(x, 1.9, z + 0.25), seat_mat)
	# Yellow handrails along the ceiling and a pole at each door.
	for x in [-0.45, 0.45]:
		body.add_cylinder(0.02, L - 4.0, Vector3(x, CEILING_Y - 0.25, 1.4), rail_mat, Vector3(PI * 0.5, 0, 0), 6)
	for z in [FRONT_DOOR_Z + 0.85, REAR_DOOR_Z + 0.85]:
		body.add_cylinder(0.02, CEILING_Y - FLOOR_Y, Vector3(0.75, (CEILING_Y + FLOOR_Y) * 0.5, z), rail_mat, Vector3.ZERO, 6)


## Grey smoke from the rear engine bay once the bus is badly damaged, so the damage bar has
## a visible counterpart in the chase view. One CPUParticles3D = one draw call.
func _build_smoke() -> void:
	smoke = CPUParticles3D.new()
	smoke.name = "DamageSmoke"
	smoke.emitting = false
	smoke.amount = 40
	smoke.lifetime = 2.4
	# Just above the rear roof edge (the engine bay), outside the cabin glass. World-space
	# particles (local_coords = false) so the plume trails behind the moving bus.
	smoke.position = Vector3(0.5, 3.5, LENGTH * 0.5 - 0.3)
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 0.35
	smoke.direction = Vector3(0.0, 1.0, 0.45)
	smoke.spread = 32.0
	smoke.gravity = Vector3(0, 1.6, 0)          # hot smoke keeps rising
	smoke.initial_velocity_min = 1.2
	smoke.initial_velocity_max = 2.4
	smoke.scale_amount_min = 0.55
	smoke.scale_amount_max = 0.95
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.3))
	grow.add_point(Vector2(0.35, 1.0))
	grow.add_point(Vector2(1.0, 1.7))
	smoke.scale_amount_curve = grow
	# Mid-grey plume that fades out; the per-damage tint in _update_smoke darkens it.
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.58, 0.58, 0.6, 0.0))
	ramp.add_point(0.12, Color(0.55, 0.55, 0.58, 0.9))
	ramp.add_point(0.55, Color(0.45, 0.45, 0.48, 0.65))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.38, 0.38, 0.4, 0.0))
	smoke.color_ramp = ramp
	# Soft round puffs: a camera-facing quad with a procedural radial gradient.
	var puff := QuadMesh.new()
	puff.size = Vector2(1.4, 1.4)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1.0))
	gradient.add_point(0.45, Color(1, 1, 1, 0.55))
	gradient.set_color(gradient.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	# Without keep_scale the particle billboard ignores the per-particle scale, so every puff
	# (including the not-yet-emitted ones, which sit at the emitter with a zero transform and
	# an opaque black default colour) would render at full quad size: a black blob on the roof.
	mat.billboard_keep_scale = true
	mat.no_depth_test = false
	puff.material = mat
	smoke.mesh = puff
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(smoke)


func _update_smoke() -> void:
	if smoke == null:
		return
	var t := clampf((damage - 35.0) / 65.0, 0.0, 1.0)
	smoke.emitting = t > 0.0
	smoke.speed_scale = lerpf(0.9, 1.4, t)
	smoke.scale_amount_max = lerpf(0.95, 1.5, t)
	# Light grey at first, sootier as the damage grows.
	smoke.color = Color(1.0, 1.0, 1.0).darkened(t * 0.4)


func _build_wheels(half_l: float) -> void:
	# Wheels: 2 front (steer) + 4 rear (dual)
	var rim := MeshFactory.mat(Color(0.7, 0.7, 0.72), 0.3, 0.8)
	var tire := MeshFactory.mat(Color(0.06, 0.06, 0.07), 0.95)
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(side * 1.0, WHEEL_RADIUS, -half_l + 1.9)
		body_pivot.add_child(pivot)
		var spinner := _make_wheel(pivot, tire, rim, side)
		wheel_pivots.append(pivot)
		wheel_spinners.append(spinner)
		var rear := Node3D.new()
		rear.position = Vector3(side * 1.0, WHEEL_RADIUS, half_l - 2.6)
		body_pivot.add_child(rear)
		wheel_spinners.append(_make_wheel(rear, tire, rim, side))


func _make_wheel(parent: Node3D, tire: Material, rim: Material, _side: float) -> Node3D:
	var spinner := Node3D.new()
	parent.add_child(spinner)
	# Tyre, hub and a visible spoke in one mesh (the spoke makes the rotation read well).
	var m := MeshMerger.new()
	m.add_cylinder(WHEEL_RADIUS, 0.42, Vector3.ZERO, tire, Vector3(0, 0, PI * 0.5), 18)
	m.add_cylinder(WHEEL_RADIUS * 0.55, 0.44, Vector3.ZERO, rim, Vector3(0, 0, PI * 0.5), 12)
	m.add_box(Vector3(0.46, 0.12, WHEEL_RADIUS * 1.1), Vector3.ZERO, MeshFactory.mat(Color(0.3, 0.3, 0.32), 0.5, 0.5))
	m.instance(spinner, "Mesh")
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


## Current yaw rate of the bus in rad/s (positive = turning right). Used by the camera
## to look into turns.
func yaw_rate() -> float:
	if absf(speed) < 0.05:
		return 0.0
	return speed / WHEELBASE * tan(steer_angle)


func _update_visuals(delta: float, throttle: float, brake: float) -> void:
	# Wheel spin and steering.
	var spin := speed * delta / WHEEL_RADIUS
	for s in wheel_spinners:
		s.rotate_x(-spin)
	for p in wheel_pivots:
		p.rotation.y = -steer_angle
	# Cockpit steering wheel follows the steering input (matches the touch wheel).
	if hand_wheel != null:
		var target_spin := clampf(input_steer, -1.0, 1.0) * HAND_WHEEL_MAX
		_hand_wheel_spin = lerpf(_hand_wheel_spin, target_spin, clampf(delta * 12.0, 0.0, 1.0))
		hand_wheel.basis = Basis.from_euler(Vector3(HAND_WHEEL_TILT, 0.0, 0.0)) * Basis(Vector3.UP, -_hand_wheel_spin)
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
	# Runs on physics ticks so the animation stays smooth with physics interpolation.
	_door_tween = create_tween().set_parallel(true).set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	var offset := 1.05 if open else 0.0
	var out := 0.12 if open else 0.0
	var base_x := WIDTH * 0.5 + 0.02
	# Door leaves slide outwards and backwards along the body.
	_door_tween.tween_property(door_front, "position", Vector3(base_x + out, 0.0, FRONT_DOOR_Z + offset), 0.55).set_trans(Tween.TRANS_SINE)
	_door_tween.tween_property(door_rear, "position", Vector3(base_x + out, 0.0, REAR_DOOR_Z + offset), 0.55).set_trans(Tween.TRANS_SINE)
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
	return to_global(Vector3(1.8, 0.0, FRONT_DOOR_Z))


func rear_door_position() -> Vector3:
	return to_global(Vector3(1.8, 0.0, REAR_DOOR_Z))


## World-space transform of the driver's eye point, including body roll and pitch.
func driver_eye_transform() -> Transform3D:
	var cab := body_pivot.global_transform
	return Transform3D(cab.basis, cab * DRIVER_EYE)


func apply_damage(amount: float) -> void:
	damage = clampf(damage + amount, 0.0, 100.0)
	_update_smoke()


func stop_immediately() -> void:
	speed = 0.0
	input_throttle = 0.0
	input_brake = 0.0
