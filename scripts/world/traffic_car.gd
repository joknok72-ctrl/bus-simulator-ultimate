class_name TrafficCar
extends AnimatableBody3D
## Ambient traffic. Each car drives a rectangular loop around city blocks in the
## right-hand lane, slows down before corners, stops at red traffic lights and stops when
## the bus or another car is directly ahead. Cars are collidable so the bus takes damage
## when it hits them.

const CAR_COLORS: Array[Color] = [
	Color(0.9, 0.9, 0.92), Color(0.15, 0.15, 0.18), Color(0.7, 0.12, 0.12), Color(0.15, 0.35, 0.75),
	Color(0.6, 0.62, 0.65), Color(0.85, 0.6, 0.15), Color(0.2, 0.55, 0.35), Color(0.45, 0.2, 0.55),
]
## Cars that have been blocking each other for this long resolve the stand-off (see _find_obstacle).
const DEADLOCK_TIME := 4.0

var cruise_speed := 10.0
var speed := 0.0
var waypoints: PackedVector3Array = PackedVector3Array()
var nodes: Array[Vector2i] = []        # grid node of the intersection each waypoint lies in
var wp_index := 0
var blocked_timer := 0.0
var half_length := 2.3
var signals: TrafficSignals = null
## True while the car is slowing for / standing at a red (or yellow) light.
var waiting_at_light := false
## True while the car waits for a legitimate reason - a red light, the bus, or a car that is
## itself queued. Queued cars are never "overtaken" by the deadlock breaker.
var queued := false

var _blocker: TrafficCar = null
var _committed_node := TrafficSignals.NO_NODE   # crossing the car decided to clear on yellow

static var all_cars: Array[TrafficCar] = []
static var bus_ref: Node3D = null


## Lane waypoints for a loop of grid nodes driven in order: one point per corner, offset
## into the right-hand lane of both the incoming and the outgoing street (so the car cuts the
## corner the way a real right turn does). Used by CityBuilder and the smoke test.
static func loop_points(loop: Array[Vector2i], lane: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for k in loop.size():
		var prev: Vector2i = loop[(k - 1 + loop.size()) % loop.size()]
		var cur: Vector2i = loop[k]
		var next: Vector2i = loop[(k + 1) % loop.size()]
		var d1 := CityLayout.seg_dir(prev, cur)
		var d2 := CityLayout.seg_dir(cur, next)
		pts.append(CityLayout.node_pos(cur) + CityLayout.right_of(d1) * lane + CityLayout.right_of(d2) * lane)
	return pts


func _init() -> void:
	sync_to_physics = false
	collision_layer = 4
	collision_mask = 0


func _ready() -> void:
	all_cars.append(self)


func _exit_tree() -> void:
	all_cars.erase(self)


func setup(loop_points: PackedVector3Array, loop_nodes: Array[Vector2i], start_index: int, night: bool,
		is_truck: bool = false, traffic_signals: TrafficSignals = null) -> void:
	waypoints = loop_points
	nodes = loop_nodes
	signals = traffic_signals
	wp_index = start_index % waypoints.size()
	cruise_speed = randf_range(8.0, 12.5) if not is_truck else randf_range(6.5, 9.0)
	speed = cruise_speed
	half_length = 3.5 if is_truck else 2.3
	_build_visual(night, is_truck)
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.9, 1.5, 4.6) if not is_truck else Vector3(2.3, 2.6, 7.0)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, shape.size.y * 0.5, 0)
	add_child(cs)
	# Start somewhere on the first segment.
	var prev := waypoints[(wp_index - 1 + waypoints.size()) % waypoints.size()]
	var next := waypoints[wp_index]
	global_position = prev.lerp(next, randf_range(0.2, 0.8))
	_face(next)
	reset_physics_interpolation()


