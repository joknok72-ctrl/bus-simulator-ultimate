class_name CameraRig
extends Node3D
## Smooth follow camera with three views: chase, driver seat and high view.

@export var bus_path: NodePath
@onready var camera: Camera3D = $Camera3D

var bus: Bus
var mode: int = GameState.CameraMode.CHASE
var _shake := 0.0
var _initialized := false


func _ready() -> void:
	if bus_path != NodePath(""):
		bus = get_node_or_null(bus_path) as Bus
	mode = int(GameState.settings.camera)
	camera.current = true
	camera.fov = 68.0
	camera.near = 0.2
	camera.far = 600.0


func set_bus(target: Bus) -> void:
	bus = target
	_initialized = false


func cycle_mode() -> void:
	mode = (mode + 1) % 3
	GameState.set_setting("camera", mode)
	_initialized = false


func add_shake(amount: float) -> void:
	_shake = minf(_shake + amount, 1.0)


func _physics_process(delta: float) -> void:
	if bus == null or not is_instance_valid(bus):
		return
	var mount: Node3D = bus.chase_mount
	if mode == GameState.CameraMode.DRIVER:
		mount = bus.driver_mount
	elif mode == GameState.CameraMode.TOP:
		mount = bus.top_mount
	if mount == null:
		return
	var target_xf := mount.global_transform
	var look_target := bus.global_position + Vector3(0, 2.2, 0) - bus.global_transform.basis.z * 6.0
	if mode == GameState.CameraMode.DRIVER:
		# Rigidly attached to the cabin; look straight ahead.
		global_position = target_xf.origin
		var ahead := bus.global_position + Vector3(0, 2.5, 0) - bus.global_transform.basis.z * 40.0
		look_at(ahead, Vector3.UP)
	else:
		if not _initialized:
			global_position = target_xf.origin
			_initialized = true
		else:
			var speed_factor := clampf(bus.speed_kmh() / 60.0, 0.0, 1.0)
			# Pull the camera back a little at speed for a sense of velocity.
			var desired := target_xf.origin + bus.global_transform.basis.z * speed_factor * 2.5 + Vector3(0, speed_factor * 0.8, 0)
			var weight := 1.0 - exp(-delta * 6.0)
			global_position = global_position.lerp(desired, weight)
		look_at(look_target, Vector3.UP)
	if _shake > 0.001:
		_shake = move_toward(_shake, 0.0, delta * 2.5)
		camera.h_offset = randf_range(-1.0, 1.0) * _shake * 0.35
		camera.v_offset = randf_range(-1.0, 1.0) * _shake * 0.35
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
