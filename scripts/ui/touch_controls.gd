class_name TouchControls
extends Control
## Central multi-touch input layer for driving. Tracks every finger separately so
## the player can steer, accelerate and brake at the same time. Also merges keyboard
## input (for desktop testing) and accelerometer steering (tilt mode).

signal horn_pressed()
signal doors_pressed()
signal camera_pressed()
signal pause_pressed()

@onready var wheel: SteeringWheel = $Wheel
@onready var left_button: TouchButton = $LeftButton
@onready var right_button: TouchButton = $RightButton
@onready var gas: TouchButton = $Gas
@onready var brake_pedal: TouchButton = $Brake
@onready var horn_button: TouchButton = $HornButton
@onready var doors_button: TouchButton = $DoorsButton
@onready var camera_button: TouchButton = $CameraButton
@onready var pause_button: TouchButton = $PauseButton
@onready var tilt_hint: Label = $TiltHint

var steer := 0.0
var throttle := 0.0
var brake := 0.0
var control_mode: int = GameState.ControlMode.WHEEL

## Button steering rate (per second) and tilt divisor (g) per sensitivity setting.
const BUTTON_RATES: Array[float] = [2.2, 3.0, 4.2]
const TILT_DIVISORS: Array[float] = [6.0, 4.5, 3.3]

var _touches: Dictionary = {}     # touch index -> Control
var _tilt_steer := 0.0
var _button_steer := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horn_button.tapped.connect(func() -> void: horn_pressed.emit())
	doors_button.tapped.connect(func() -> void: doors_pressed.emit())
	camera_button.tapped.connect(func() -> void: camera_pressed.emit())
	pause_button.tapped.connect(func() -> void: pause_pressed.emit())
	apply_control_mode(int(GameState.settings.control_mode))
	GameState.settings_changed.connect(func() -> void: apply_control_mode(int(GameState.settings.control_mode)))


func apply_control_mode(mode: int) -> void:
	control_mode = mode
	wheel.visible = mode == GameState.ControlMode.WHEEL
	left_button.visible = mode == GameState.ControlMode.BUTTONS
	right_button.visible = mode == GameState.ControlMode.BUTTONS
	tilt_hint.visible = mode == GameState.ControlMode.TILT
	wheel.end_touch()
	left_button.release()
	right_button.release()


func _zones() -> Array:
	var zones: Array = [gas, brake_pedal, horn_button, doors_button, camera_button, pause_button]
	if wheel.visible:
		zones.append(wheel)
	if left_button.visible:
		zones.append(left_button)
		zones.append(right_button)
	return zones


func _input(event: InputEvent) -> void:
	if not visible or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_began(event.index, event.position)
		else:
			_touch_ended(event.index)
	elif event is InputEventScreenDrag:
		_touch_moved(event.index, event.position)


func _touch_began(index: int, pos: Vector2) -> void:
	for zone in _zones():
		if zone.contains_point(pos):
			_touches[index] = zone
			if zone is SteeringWheel:
				zone.begin_touch(pos)
			else:
				zone.press()
			return


func _touch_moved(index: int, pos: Vector2) -> void:
	if not _touches.has(index):
		# A finger that started outside any control may slide onto the wheel or a button.
		_touch_began(index, pos)
		return
	var zone: Control = _touches[index]
	if zone is SteeringWheel:
		zone.update_touch(pos)
	elif zone == left_button or zone == right_button:
		# Allow sliding between the two steering buttons.
		if zone == left_button and right_button.contains_point(pos):
			left_button.release()
			right_button.press()
			_touches[index] = right_button
		elif zone == right_button and left_button.contains_point(pos):
			right_button.release()
			left_button.press()
			_touches[index] = left_button


func _touch_ended(index: int) -> void:
	if not _touches.has(index):
		return
	var zone: Control = _touches[index]
	_touches.erase(index)
	if zone is SteeringWheel:
		zone.end_touch()
	else:
		zone.release()


func release_all() -> void:
	for index in _touches.keys():
		_touch_ended(index)
	_touches.clear()


func _process(delta: float) -> void:
	# --- steering
	var touch_steer := 0.0
	if control_mode == GameState.ControlMode.WHEEL:
		touch_steer = wheel.value
	elif control_mode == GameState.ControlMode.BUTTONS:
		var target := 0.0
		if left_button.pressed:
			target -= 1.0
		if right_button.pressed:
			target += 1.0
		var rate: float = BUTTON_RATES[GameState.steer_sensitivity()]
		_button_steer = move_toward(_button_steer, target, delta * (rate if target != 0.0 else 5.0))
		touch_steer = _button_steer
	else:
		var acc := Input.get_accelerometer()
		var raw := clampf(-acc.x / TILT_DIVISORS[GameState.steer_sensitivity()], -1.0, 1.0)
		if GameState.settings.invert_tilt:
			raw = -raw
		if absf(raw) < 0.06:
			raw = 0.0
		_tilt_steer = lerpf(_tilt_steer, raw, clampf(delta * 10.0, 0.0, 1.0))
		touch_steer = _tilt_steer
	var key_steer := Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	steer = touch_steer if absf(touch_steer) > 0.001 else key_steer
	# --- pedals
	var key_gas := Input.get_action_strength("accelerate")
	var key_brake := Input.get_action_strength("brake")
	throttle = maxf(gas.value, key_gas)
	brake = maxf(brake_pedal.value, key_brake)


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("horn"):
		horn_pressed.emit()
	elif event.is_action_pressed("toggle_doors"):
		doors_pressed.emit()
	elif event.is_action_pressed("toggle_camera"):
		camera_pressed.emit()
	elif event.is_action_pressed("pause"):
		pause_pressed.emit()
