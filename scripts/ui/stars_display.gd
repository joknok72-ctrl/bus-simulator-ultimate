class_name StarsDisplay
extends Control
## Draws 1-3 stars (filled/empty) with vector primitives, optionally animated.

@export var count: int = 0
@export var max_stars: int = 3
@export var star_size: float = 28.0
var _reveal := 3.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(star_size * 2.3 * max_stars, star_size * 2.2)


func set_stars(n: int, animate: bool = false) -> void:
	count = n
	if animate:
		_reveal = 0.0
		var tween := create_tween()
		tween.tween_property(self, "_reveal", float(max_stars), 0.9).set_delay(0.2)
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _star_points(center: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + i * PI / 5.0
		var radius := r if i % 2 == 0 else r * 0.45
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	return pts


func _draw() -> void:
	var spacing := star_size * 2.3
	var start_x := (size.x - spacing * max_stars) * 0.5 + spacing * 0.5
	for i in max_stars:
		var c := Vector2(start_x + i * spacing, size.y * 0.5)
		var filled := i < count and float(i) < _reveal
		var scale := 1.0
		if filled:
			scale = clampf((_reveal - i) * 1.5, 0.0, 1.0)
			scale = 1.0 + (1.0 - scale) * 0.6
		var pts := _star_points(c, star_size * scale)
		draw_colored_polygon(pts, Color(1.0, 0.82, 0.2) if filled else Color(1, 1, 1, 0.15))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1.0, 0.9, 0.5) if filled else Color(1, 1, 1, 0.3), 2.0, true)
