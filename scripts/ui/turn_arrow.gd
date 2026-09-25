class_name TurnArrow
extends Control
## Small vector-drawn turn-by-turn icon for the HUD: straight / left / right / bus stop /
## terminal flag / U-turn (off route). Driven by Hud.set_guidance().

var turn: int = RouteGuide.Turn.STRAIGHT:
	set(value):
		if turn != value:
			turn = value
			queue_redraw()

const GREEN := Color(0.45, 0.95, 0.55)
const YELLOW := Color(1.0, 0.85, 0.25)
const ORANGE := Color(1.0, 0.55, 0.3)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(44, 40)


func _draw() -> void:
	var w := size.x
	var h := size.y
	var c := Vector2(w * 0.5, h * 0.5)
	var lw := maxf(4.0, h * 0.13)
	match turn:
		RouteGuide.Turn.LEFT, RouteGuide.Turn.RIGHT:
			var dir := -1.0 if turn == RouteGuide.Turn.LEFT else 1.0
			var x0 := c.x - dir * w * 0.12
			var top := h * 0.32
			# Shaft up, then a bend towards the turn side ending in an arrow head.
			draw_polyline(PackedVector2Array([Vector2(x0, h * 0.92), Vector2(x0, top), Vector2(x0 + dir * w * 0.3, top)]), GREEN, lw, true)
			var tip := Vector2(x0 + dir * w * 0.44, top)
			draw_colored_polygon(PackedVector2Array([tip, Vector2(tip.x - dir * h * 0.24, top - h * 0.2), Vector2(tip.x - dir * h * 0.24, top + h * 0.2)]), GREEN)
		RouteGuide.Turn.STOP:
			# Bus stop sign: yellow disc with a little dark bus.
			draw_circle(c, h * 0.46, YELLOW)
			var bus := Rect2(c + Vector2(-w * 0.22, -h * 0.16), Vector2(w * 0.44, h * 0.26))
			draw_rect(bus, Color(0.1, 0.1, 0.12))
			draw_rect(Rect2(bus.position + Vector2(w * 0.04, h * 0.04), Vector2(w * 0.36, h * 0.09)), Color(0.75, 0.9, 1.0))
			for x in [-0.12, 0.12]:
				draw_circle(c + Vector2(w * x, h * 0.14), h * 0.06, Color(0.1, 0.1, 0.12))
		RouteGuide.Turn.TERMINAL:
			# Chequered finish flag.
			var cell := h * 0.16
			var origin := c - Vector2(cell * 1.5, cell * 1.5)
			for j in 3:
				for i in 3:
					var col := Color.WHITE if (i + j) % 2 == 0 else Color(0.1, 0.1, 0.12)
					draw_rect(Rect2(origin + Vector2(i * cell, j * cell), Vector2(cell, cell)), col)
			draw_rect(Rect2(origin - Vector2(3.0, 0.0), Vector2(3.0, cell * 3.6)), Color(0.85, 0.85, 0.88))
		RouteGuide.Turn.OFF_ROUTE:
			# U-turn arrow.
			var r := h * 0.22
			var centre := Vector2(c.x, h * 0.4)
			draw_arc(centre, r, PI, TAU, 16, ORANGE, lw, true)
			draw_line(Vector2(centre.x + r, centre.y), Vector2(centre.x + r, h * 0.92), ORANGE, lw, true)
			var tip := Vector2(centre.x - r, h * 0.72)
			draw_colored_polygon(PackedVector2Array([tip, Vector2(tip.x - h * 0.2, tip.y - h * 0.24), Vector2(tip.x + h * 0.2, tip.y - h * 0.24)]), ORANGE)
			draw_line(Vector2(centre.x - r, centre.y), Vector2(centre.x - r, tip.y - h * 0.2), ORANGE, lw, true)
		_:
			# Straight ahead.
			draw_line(Vector2(c.x, h * 0.92), Vector2(c.x, h * 0.32), GREEN, lw, true)
			draw_colored_polygon(PackedVector2Array([Vector2(c.x, h * 0.06), Vector2(c.x - h * 0.24, h * 0.42), Vector2(c.x + h * 0.24, h * 0.42)]), GREEN)
