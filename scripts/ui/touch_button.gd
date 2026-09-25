class_name TouchButton
extends Control
## Vector-drawn touch button used by the in-game controls (pedals and round action
## buttons). Touch handling is done centrally by TouchControls so several buttons can
## be held at the same time with multi-touch.

signal tapped()

enum Shape { ROUND, PEDAL }
enum Icon { NONE, HORN, DOORS, CAMERA, LEFT, RIGHT, PAUSE, GAS, BRAKE }

@export var shape: Shape = Shape.ROUND
@export var icon: Icon = Icon.NONE
@export var label_key: String = ""
@export var base_color: Color = Color(0.15, 0.17, 0.22, 0.85)
@export var accent_color: Color = Color(1, 1, 1, 0.9)
@export var analog_ramp: float = 0.0   # seconds to reach full value while held (0 = instant)

var pressed := false
var value := 0.0
var _flash := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if pressed:
		value = 1.0 if analog_ramp <= 0.0 else move_toward(value, 1.0, delta / analog_ramp)
	else:
		value = 0.0 if analog_ramp <= 0.0 else move_toward(value, 0.0, delta / (analog_ramp * 0.5))
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 4.0, 0.0)
	queue_redraw()


func contains_point(global_point: Vector2) -> bool:
	var rect := get_global_rect().grow(10.0)
	if shape == Shape.ROUND:
		var r := minf(rect.size.x, rect.size.y) * 0.5
		return rect.get_center().distance_to(global_point) <= r
	return rect.has_point(global_point)


func press() -> void:
	if not pressed:
		pressed = true
		_flash = 1.0
		tapped.emit()


func release() -> void:
	pressed = false


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var col := base_color
	if pressed:
		col = col.lightened(0.25)
	var font := get_theme_default_font()
	if shape == Shape.ROUND:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, Color(0, 0, 0, 0.25))
		draw_circle(c, r - 3.0, col)
		draw_arc(c, r - 3.0, 0.0, TAU, 48, Color(1, 1, 1, 0.35 + _flash * 0.4), 2.5, true)
		_draw_icon(c, r * 0.5)
	else:
		var style := StyleBoxFlat.new()
		style.bg_color = col
		style.set_corner_radius_all(int(minf(size.x, size.y) * 0.22))
		style.border_width_bottom = 6
		style.border_color = Color(0, 0, 0, 0.35)
		draw_style_box(style, rect)
		var inner := StyleBoxFlat.new()
		inner.bg_color = Color(1, 1, 1, 0.06 + value * 0.12)
		inner.set_corner_radius_all(int(minf(size.x, size.y) * 0.2))
		draw_style_box(inner, rect.grow(-8.0))
		# Pedal grip lines
		for i in 5:
			var y := rect.size.y * (0.25 + i * 0.1)
			draw_line(Vector2(rect.size.x * 0.28, y), Vector2(rect.size.x * 0.72, y), Color(1, 1, 1, 0.22), 3.0, true)
		_draw_icon(Vector2(size.x * 0.5, size.y * 0.72), minf(size.x, size.y) * 0.3)
		if label_key != "":
			draw_string_outline(font, Vector2(0, size.y * 0.16 + 8.0), tr(label_key), HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, 4, Color(0, 0, 0, 0.45))
			draw_string(font, Vector2(0, size.y * 0.16 + 8.0), tr(label_key), HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, Color(1, 1, 1, 0.9))
	if shape == Shape.ROUND and label_key != "":
		# Dark outline keeps the caption readable over bright buildings and lit windows.
		draw_string_outline(font, Vector2(0, size.y + 22.0), tr(label_key), HORIZONTAL_ALIGNMENT_CENTER, size.x, 17, 5, Color(0, 0, 0, 0.6))
		draw_string(font, Vector2(0, size.y + 22.0), tr(label_key), HORIZONTAL_ALIGNMENT_CENTER, size.x, 17, Color(1, 1, 1, 0.95))


func _draw_icon(c: Vector2, s: float) -> void:
	var ic := accent_color
	match icon:
		Icon.HORN:
			# Trumpet body and sound waves.
			var pts := PackedVector2Array([c + Vector2(-s, -s * 0.3), c + Vector2(-s * 0.1, -s * 0.3), c + Vector2(s * 0.45, -s * 0.85), c + Vector2(s * 0.45, s * 0.85), c + Vector2(-s * 0.1, s * 0.3), c + Vector2(-s, s * 0.3)])
			draw_colored_polygon(pts, ic)
			draw_arc(c + Vector2(s * 0.5, 0), s * 0.75, -0.7, 0.7, 10, ic, 3.0, true)
			draw_arc(c + Vector2(s * 0.5, 0), s * 1.05, -0.6, 0.6, 10, ic, 3.0, true)
		Icon.DOORS:
			draw_rect(Rect2(c + Vector2(-s, -s), Vector2(s * 0.9, s * 2.0)), ic, false, 4.0)
			draw_rect(Rect2(c + Vector2(s * 0.1, -s), Vector2(s * 0.9, s * 2.0)), ic, false, 4.0)
			draw_line(c + Vector2(-s * 0.55, 0), c + Vector2(-s * 1.4, 0), ic, 4.0, true)
			draw_line(c + Vector2(s * 0.55, 0), c + Vector2(s * 1.4, 0), ic, 4.0, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 1.4, 0), c + Vector2(-s * 1.05, -s * 0.3), c + Vector2(-s * 1.05, s * 0.3)]), ic)
			draw_colored_polygon(PackedVector2Array([c + Vector2(s * 1.4, 0), c + Vector2(s * 1.05, -s * 0.3), c + Vector2(s * 1.05, s * 0.3)]), ic)
		Icon.CAMERA:
			draw_rect(Rect2(c + Vector2(-s, -s * 0.6), Vector2(s * 2.0, s * 1.3)), ic, false, 4.0)
			draw_circle(c + Vector2(0, s * 0.05), s * 0.38, ic)
			draw_rect(Rect2(c + Vector2(-s * 0.5, -s * 0.9), Vector2(s * 0.7, s * 0.3)), ic)
		Icon.LEFT:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s, 0), c + Vector2(s * 0.4, -s), c + Vector2(s * 0.4, s)]), ic)
		Icon.RIGHT:
			draw_colored_polygon(PackedVector2Array([c + Vector2(s, 0), c + Vector2(-s * 0.4, -s), c + Vector2(-s * 0.4, s)]), ic)
		Icon.PAUSE:
			draw_rect(Rect2(c + Vector2(-s * 0.8, -s), Vector2(s * 0.55, s * 2.0)), ic)
			draw_rect(Rect2(c + Vector2(s * 0.25, -s), Vector2(s * 0.55, s * 2.0)), ic)
		Icon.GAS:
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.9, s * 0.6), c + Vector2(-s * 0.9, s * 0.6)]), ic)
		Icon.BRAKE:
			draw_rect(Rect2(c + Vector2(-s * 0.8, -s * 0.8), Vector2(s * 1.6, s * 1.6)), ic)
		_:
			pass
