class_name Passenger
extends Node3D
## A simple low-poly passenger who waits at a bus stop, walks into the bus when the
## doors open, and walks out again at a later stop.

const SHIRT_COLORS: Array[Color] = [
	Color(0.85, 0.3, 0.25), Color(0.25, 0.5, 0.85), Color(0.3, 0.7, 0.4),
	Color(0.9, 0.75, 0.2), Color(0.6, 0.35, 0.7), Color(0.95, 0.95, 0.95),
	Color(0.2, 0.2, 0.25), Color(0.95, 0.55, 0.2),
]
const SKIN_COLORS: Array[Color] = [
	Color(0.98, 0.82, 0.68), Color(0.85, 0.62, 0.45), Color(0.55, 0.36, 0.25), Color(0.95, 0.75, 0.6),
]

var _body: Node3D
var _walk_tween: Tween
var _bob_time := 0.0
var _walking := false


func _ready() -> void:
	_build()


func _build() -> void:
	_body = Node3D.new()
	add_child(_body)
	var shirt := SHIRT_COLORS[randi() % SHIRT_COLORS.size()]
	var skin := SKIN_COLORS[randi() % SKIN_COLORS.size()]
	var pants := Color(0.15, 0.17, 0.25) if randf() < 0.6 else Color(0.35, 0.3, 0.28)
	# legs
	MeshFactory.box(_body, Vector3(0.36, 0.75, 0.3), Vector3(0, 0.375, 0), MeshFactory.mat(pants))
	# torso (capsule)
	var torso := CapsuleMesh.new()
	torso.radius = 0.24
	torso.height = 0.85
	torso.radial_segments = 8
	torso.rings = 4
	var torso_mi := MeshInstance3D.new()
	torso_mi.mesh = torso
	torso_mi.material_override = MeshFactory.mat(shirt)
	torso_mi.position = Vector3(0, 1.15, 0)
	_body.add_child(torso_mi)
	# head
	MeshFactory.sphere(_body, 0.17, Vector3(0, 1.72, 0), MeshFactory.mat(skin), 10)
	# hair / cap
	if randf() < 0.7:
		var hair := SphereMesh.new()
		hair.radius = 0.18
		hair.height = 0.2
		hair.radial_segments = 10
		hair.rings = 4
		var hair_mi := MeshInstance3D.new()
		hair_mi.mesh = hair
		hair_mi.material_override = MeshFactory.mat(Color(0.12, 0.09, 0.07) if randf() < 0.7 else Color(0.5, 0.35, 0.2))
		hair_mi.position = Vector3(0, 1.8, 0)
		_body.add_child(hair_mi)
	scale = Vector3.ONE * randf_range(0.9, 1.05)


func _process(delta: float) -> void:
	if _walking:
		_bob_time += delta * 14.0
		_body.position.y = absf(sin(_bob_time)) * 0.06
		_body.rotation.z = sin(_bob_time) * 0.05
	elif _body.position.y != 0.0:
		_body.position.y = 0.0
		_body.rotation.z = 0.0


## Walks to a world position. Returns the tween so callers can await it.
func walk_to(target: Vector3, duration: float) -> Tween:
	if _walk_tween and _walk_tween.is_valid():
		_walk_tween.kill()
	var flat_target := Vector3(target.x, global_position.y, target.z)
	if flat_target.distance_to(global_position) > 0.05:
		look_at(flat_target, Vector3.UP)
	_walking = true
	_walk_tween = create_tween()
	_walk_tween.tween_property(self, "global_position", flat_target, duration).set_trans(Tween.TRANS_SINE)
	_walk_tween.finished.connect(func() -> void: _walking = false)
	return _walk_tween


## Walks into the bus door and disappears.
func board(door_position: Vector3, duration: float) -> void:
	var tween := walk_to(door_position, duration)
	tween.finished.connect(func() -> void:
		if is_inside_tree():
			queue_free()
	)


## Appears at the door, walks to the sidewalk and disappears a moment later.
func alight(door_position: Vector3, sidewalk_target: Vector3, duration: float) -> void:
	global_position = Vector3(door_position.x, 0.0, door_position.z)
	var tween := walk_to(sidewalk_target, duration)
	tween.finished.connect(func() -> void:
		if is_inside_tree():
			var fade := create_tween()
			fade.tween_interval(1.5)
			fade.tween_property(self, "scale", Vector3.ONE * 0.01, 0.4)
			fade.tween_callback(queue_free)
	)