func _build_visual(night: bool, is_truck: bool) -> void:
	# The whole car (body, glass, wheels, lights) is baked into one mesh: 4-5 draw calls
	# instead of ~14. Plain cylinder wheels look identical whether they spin or not.
	var color := CAR_COLORS[randi() % CAR_COLORS.size()]
	var paint := MeshFactory.mat(color, 0.35, 0.4)
	var glass := MeshFactory.glass_mat(Color(0.2, 0.3, 0.4, 0.8))
	var dark := MeshFactory.mat(Color(0.08, 0.08, 0.09), 0.9)
	var m := MeshMerger.new()
	if is_truck:
		m.add_box(Vector3(2.2, 1.3, 2.2), Vector3(0, 1.05, -2.2), paint)
		m.add_box(Vector3(2.3, 2.3, 4.4), Vector3(0, 1.55, 1.1), MeshFactory.mat(color.lightened(0.3), 0.7))
		m.add_box(Vector3(2.3, 0.4, 6.8), Vector3(0, 0.55, 0), dark)
		for z in [-2.2, 0.6, 1.9]:
			for x in [-1.05, 1.05]:
				m.add_cylinder(0.5, 0.35, Vector3(x, 0.5, z), dark, Vector3(0, 0, PI * 0.5), 10)
		m.add_box(Vector3(2.1, 0.9, 1.0), Vector3(0, 2.1, -2.5), glass)
	else:
		m.add_box(Vector3(1.8, 0.55, 4.3), Vector3(0, 0.62, 0), paint)
		m.add_box(Vector3(1.6, 0.55, 2.2), Vector3(0, 1.15, 0.15), paint)
		m.add_box(Vector3(1.85, 0.2, 4.4), Vector3(0, 0.3, 0), dark)
		for z in [-1.4, 1.4]:
			for x in [-0.85, 0.85]:
				m.add_cylinder(0.34, 0.25, Vector3(x, 0.34, z), dark, Vector3(0, 0, PI * 0.5), 10)
		m.add_box(Vector3(1.62, 0.5, 2.0), Vector3(0, 1.17, 0.15), glass)
	# Lights
	var head_mat := MeshFactory.mat(Color(1, 1, 0.9), 0.2, 0.0, Color(1.0, 0.95, 0.8), 3.0 if night else 0.0)
	var tail_mat := MeshFactory.mat(Color(0.8, 0.1, 0.1), 0.3, 0.0, Color(1.0, 0.1, 0.1), 2.0 if night else 0.0)
	var front_z := -3.3 if is_truck else -2.16
	var back_z := 3.5 if is_truck else 2.16
	var light_y := 1.0 if is_truck else 0.65
	for x in [-0.6, 0.6]:
		m.add_box(Vector3(0.35, 0.18, 0.06), Vector3(x, light_y, front_z), head_mat)
		m.add_box(Vector3(0.35, 0.16, 0.06), Vector3(x, light_y, back_z), tail_mat)
	m.instance(self, "Body")


func _face(target: Vector3) -> void:
	var flat := Vector3(target.x, global_position.y, target.z)
	if flat.distance_squared_to(global_position) > 0.01:
		look_at(flat, Vector3.UP)


func _physics_process(delta: float) -> void:
	if waypoints.size() < 2:
		return
	var target := waypoints[wp_index]
	var to_target := target - global_position
	to_target.y = 0.0
	var dist := to_target.length()
	if dist < 1.2:
		wp_index = (wp_index + 1) % waypoints.size()
		target = waypoints[wp_index]
		to_target = target - global_position
		to_target.y = 0.0
		dist = to_target.length()
	var desired := cruise_speed
	# Slow down before corners.
	if dist < 10.0:
		desired = minf(desired, lerpf(4.0, cruise_speed, clampf((dist - 2.0) / 8.0, 0.0, 1.0)))
	# Traffic lights: roll to a stop at the white line when the signal ahead is red.
	var hold := _signal_hold_distance()
	waiting_at_light = hold >= 0.0
	if waiting_at_light:
		desired = minf(desired, lerpf(0.0, cruise_speed, clampf((hold - 0.6) / 14.0, 0.0, 1.0)))
	# Yield to the bus and to other cars ahead.
	var obstacle := _find_obstacle()
	_blocker = obstacle as TrafficCar
	queued = waiting_at_light or (obstacle != null and obstacle == bus_ref) or (_blocker != null and _blocker.queued)
	if obstacle != null:
		desired = 0.0
		# A queue behind a red light or the bus is a legitimate wait; only cars stuck behind
		# each other for no such reason count towards the deadlock breaker.
		blocked_timer = 0.0 if queued else blocked_timer + delta
	else:
		blocked_timer = 0.0
	speed = move_toward(speed, desired, (7.0 if desired < speed else 3.5) * delta)
	# Smoothly rotate toward the target.
	if dist > 0.05:
		var forward := -global_transform.basis.z
		var dir := to_target / dist
		var new_forward := forward.slerp(dir, clampf(delta * 6.0, 0.0, 1.0))
		if new_forward.length_squared() > 0.001:
			look_at(global_position + new_forward, Vector3.UP)
	global_position += -global_transform.basis.z * speed * delta


