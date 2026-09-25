class_name RouteGuide
extends RefCounted
## Turn-by-turn guidance along the route polyline (the right-hand lane, with a corner
## point at every intersection, see CityLayout.route_polyline).
##
## The old guide arrow pointed straight at the next stop "as the crow flies", which around
## a corner meant pointing through a building. This class projects the bus onto the route,
## finds the next corner before the target stop and tells the HUD which way to turn, how far
## the turn is, and whether the bus has left the route.

enum Turn { STRAIGHT, LEFT, RIGHT, STOP, TERMINAL, OFF_ROUTE }

const OFF_ROUTE_ENTER := 22.0   # lateral distance (m) from the lane line that counts as leaving the route
const OFF_ROUTE_LEAVE := 13.0   # ... and the distance at which the bus is back on it (hysteresis)
const MIN_TURN_LOOKAHEAD := 2.0

var points: PackedVector3Array = PackedVector3Array()
var off_route := false

var _cumulative: PackedFloat32Array = PackedFloat32Array()   # distance along the route at every vertex


func setup(polyline: PackedVector3Array) -> void:
	points = polyline
	off_route = false
	_cumulative.clear()
	var total := 0.0
	for i in points.size():
		if i > 0:
			total += points[i].distance_to(points[i - 1])
		_cumulative.append(total)


func total_length() -> float:
	return _cumulative[_cumulative.size() - 1] if _cumulative.size() > 0 else 0.0


## Closest point of the route to `pos` (in the XZ plane).
## Returns {seg, t, point, lateral, along}.
func project(pos: Vector3) -> Dictionary:
	var best := {"seg": 0, "t": 0.0, "point": Vector3.ZERO, "lateral": INF, "along": 0.0}
	if points.size() < 2:
		return best
	var flat := Vector3(pos.x, 0.0, pos.z)
	for i in range(points.size() - 1):
		var a := Vector3(points[i].x, 0.0, points[i].z)
		var b := Vector3(points[i + 1].x, 0.0, points[i + 1].z)
		var ab := b - a
		var len_sq := ab.length_squared()
		var t := 0.0
		if len_sq > 0.0001:
			t = clampf((flat - a).dot(ab) / len_sq, 0.0, 1.0)
		var p := a + ab * t
		var d := p.distance_to(flat)
		# Prefer the later segment when the bus is exactly at a corner (equal distances).
		if d <= best.lateral:
			best = {"seg": i, "t": t, "point": p, "lateral": d, "along": _cumulative[i] + ab.length() * t}
	return best


## Guidance towards `target` (the next stop or the terminal).
## Returns {turn: Turn, guide_point: Vector3, distance: float, seg: int, lateral: float}
##  * guide_point - where the 3D arrow should point: the next corner, or the target itself
##  * distance    - metres along the route to that corner / target
func guidance(bus_pos: Vector3, target: Vector3, is_terminal: bool) -> Dictionary:
	var here := project(bus_pos)
	var there := project(target)
	var lateral: float = here.lateral
	if off_route:
		off_route = lateral > OFF_ROUTE_LEAVE
	else:
		off_route = lateral > OFF_ROUTE_ENTER
	var result := {"turn": Turn.STRAIGHT, "guide_point": target, "distance": 0.0, "seg": int(here.seg), "lateral": lateral}
	if off_route:
		# Back to the nearest point of the route.
		result.turn = Turn.OFF_ROUTE
		result.guide_point = Vector3(here.point.x, target.y, here.point.z)
		result.distance = lateral
		return result
	var remaining: float = float(there.along) - float(here.along)
	if remaining <= MIN_TURN_LOOKAHEAD or int(here.seg) >= int(there.seg):
		# Target is on the current segment (or behind us): head straight for it.
		result.turn = Turn.TERMINAL if is_terminal else Turn.STOP
		result.guide_point = target
		result.distance = maxf(remaining, Vector2(target.x - bus_pos.x, target.z - bus_pos.z).length())
		return result
	# Next corner between the bus and the target.
	var corner_index: int = int(here.seg) + 1
	var corner := points[corner_index]
	var d_in := (points[corner_index] - points[corner_index - 1]).normalized()
	var d_out := (points[corner_index + 1] - points[corner_index]).normalized()
	var cross_y := d_in.cross(d_out).y
	if cross_y > 0.3:
		result.turn = Turn.LEFT
	elif cross_y < -0.3:
		result.turn = Turn.RIGHT
	else:
		result.turn = Turn.STRAIGHT
	result.guide_point = Vector3(corner.x, target.y, corner.z)
	result.distance = float(_cumulative[corner_index]) - float(here.along)
	return result
