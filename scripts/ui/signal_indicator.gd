class_name SignalIndicator
extends Control
## Small vector-drawn traffic-light icon for the HUD guidance row. Shows the colour of the
## signal the bus is heading towards (see TrafficSignals.next_signal_ahead), so the state is
## readable in every camera view - including the high view, where the 3D lamps face away
## from the camera, and from the stop line, where the mast-arm head is above the windshield.
## Driven by Hud.set_signal(); hidden when no signal is near.

var light: int = TrafficSignals.Light.RED:
	set(value):
		if light != value:
			light = value
			queue_redraw()

const HOUSING := Color(0.1, 0.1, 0.12, 0.95)
const RIM := Color(1, 1, 1, 0.25)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(24, 36)


func _draw() -> void:
	var w := size.x
	var h := size.y
	var housing := StyleBoxFlat.new()
	housing.bg_color = HOUSING
	housing.set_corner_radius_all(int(w * 0.25))
	housing.border_width_left = 1
	housing.border_width_right = 1
	housing.border_width_top = 1
	housing.border_width_bottom = 1
	housing.border_color = RIM
	draw_style_box(housing, Rect2(Vector2.ZERO, size))
	var r := minf(w * 0.32, h * 0.13)
	var cx := w * 0.5
	for k in 3:
		var colour: Color = TrafficSignals.LAMP_COLORS[k]
		var c := Vector2(cx, h * (0.2 + 0.3 * k))
		if k == light:
			draw_circle(c, r * 1.6, Color(colour, 0.28))   # glow
			draw_circle(c, r, colour)
		else:
			draw_circle(c, r, colour.darkened(0.7))