## Metres from the car's front bumper to the stop line it has to hold at, or -1.0 when it may
## drive on: green light, no signals, already over the line, or committed to clearing the
## crossing on yellow (a car too close to stop comfortably keeps going, like a real driver,
## instead of slamming the brakes when the light changes). The crossing checked is the next
## one along the current road segment, not the loop corner: a loop side spanning several
## blocks passes straight through intermediate intersections, and those have lights too.
func _signal_hold_distance() -> float:
	if signals == null or nodes.size() != waypoints.size():
		return -1.0
	var node: Vector2i = nodes[wp_index]
	var prev: Vector2i = nodes[(wp_index - 1 + nodes.size()) % nodes.size()]
	var ahead := signals.next_signal_ahead(global_position, CityLayout.seg_dir(prev, node), half_length)
	if ahead.is_empty():
		return -1.0
	var to_line := float(ahead.distance)
	var crossing: Vector2i = ahead.node
	var light := int(ahead.light)
	if to_line < -1.0:
		return -1.0
	if light == TrafficSignals.Light.GREEN:
		_committed_node = TrafficSignals.NO_NODE
		return -1.0
	if crossing == _committed_node:
		return -1.0
	if light == TrafficSignals.Light.YELLOW and to_line < speed * 1.1:
		_committed_node = crossing
		return -1.0
	return maxf(to_line, 0.0)


## The bus or the car directly ahead of this one, or null when the road is free.
func _find_obstacle() -> Node3D:
	var forward := -global_transform.basis.z
	var check_len := 6.0 + speed * 1.1
	if bus_ref != null and is_instance_valid(bus_ref):
		# The bus is 11 m long: test its front, middle and rear, not just the centre, so a car
		# approaching from the side at an intersection also stops instead of T-boning the bus,
		# which felt unfair to the player.
		# (3.0 m half-width: a car in the neighbouring lane, 3.5 m away, still passes a parked bus.)
		var bus_fwd := -bus_ref.global_transform.basis.z
		for offset in [-4.5, 0.0, 4.5]:
			if _in_front(bus_ref.global_position + bus_fwd * offset, forward, check_len + 4.0, 3.0):
				return bus_ref
	for other in all_cars:
		if other == self or not is_instance_valid(other):
			continue
		if _in_front(other.global_position, forward, check_len, 2.0):
			# Two cars waiting for each other forever (crossing paths in a junction): after a
			# while the one created later drives on. Queued cars keep a zero timer, so a line
			# of cars behind a red light or the bus never gets driven through.
			if other.blocked_timer > DEADLOCK_TIME and blocked_timer > DEADLOCK_TIME and other.get_instance_id() < get_instance_id():
				continue
			return other
	return null


func _obstacle_ahead() -> bool:
	return _find_obstacle() != null


func _in_front(point: Vector3, forward: Vector3, length: float, half_width: float) -> bool:
	var rel := point - global_position
	rel.y = 0.0
	var ahead := rel.dot(forward)
	if ahead < 0.5 or ahead > length:
		return false
	var lateral := (rel - forward * ahead).length()
	return lateral < half_width
