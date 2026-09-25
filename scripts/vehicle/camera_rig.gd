class_name CameraRig
extends Node3D
## Camera rig with three views, blended smoothly when the player switches:
##  * DRIVER - first-person view from the driver's seat (Bus.DRIVER_EYE). The camera is
##    rigidly attached to the cabin so it rolls and pitches with the body, looks slightly
##    into turns, vibrates a little with speed and widens its field of view at speed.
##  * CHASE  - smooth follow camera behind the bus that never clips through buildings.
##  * TOP    - high follow camera for an overview of the road ahead.

const DRIVER_FOV := 63.0
const CHASE_FOV := 66.0
const TOP_FOV := 60.0
const DRIVER_PITCH := deg_to_rad(-5.0)      # look slightly down: horizon a little above centre
const LOOK_INTO_TURN := 0.55                # rad of yaw per rad/s of bus yaw rate
const LOOK_INTO_TURN_MAX := deg_to_rad(15.0)
const BLEND_TIME := 0.45
const FOLLOW_SMOOTHING := 6.0
const OBSTACLE_MARGIN := 0.5

@export var bus_path: NodePath
@onready var camera: Camera3D = $Camera3D

var bus: Bus
var mode: int = GameState.CameraMode.CHASE

var _shake := 0.0
var _initialized := false
var _follow_pos := Vector3.ZERO
var _look_yaw := 0.0
var _blend_from := Transform3D.IDENTITY
var _blend_t := 1.0          # 1 = no blend in progress


func _ready() -> void:
	# Update strictly after the bus has moved in this physics tick; otherwise a rigidly
	# attached cockpit camera would trail the cabin by one tick and the interior would
	# appear to slide when accelerating or braking.
	process_physics_priority = 20
	if bus_path != NodePath(""):
		bus = get_node_or_null(bus_path) as Bus
	mode = clampi(int(GameState.settings.camera), 0, 2)
	camera.current = true
	camera.fov = _base_fov()
	camera.near = 0.15
	camera.far = 600.0


func set_bus(target: Bus) -> void:
	bus = target
	_initialized = false
	_blend_t = 1.0


func cycle_mode() -> void:
	set_mode((mode + 1) % 3)


func set_mode(new_mode: int) -> void:
	new_mode = clampi(new_mode, 0, 2)
	if new_mode == mode:
		return
	if _initialized:
		# Blend from wherever the camera is now to the new view.
		_blend_from = global_transform
		_blend_t = 0.0
	mode = new_mode
	_initialized = false
	_look_yaw = 0.0
	GameState.set_setting("camera", mode)


func add_shake(amount: float) -> void:
	_shake = minf(_shake + amount, 1.0)


func is_driver_view() -> bool:
	return mode == GameState.CameraMode.DRIVER


func _base_fov() -> float:
	match mode:
		GameState.CameraMode.DRIVER:
			return DRIVER_FOV
		GameState.CameraMode.TOP:
			return TOP_FOV
		_:
			return CHASE_FOV


func _physics_process(delta: float) -> void:
	if bus == null or not is_instance_valid(bus):
		return
	var snapped := not _initialized
	var target: Transform3D
	match mode:
		GameState.CameraMode.DRIVER:
			target = _driver_transform(delta)
		GameState.CameraMode.TOP:
			target = _follow_transform(delta, bus.top_mount, 0.0, 5.0, 0.0, 1.5)
		_:
			target = _follow_transform(delta, bus.chase_mount, 1.8, 3.0, 2.0, 0.6)
	if _blend_t < 1.0:
		_blend_t = minf(1.0, _blend_t + delta / BLEND_TIME)
		var w := smoothstep(0.0, 1.0, _blend_t)
		global_transform = _blend_from.interpolate_with(target, w)
	else:
		global_transform = target
	if snapped and _blend_t >= 1.0:
		# First frame after (re)targeting: do not interpolate from the old position.
		reset_physics_interpolation()
	_apply_camera_effects(delta)


## First-person transform at the driver's eye, in cabin space (follows body roll/pitch).
func _driver_transform(delta: float) -> Transform3D:
	var eye := bus.driver_eye_transform()
	# Look into the turn proportionally to how fast the bus is actually rotating, so
	# turning the wheel at a standstill does not swing the view.
	var target_yaw := clampf(-bus.yaw_rate() * LOOK_INTO_TURN, -LOOK_INTO_TURN_MAX, LOOK_INTO_TURN_MAX)
	_look_yaw = lerpf(_look_yaw, target_yaw, 1.0 - exp(-delta * 3.5))
	var basis := eye.basis.rotated(eye.basis.y.normalized(), _look_yaw)
	basis = basis.rotated(basis.x.normalized(), DRIVER_PITCH)
	_initialized = true
	return Transform3D(basis, eye.origin)


## Smoothed follow transform for the chase / top views.
## look_height / look_ahead define the aim point relative to the bus; pull_back / pull_up
## move the camera away from the bus as speed increases for a sense of velocity.
func _follow_transform(delta: float, mount: Node3D, look_height: float, look_ahead: float, pull_back: float, pull_up: float) -> Transform3D:
	var bus_xf := bus.global_transform
	var anchor := bus_xf.origin if mount == null else mount.global_transform.origin
	var speed_factor := clampf(bus.speed_kmh() / 60.0, 0.0, 1.0)
	var desired := anchor + bus_xf.basis.z * speed_factor * pull_back + Vector3.UP * speed_factor * pull_up
	if not _initialized:
		_follow_pos = desired
		_initialized = true
	else:
		var weight := 1.0 - exp(-delta * FOLLOW_SMOOTHING)
		_follow_pos = _follow_pos.lerp(desired, weight)
	var look_target := bus_xf.origin + Vector3(0, look_height, 0) - bus_xf.basis.z * look_ahead
	var pos := _avoid_obstacles(bus_xf.origin + Vector3(0, 2.5, 0), _follow_pos)
	var xf := Transform3D(Basis.IDENTITY, pos)
	if pos.distance_squared_to(look_target) > 0.01:
		xf = xf.looking_at(look_target, Vector3.UP)
	return xf


## Keeps the follow camera out of buildings and walls: if something on the World layer
## blocks the line from the bus to the camera, the camera moves in front of it.
func _avoid_obstacles(from: Vector3, to: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	if space == null:
		return to
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return to
	var hit_pos: Vector3 = hit.position
	var back := (from - hit_pos).normalized()
	var pos := hit_pos + back * OBSTACLE_MARGIN
	if pos.distance_to(from) < 1.5:
		pos = from + back * 1.5
	return pos


func _apply_camera_effects(delta: float) -> void:
	var speed_factor := clampf(bus.speed_kmh() / 80.0, 0.0, 1.0)
	var fov_target := _base_fov() + speed_factor * (6.0 if is_driver_view() else 4.0)
	camera.fov = lerpf(camera.fov, fov_target, clampf(delta * 3.0, 0.0, 1.0))
	_shake = move_toward(_shake, 0.0, delta * 2.5)
	# Gentle cabin vibration in the driver seat that grows with speed (a few pixels at most).
	var vibration := 0.0
	if is_driver_view() and bus.engine_on:
		vibration = 0.0006 + speed_factor * speed_factor * 0.0035
	var amplitude := _shake * 0.35 + vibration
	if amplitude > 0.0004:
		camera.h_offset = randf_range(-1.0, 1.0) * amplitude
		camera.v_offset = randf_range(-1.0, 1.0) * amplitude
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
