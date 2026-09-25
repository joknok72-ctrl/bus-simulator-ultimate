class_name Minimap
extends Control
## North-up minimap of the city: road grid, route line, stops, traffic and the bus.

var route_points: PackedVector3Array = PackedVector3Array()
var stops: Array = []          # Array[BusStop]
var terminal: BusStop = null
var current_stop_index := 0
var progress_seg := -1        # route segment the bus is on (RouteGuide); earlier segments are drawn dimmed
var bus: Node3D = null
var cars: Array = []
var _pulse := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_pulse += delta * 4.0
	queue_redraw()


func _map(world: Vector3) -> Vector2:
	var uv := CityLayout.to_map_uv(world)
	return Vector2(uv.x * size.x, uv.y * size.y)


func _draw() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.08, 0.06, 0.85)
	bg.set_corner_radius_all(14)
	bg.border_width_left = 2
	bg.border_width_right = 2
	bg.border_width_top = 2
	bg.border_width_bottom = 2
	bg.border_color = Color(1, 1, 1, 0.25)
	draw_style_box(bg, Rect2(Vector2.ZERO, size))
	# Road grid
	var n := CityLayout.GRID_N
	var road_col := Color(0.45, 0.47, 0.5, 0.9)
	var road_w := maxf(3.0, size.x * 0.035)
	for i in n:
		var a := _map(CityLayout.node_pos(Vector2i(i, 0)))
		var b := _map(CityLayout.node_pos(Vector2i(i, n - 1)))
		draw_line(a, b, road_col, road_w)
		var c := _map(CityLayout.node_pos(Vector2i(0, i)))
		var d := _map(CityLayout.node_pos(Vector2i(n - 1, i)))
		draw_line(c, d, road_col, road_w)
	# Route: the part already driven is dimmed, the rest stays bright yellow.
	if route_points.size() >= 2:
		var pts := PackedVector2Array()
		for p in route_points:
			pts.append(_map(p))
		var split := clampi(progress_seg, 0, pts.size() - 1)
		var line_w := maxf(2.0, road_w * 0.5)
		if split >= 1:
			draw_polyline(pts.slice(0, split + 1), Color(0.75, 0.7, 0.55, 0.55), line_w, true)
		if split <= pts.size() - 2:
			draw_polyline(pts.slice(split), Color(1.0, 0.85, 0.2, 0.95), line_w, true)
	# Stops
	for i in stops.size():
		var stop: BusStop = stops[i]
		if stop == null or not is_instance_valid(stop):
			continue
		var p := _map(stop.global_position)
		if stop.served:
			draw_circle(p, 4.0, Color(0.6, 0.6, 0.6, 0.8))
		elif i == current_stop_index:
			draw_circle(p, 6.0 + sin(_pulse) * 1.5, Color(1.0, 0.85, 0.2))
			draw_arc(p, 9.0 + sin(_pulse) * 2.0, 0.0, TAU, 20, Color(1.0, 0.85, 0.2, 0.6), 2.0, true)
		else:
			draw_circle(p, 4.5, Color(1, 1, 1, 0.9))
	if terminal != null and is_instance_valid(terminal):
		var tp := _map(terminal.global_position)
		draw_rect(Rect2(tp - Vector2(5, 5), Vector2(10, 10)), Color(0.3, 0.9, 0.5))
	# Traffic
	for car in cars:
		if car != null and is_instance_valid(car):
			draw_circle(_map(car.global_position), 2.5, Color(0.95, 0.4, 0.3, 0.9))
	# Bus
	if bus != null and is_instance_valid(bus):
		var bp := _map(bus.global_position)
		var fwd3 := -bus.global_transform.basis.z
		var fwd := Vector2(fwd3.x, fwd3.z).normalized()
		var side := Vector2(-fwd.y, fwd.x)
		var tri := PackedVector2Array([bp + fwd * 9.0, bp - fwd * 6.0 + side * 6.0, bp - fwd * 6.0 - side * 6.0])
		draw_colored_polygon(tri, Color(0.3, 0.8, 1.0))
		draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color(1, 1, 1, 0.9), 1.5, true)
