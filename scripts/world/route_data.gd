class_name RouteData
extends RefCounted
## Static definitions of the playable bus routes.
## "path" lists intersection grid coordinates; consecutive nodes must share a row
## or a column (straight road segments). "stops" are [segment_index, fraction]
## pairs placed in the right-hand lane of that segment. Every stop must lie mid-block:
## at least MIN_STOP_CLEARANCE metres from any intersection centre along the segment, so
## the painted stop zone (+-8 m) and a correctly parked bus stay out of the signalised
## crossing (checked by tests/smoke_test.gd). Time limits include a margin for waiting at
## red lights (roughly one stop per two blocks of straight road).

## Minimum distance (m) between a stop marker and an intersection centre: half the road
## width (7) plus the half-length of the stop zone (8) plus a metre of margin.
const MIN_STOP_CLEARANCE := 16.0

static func all() -> Array[Dictionary]:
	return [
		{
			"id": "route_1",
			"name": "ROUTE_1_NAME",
			"time_of_day": "day",
			"time_limit": 180,
			"speed_limit": 50,
			"path": [Vector2i(0, 4), Vector2i(0, 2), Vector2i(2, 2), Vector2i(2, 0), Vector2i(4, 0)],
			"stops": [[0, 0.34], [1, 0.28], [2, 0.28], [3, 0.34]],
			"passengers": [4, 3, 5, 4],
			"traffic": 6,
			"stars_required": 0,
		},
		{
			"id": "route_2",
			"name": "ROUTE_2_NAME",
			"time_of_day": "sunset",
			"time_limit": 200,
			"speed_limit": 50,
			"path": [Vector2i(4, 4), Vector2i(4, 1), Vector2i(1, 1), Vector2i(1, 3), Vector2i(3, 3)],
			"stops": [[0, 0.22], [0, 0.78], [1, 0.5], [2, 0.27], [3, 0.3]],
			"passengers": [3, 4, 5, 4, 3],
			"traffic": 8,
			"stars_required": 2,
		},
		{
			"id": "route_3",
			"name": "ROUTE_3_NAME",
			"time_of_day": "night",
			"time_limit": 240,
			"speed_limit": 40,
			"path": [Vector2i(0, 0), Vector2i(3, 0), Vector2i(3, 4), Vector2i(0, 4), Vector2i(0, 1)],
			"stops": [[0, 0.45], [0, 0.8], [1, 0.35], [1, 0.64], [2, 0.5], [3, 0.5]],
			"passengers": [3, 4, 4, 5, 3, 4],
			"traffic": 9,
			"stars_required": 5,
		},
		{
			"id": "route_4",
			"name": "ROUTE_4_NAME",
			"time_of_day": "day",
			"time_limit": 250,
			"speed_limit": 50,
			"path": [Vector2i(2, 4), Vector2i(2, 3), Vector2i(4, 3), Vector2i(4, 0), Vector2i(1, 0), Vector2i(1, 2), Vector2i(3, 2)],
			"stops": [[1, 0.27], [2, 0.22], [2, 0.78], [3, 0.45], [3, 0.78], [4, 0.27], [5, 0.3]],
			"passengers": [4, 5, 4, 6, 4, 5, 4],
			"traffic": 12,
			"stars_required": 8,
		},
	]


static func get_route(route_id: String) -> Dictionary:
	for route in all():
		if route.id == route_id:
			return route
	return all()[0]


static func next_route_id(route_id: String) -> String:
	var routes := all()
	for i in routes.size():
		if routes[i].id == route_id and i + 1 < routes.size():
			return routes[i + 1].id
	return ""


static func total_passengers(route: Dictionary) -> int:
	var total := 0
	for n in route.passengers:
		total += int(n)
	return total


## Approximate route length in metres (used on the route cards).
static func route_length(route: Dictionary) -> float:
	return CityLayout.polyline_length(CityLayout.route_polyline(route.path))


## Distance (m) along its road segment from a stop marker to the nearest intersection centre.
## Must be at least MIN_STOP_CLEARANCE for every stop (see the class comment).
static func stop_clearance(route: Dictionary, stop_index: int) -> float:
	var def: Array = route.stops[stop_index]
	var a: Vector2i = route.path[int(def[0])]
	var b: Vector2i = route.path[int(def[0]) + 1]
	var along := CityLayout.node_pos(a).distance_to(CityLayout.node_pos(b)) * float(def[1])
	var to_prev := fposmod(along, CityLayout.BLOCK)
	return minf(to_prev, CityLayout.BLOCK - to_prev)
