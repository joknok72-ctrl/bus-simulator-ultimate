class_name Speedometer
extends Control
## Analogue speed gauge drawn with primitives. Shows speed, gear and speed limit.

var speed_kmh := 0.0
var speed_limit := 50
var reversing := false
var doors_open := false
var _display_speed := 0.0
const MAX_KMH := 100.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_display_speed = lerpf(_display_speed, speed_kmh, clampf(delta * 8.0, 0.0, 1.0))
	queue_redraw()


func _draw() -> void:
	var c := Vector2(size.x * 0.5, size.y * 0.62)
	var r := minf(size.x * 0.5, size.y * 0.62) - 8.0
	var start := deg_to_rad(150.0)
	var end := deg_to_rad(390.0)
	var over_limit := _display_speed > speed_limit + 3.0
	# Background
	draw_circle(c, r + 6.0, Color(0, 0, 0, 0.35))
	draw_arc(c, r, start, end, 48, Color(0.1, 0.11, 0.14, 0.95), 18.0, true)
	# Speed limit zone (red)
	var limit_angle := remap(clampf(speed_limit, 0.0, MAX_KMH), 0.0, MAX_KMH, start, end)
	draw_arc(c, r, limit_angle, end, 24, Color(0.75, 0.15, 0.12, 0.8), 18.0, true)
	# Progress arc
	var speed_angle := remap(clampf(_display_speed, 0.0, MAX_KMH), 0.0, MAX_KMH, start, end)
	if _display_speed > 0.5:
		var col := Color(0.95, 0.35, 0.25) if over_limit else Color(0.3, 0.85, 0.95)
		draw_arc(c, r, start, speed_angle, 40, col, 12.0, true)
	# Ticks
	var font := get_theme_default_font()
	for i in 11:
		var a := remap(float(i), 0.0, 10.0, start, end)
		var dir := Vector2(cos(a), sin(a))
		draw_line(c + dir * (r - 14.0), c + dir * (r - 24.0), Color(1, 1, 1, 0.7), 2.0, true)
		if i % 2 == 0:
			var label_pos := c + dir * (r - 40.0) - Vector2(12, -6)
			draw_string(font, label_pos, str(i * 10), HORIZONTAL_ALIGNMENT_CENTER, 24, 12, Color(1, 1, 1, 0.75))
	# Needle
	var nd := Vector2(cos(speed_angle), sin(speed_angle))
	draw_line(c, c + nd * (r - 22.0), Color(1.0, 0.3, 0.25) if over_limit else Color(1.0, 0.8, 0.2), 4.0, true)
	draw_circle(c, 7.0, Color(0.9, 0.9, 0.9))
	# Speed value
	var bold := get_theme_font("font", "HudValue")
	draw_string(bold, Vector2(0, c.y + 4.0), str(int(round(_display_speed))), HORIZONTAL_ALIGNMENT_CENTER, size.x, 34, Color(1, 1, 1))
	draw_string(font, Vector2(0, c.y + 24.0), tr("HUD_KMH"), HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, Color(1, 1, 1, 0.75))
	# Gear indicator
	var gear := "R" if reversing else ("N" if doors_open else "D")
	var gear_col := Color(1.0, 0.6, 0.2) if reversing else (Color(0.9, 0.9, 0.9) if doors_open else Color(0.4, 0.9, 0.5))
	draw_circle(Vector2(c.x, c.y + r * 0.62), 16.0, Color(0, 0, 0, 0.5))
	draw_string(bold, Vector2(0, c.y + r * 0.62 + 8.0), gear, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, gear_col)
	if over_limit:
		draw_arc(c, r + 4.0, 0.0, TAU, 48, Color(1.0, 0.3, 0.25, 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.01)), 3.0, true)
