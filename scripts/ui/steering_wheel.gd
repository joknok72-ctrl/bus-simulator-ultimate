class_name SteeringWheel
extends Control
## Touch steering wheel drawn with vector primitives. Drag anywhere on the wheel to
## rotate it; it springs back to centre when released. "value" is -1..1.

## Wheel rotation for full lock per steering sensitivity setting (low / normal / high).
const LOCK_ANGLES: Array[float] = [deg_to_rad(190.0), deg_to_rad(150.0), deg_to_rad(110.0)]
const MAX_ANGLE := deg_to_rad(150.0)
const RETURN_SPEED := deg_to_rad(260.0)

var value := 0.0
var angle := 0.0
var held := false
var max_angle := MAX_ANGLE
var _last_touch_angle := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(240, 240)
	_apply_sensitivity()
	GameState.settings_changed.connect(_apply_sensitivity)


func _apply_sensitivity() -> void:
	max_angle = LOCK_ANGLES[GameState.steer_sensitivity()]


func _process(delta: float) -> void:
	if not held:
		angle = move_toward(angle, 0.0, RETURN_SPEED * delta)
	value = clampf(angle / max_angle, -1.0, 1.0)
	queue_redraw()


func contains_point(global_point: Vector2) -> bool:
	var rect := get_global_rect()
	var center := rect.get_center()
	var radius := minf(rect.size.x, rect.size.y) * 0.5 + 24.0
	return center.distance_to(global_point) <= radius


func begin_touch(global_point: Vector2) -> void:
	held = true
	_last_touch_angle = _touch_angle(global_point)


func update_touch(global_point: Vector2) -> void:
	if not held:
		return
	var a := _touch_angle(global_point)
	var diff := wrapf(a - _last_touch_angle, -PI, PI)
	_last_touch_angle = a
	angle = clampf(angle + diff, -max_angle, max_angle)


func end_touch() -> void:
	held = false


func _touch_angle(global_point: Vector2) -> float:
	var center := get_global_rect().get_center()
	return (global_point - center).angle()


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 6.0
	var ring_w := radius * 0.2
	draw_set_transform(center, angle, Vector2.ONE)
	# Tyre
	draw_arc(Vector2.ZERO, radius - ring_w * 0.5, 0.0, TAU, 64, Color(0.12, 0.12, 0.14, 0.92), ring_w, true)
	draw_arc(Vector2.ZERO, radius - ring_w * 0.5, 0.0, TAU, 64, Color(1, 1, 1, 0.18), 2.0, true)
	# Grips
	for a in [PI * 0.25, PI * 0.75]:
		draw_arc(Vector2.ZERO, radius - ring_w * 0.5, a - 0.3, a + 0.3, 12, Color(0.3, 0.3, 0.34, 0.95), ring_w * 0.7, true)
	# Spokes
	var spoke_color := Color(0.22, 0.23, 0.26, 0.95)
	for a in [PI * 0.5, PI + PI * 0.18, -PI * 0.18]:
		var dir := Vector2(cos(a), sin(a))
		draw_line(dir * radius * 0.2, dir * (radius - ring_w), spoke_color, ring_w * 0.55, true)
	# Hub
	draw_circle(Vector2.ZERO, radius * 0.26, Color(0.2, 0.21, 0.24, 0.98))
	draw_circle(Vector2.ZERO, radius * 0.16, Color(0.85, 0.2, 0.18, 1.0))
	# Top marker
	draw_circle(Vector2(0, -(radius - ring_w * 0.5)), ring_w * 0.28, Color(0.95, 0.35, 0.3, 1.0))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if held:
		draw_arc(center, radius + 4.0, 0.0, TAU, 64, Color(1, 1, 1, 0.25), 3.0, true)
