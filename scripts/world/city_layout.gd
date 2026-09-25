class_name CityLayout
extends RefCounted
## Shared geometry constants and helpers for the procedurally generated city grid.
## The city is a GRID_N x GRID_N grid of intersections. Roads run along X and Z.
## Traffic drives on the right-hand side.

const BLOCK := 64.0          # distance between intersection centres (m)
const ROAD_WIDTH := 14.0     # 2 lanes per direction
const LANE_WIDTH := 3.5
const SIDEWALK := 3.0
const GRID_N := 5            # intersections per side
const INNER_LANE := 1.75     # lane centre offsets from the road centre line
const OUTER_LANE := 5.25
const CURB := ROAD_WIDTH * 0.5


static func half_extent() -> float:
	return (GRID_N - 1) * BLOCK * 0.5


## World position of an intersection given its grid coordinates.
static func node_pos(g: Vector2i) -> Vector3:
	var half := half_extent()
	return Vector3(g.x * BLOCK - half, 0.0, g.y * BLOCK - half)


## Unit direction of a straight segment between two grid nodes.
static func seg_dir(a: Vector2i, b: Vector2i) -> Vector3:
	var d := node_pos(b) - node_pos(a)
	if d.length_squared() < 0.001:
		return Vector3.FORWARD
	return d.normalized()


## Right-hand vector (driver's right) for a travel direction.
static func right_of(dir: Vector3) -> Vector3:
	return dir.cross(Vector3.UP).normalized()


## Point along a route segment, offset into the right-hand lane.
static func lane_point(a: Vector2i, b: Vector2i, fraction: float, lane_offset: float = OUTER_LANE) -> Vector3:
	var pa := node_pos(a)
	var pb := node_pos(b)
	var dir := seg_dir(a, b)
	return pa.lerp(pb, fraction) + right_of(dir) * lane_offset


## Builds the polyline (in the right-hand lane) that a route follows, with lane
## corner points at every intersection, so that turns look natural on the minimap.
static func route_polyline(path: Array, lane_offset: float = OUTER_LANE) -> PackedVector3Array:
	var pts := PackedVector3Array()
	if path.size() < 2:
		return pts
	for i in path.size():
		var node: Vector2i = path[i]
		var p := node_pos(node)
		if i == 0:
			var d := seg_dir(path[0], path[1])
			pts.append(p + right_of(d) * lane_offset)
		elif i == path.size() - 1:
			var d := seg_dir(path[i - 1], path[i])
			pts.append(p + right_of(d) * lane_offset)
		else:
			var d1 := seg_dir(path[i - 1], path[i])
			var d2 := seg_dir(path[i], path[i + 1])
			pts.append(p + right_of(d1) * lane_offset + right_of(d2) * lane_offset)
	return pts


static func polyline_length(pts: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i].distance_to(pts[i - 1])
	return total


## Converts a world position to minimap space (0..1 in both axes).
static func to_map_uv(world: Vector3) -> Vector2:
	var half := half_extent() + ROAD_WIDTH
	return Vector2((world.x + half) / (half * 2.0), (world.z + half) / (half * 2.0))
