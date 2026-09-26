extends Node3D
## Mission controller for a bus route: builds the city, spawns the bus, runs the
## stop/boarding state machine, scoring, timer, collisions, traffic-light violations and
## the results screen.

enum State { COUNTDOWN, DRIVING, BOARDING, WAIT_CLOSE, FINISHED }

const BUS_SCENE := preload("res://scenes/bus.tscn")
const MISSED_STOP_DISTANCE := 30.0
const STOP_BONUS := 100
const PASSENGER_POINTS := 50
const MISSED_PENALTY := 200
const PERFECT_STOP_BONUS := 50
const PERFECT_STOP_TOLERANCE := 2.0    # metres along the lane from the stop marker
const RED_LIGHT_PENALTY := 100
const SIGNAL_HUD_RANGE := 80.0         # the HUD shows the next traffic light from this far away
const BOARDING_INTERVAL := 0.6
const CAMERA_NAMES: Array[String] = ["CAM_CHASE", "CAM_DRIVER", "CAM_TOP"]
## Guide arrow placement: above the bus for the outside views; in the driver view it sits
## on the road ahead of the bumper, like a navigation arrow projected on the tarmac.
const ARROW_ABOVE := Vector3(0, 5.2, 0)
const ARROW_AHEAD_DISTANCE := 14.0
const ARROW_AHEAD_MIN := 7.0
const ARROW_HIDE_DISTANCE := 9.0
const ARROW_AHEAD_HEIGHT := 0.6
const ARROW_AHEAD_SCALE := 1.3
const ARROW_TILT := deg_to_rad(32.0)   # nose up, so the flat arrow is readable from behind

@onready var world: CityBuilder = $World
@onready var camera_rig: CameraRig = $CameraRig
@onready var hud: Hud = $HUDLayer/HUD
@onready var pause_menu: PauseMenu = $PauseLayer/PauseMenu
@onready var results: ResultsPanel = $ResultsLayer/ResultsPanel

var route: Dictionary
var bus: Bus
var state: State = State.COUNTDOWN
var time_left := 0.0
var score := 0
var onboard := 0
var delivered := 0
var collisions := 0
var missed_stops := 0
var stops_served := 0
var current_stop := 0
var total_passengers := 0
var speed_limit := 50
var perfect_stops := 0
var red_lights := 0
## Turn-by-turn guidance along the route polyline (next corner / stop, off-route detection).
var guide := RouteGuide.new()
var guidance: Dictionary = {}

var _boarding_steps: Array[Callable] = []
var _boarding_timer := 0.0
var _hint_timer := 0.0
var _speeding_timer := 0.0
var _speeding_msg_timer := 0.0
var _guide_arrow: Node3D
var _arrow_mat: StandardMaterial3D
var _arrow_bob := 0.0
var _finish_started := false
var _was_off_route := false
var _perfect_awarded: Dictionary = {}   # stop index -> true (bonus paid once per stop)
var _bus_intersection := TrafficSignals.NO_NODE   # crossing the bus's front bumper is currently in


func _ready() -> void:
	# Run after the bus has moved this tick so the guide arrow follows the current position
	# (the camera rig runs even later, see CameraRig._ready).
	process_physics_priority = 10
	route = RouteData.get_route(GameState.selected_route_id)
	speed_limit = int(route.get("speed_limit", 50))
	time_left = float(route.get("time_limit", 150))
	total_passengers = RouteData.total_passengers(route)
	_apply_quality()
	world.build(route, int(GameState.settings.quality))
	# Bus
	bus = BUS_SCENE.instantiate() as Bus
	add_child(bus)
	bus.global_transform = world.get_spawn_transform()
	bus.reset_physics_interpolation()
	bus.configure(GameState.get_bus_color(), world.night)
	bus.engine_on = false
	bus.collided.connect(_on_bus_collided)
	bus.doors_changed.connect(_on_doors_changed)
	TrafficCar.bus_ref = bus
	camera_rig.set_bus(bus)
	# HUD wiring
	hud.minimap.route_points = world.route_points
	hud.minimap.stops = world.stops
	hud.minimap.terminal = world.terminal
	hud.minimap.bus = bus
	hud.minimap.cars = world.cars
	hud.touch_controls.horn_pressed.connect(func() -> void: bus.honk())
	hud.touch_controls.doors_pressed.connect(_on_doors_button)
	hud.touch_controls.camera_pressed.connect(_on_camera_button)
	hud.touch_controls.pause_pressed.connect(_on_pause_pressed)
	pause_menu.resume_requested.connect(_resume)
	pause_menu.restart_requested.connect(_restart)
	pause_menu.menu_requested.connect(_to_menu)
	results.retry_requested.connect(_restart)
	results.menu_requested.connect(_to_menu)
	results.next_requested.connect(_next_route)
	_build_guide_arrow()
	guide.setup(world.route_points)
	_update_stop_targets()
	_update_guidance()
	hud.set_stats(time_left, score, onboard, delivered, total_passengers, 0.0)
	hud.set_next_stop(current_stop, bus.global_position.distance_to(_current_target_position()), false, world.stops.size())
	hud.set_guidance(guidance)
	_run_countdown()


func _apply_quality() -> void:
	var high := int(GameState.settings.quality) >= 1
	get_viewport().msaa_3d = Viewport.MSAA_2X if high else Viewport.MSAA_DISABLED
	get_viewport().scaling_3d_scale = 1.0 if high else 0.8


func _run_countdown() -> void:
	for text in ["3", "2", "1"]:
		hud.show_countdown(text, 0.55)
		AudioSynth.play("click", -4.0, 0.9)
		await get_tree().create_timer(0.85).timeout
		if not is_inside_tree():
			return
	hud.show_countdown(tr("COUNTDOWN_GO"), 0.6)
	AudioSynth.play("ding", -2.0)
	bus.engine_on = true
	state = State.DRIVING
	hud.show_message(tr("MSG_GO"), 2.5, Color(0.6, 1.0, 0.6))


# ---------------------------------------------------------------- guide arrow
func _build_guide_arrow() -> void:
	_guide_arrow = Node3D.new()
	add_child(_guide_arrow)
	# Unshaded so it stays a readable green instead of blowing out to white in sunlight.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.9, 0.35)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arrow_mat = mat
	var shaft := BoxMesh.new()
	shaft.size = Vector3(0.5, 0.25, 1.6)
	var shaft_mi := MeshInstance3D.new()
	shaft_mi.mesh = shaft
	shaft_mi.material_override = mat
	shaft_mi.position = Vector3(0, 0, 0.6)
	_guide_arrow.add_child(shaft_mi)
	var head := PrismMesh.new()
	head.size = Vector3(1.6, 1.4, 0.25)
	var head_mi := MeshInstance3D.new()
	head_mi.mesh = head
	head_mi.material_override = mat
	# Prism points up (+Y); rotate so the tip points forward (-Z) and lies flat.
	head_mi.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	head_mi.position = Vector3(0, 0, -0.9)
	_guide_arrow.add_child(head_mi)


## Recomputes where the route guidance points (next corner, the stop itself, or back to the
## route when the bus has left it).
func _update_guidance() -> void:
	guidance = guide.guidance(bus.global_position, _current_target_position(), current_stop >= world.stops.size())


func _update_guide_arrow(delta: float) -> void:
	if _guide_arrow == null or bus == null or guidance.is_empty():
		return
	_arrow_bob += delta * 3.0
	var turn: int = int(guidance.turn)
	var target: Vector3 = guidance.guide_point
	var off_route := turn == RouteGuide.Turn.OFF_ROUTE
	var at_target := turn == RouteGuide.Turn.STOP or turn == RouteGuide.Turn.TERMINAL
	var dist := Vector2(target.x - bus.global_position.x, target.z - bus.global_position.z).length()
	var driver := camera_rig.is_driver_view()
	var pos: Vector3
	if driver:
		# On the road ahead, where the driver is looking. It slides closer (and shrinks) as the
		# corner or stop comes near so it never sits beyond it pointing back at the bus.
		var ahead := clampf(dist - 4.0, ARROW_AHEAD_MIN, ARROW_AHEAD_DISTANCE)
		var far_t := (ahead - ARROW_AHEAD_MIN) / (ARROW_AHEAD_DISTANCE - ARROW_AHEAD_MIN)
		pos = bus.global_position - bus.global_transform.basis.z * ahead + Vector3(0, ARROW_AHEAD_HEIGHT + sin(_arrow_bob) * 0.08, 0)
		_guide_arrow.scale = Vector3.ONE * lerpf(1.0, ARROW_AHEAD_SCALE, far_t)
	else:
		pos = bus.global_position + ARROW_ABOVE + Vector3(0, sin(_arrow_bob) * 0.2, 0)
		_guide_arrow.scale = Vector3.ONE
	_guide_arrow.global_position = pos
	var flat_target := Vector3(target.x, pos.y, target.z)
	if flat_target.distance_squared_to(pos) > 0.5:
		_guide_arrow.look_at(flat_target, Vector3.UP)
		# Nose up: every camera looks at the arrow from above and behind.
		_guide_arrow.rotate_object_local(Vector3.RIGHT, ARROW_TILT)
	_arrow_mat.albedo_color = Color(1.0, 0.55, 0.25) if off_route else Color(0.25, 0.9, 0.35)
	# Hidden once the bus is at the stop (boarding) and, in the cockpit, when the stop is so close
	# that the painted stop zone and the shelter are already in view.
	var at_stop := state == State.BOARDING or state == State.WAIT_CLOSE
	_guide_arrow.visible = state != State.FINISHED and not at_stop and not (driver and at_target and dist < ARROW_HIDE_DISTANCE)


func _on_camera_button() -> void:
	camera_rig.cycle_mode()
	AudioSynth.play("click", -6.0)
	hud.show_message(tr(CAMERA_NAMES[camera_rig.mode]), 0.9, Color(0.85, 0.9, 1.0))


# ---------------------------------------------------------------- main loop
func _physics_process(delta: float) -> void:
	if bus == null:
		return
	var tc := hud.touch_controls
	if state == State.FINISHED or state == State.COUNTDOWN:
		bus.input_throttle = 0.0
		bus.input_brake = 1.0 if state == State.FINISHED else 0.0
		bus.input_steer = 0.0
	else:
		bus.input_steer = tc.steer
		bus.input_throttle = tc.throttle
		bus.input_brake = tc.brake
	# The arrow follows the (physics-driven) bus, so move it on the physics tick too.
	_update_guidance()
	_update_guide_arrow(delta)
	_check_red_light()


func _process(delta: float) -> void:
	if bus == null:
		return
	var target := _current_target_position()
	hud.set_speed(bus.speed_kmh(), speed_limit, bus.reverse_gear or bus.speed < -0.05, bus.doors_open)
	hud.minimap.current_stop_index = current_stop
	_update_signal_hud()
	if state == State.FINISHED or state == State.COUNTDOWN:
		return
	time_left -= delta
	_hint_timer = maxf(0.0, _hint_timer - delta)
	if time_left <= 0.0:
		time_left = 0.0
		_finish(false, "RESULT_FAILED_TIME")
		return
	_check_speeding(delta)
	_check_off_route()
	match state:
		State.DRIVING:
			_process_driving()
		State.BOARDING:
			_process_boarding(delta)
		State.WAIT_CLOSE:
			if not bus.doors_open:
				_complete_stop()
	var dist := bus.global_position.distance_to(target)
	hud.set_next_stop(current_stop, dist, current_stop >= world.stops.size(), world.stops.size())
	hud.set_guidance(guidance)
	hud.minimap.progress_seg = int(guidance.get("seg", -1))
	hud.set_stats(time_left, score, onboard, delivered, total_passengers, bus.damage)


func _check_off_route() -> void:
	var off := guide.off_route
	if off and not _was_off_route:
		hud.show_message(tr("MSG_OFF_ROUTE"), 2.5, Color(1.0, 0.65, 0.4))
		AudioSynth.play("fail", -10.0, 1.3)
	_was_off_route = off


# ---------------------------------------------------------------- traffic lights
## Penalises driving into a signalised crossing while the light for the bus's direction is
## red. The reference point is the front bumper entering the crossing square itself (the
## white stop line lies TrafficSignals.STOP_LINE_OFFSET metres before it, so creeping over
## the line is not fined), and TrafficSignals.RED_GRACE tolerates a bumper that is over the
## edge a split second after the change to red. Charged once per entry.
func _check_red_light() -> void:
	var sig := world.signals
	if sig == null:
		return
	var front := bus.global_position - bus.global_transform.basis.z * (Bus.LENGTH * 0.5)
	if _bus_intersection != TrafficSignals.NO_NODE:
		# Still in the same crossing (with a little hysteresis so a bus standing right on the
		# edge does not count as entering twice).
		if TrafficSignals.intersection_at(front, 1.0) == _bus_intersection:
			return
		_bus_intersection = TrafficSignals.NO_NODE
	var node := TrafficSignals.intersection_at(front)
	if node == TrafficSignals.NO_NODE:
		return
	_bus_intersection = node
	if state != State.DRIVING:
		return
	var axis := TrafficSignals.axis_of(-bus.global_transform.basis.z)
	if sig.light_for(axis) == TrafficSignals.Light.RED and sig.red_seconds(axis) > TrafficSignals.RED_GRACE:
		red_lights += 1
		score = maxi(0, score - RED_LIGHT_PENALTY)
		hud.show_message(tr("MSG_RED_LIGHT") % RED_LIGHT_PENALTY, 2.0, Color(1.0, 0.4, 0.35))
		AudioSynth.play("fail", -6.0, 1.15)
		GameState.vibrate(120)


## Feeds the HUD the traffic light the bus is heading towards, when one is reasonably close.
func _update_signal_hud() -> void:
	var sig := world.signals
	if sig == null or state == State.FINISHED:
		hud.set_signal({})
		return
	var info := sig.next_signal_ahead(bus.global_position, -bus.global_transform.basis.z, Bus.LENGTH * 0.5)
	if info.is_empty() or float(info.distance) > SIGNAL_HUD_RANGE:
		hud.set_signal({})
	else:
		hud.set_signal(info)


func _current_target_position() -> Vector3:
	if current_stop < world.stops.size():
		return world.stops[current_stop].global_position
	return world.terminal.global_position


func _update_stop_targets() -> void:
	for i in world.stops.size():
		world.stops[i].set_active(i == current_stop)
	world.terminal.set_active(current_stop >= world.stops.size())


func _process_driving() -> void:
	var stopped := bus.speed_kmh() < 1.0
	if current_stop < world.stops.size():
		var stop := world.stops[current_stop]
		if stop.is_bus_in_zone(bus.global_position):
			if stopped and bus.doors_open:
				_begin_boarding(stop)
			elif stopped and _hint_timer <= 0.0:
				hud.show_message(tr("MSG_OPEN_DOORS"), 1.6, Color(1.0, 0.9, 0.5))
				_hint_timer = 2.5
			elif not stopped and _hint_timer <= 0.0 and bus.speed_kmh() < 25.0:
				hud.show_message(tr("MSG_STOP_HERE"), 1.0, Color(1.0, 0.9, 0.5))
				_hint_timer = 2.0
		elif stop.distance_past(bus.global_position) > MISSED_STOP_DISTANCE:
			_miss_stop(stop)
	else:
		if world.terminal.is_bus_in_zone(bus.global_position) and stopped:
			_finish(true, "RESULT_COMPLETE")


func _begin_boarding(stop: BusStop) -> void:
	state = State.BOARDING
	_boarding_steps.clear()
	# Some passengers get off first (never at the first stop).
	var alighting := 0
	if current_stop > 0 and onboard > 0:
		alighting = mini(onboard, randi_range(1, 2))
	for i in alighting:
		_boarding_steps.append(func() -> void: _alight_one(stop))
	for p in stop.waiting.duplicate():
		_boarding_steps.append(func() -> void: _board_one(stop, p))
	_boarding_steps.append(func() -> void: pass)   # small pause after the last passenger
	_boarding_timer = 0.3
	if _is_perfect_stop(stop) and not _perfect_awarded.has(current_stop):
		_perfect_awarded[current_stop] = true
		perfect_stops += 1
		score += PERFECT_STOP_BONUS
		hud.show_message(tr("MSG_PERFECT_STOP") % PERFECT_STOP_BONUS, 1.6, Color(0.6, 1.0, 0.7))
		AudioSynth.play("ding", -4.0, 1.25)
		GameState.vibrate(40)
	else:
		hud.show_message(tr("MSG_BOARDING"), 1.2, Color(0.8, 0.9, 1.0))


## A perfect stop: centred on the stop marker along the lane, next to the kerb and parallel
## to it. Rewards precise driving instead of just "somewhere inside the yellow zone".
func _is_perfect_stop(stop: BusStop) -> bool:
	var local := stop.to_local(bus.global_position)
	var aligned := (-bus.global_transform.basis.z).dot(-stop.global_transform.basis.z) > 0.985
	return absf(local.z) <= PERFECT_STOP_TOLERANCE and absf(local.x) <= 1.0 and aligned


func _process_boarding(delta: float) -> void:
	_boarding_timer -= delta
	if _boarding_timer > 0.0:
		return
	if _boarding_steps.is_empty():
		state = State.WAIT_CLOSE
		hud.show_message(tr("MSG_CLOSE_DOORS"), 2.0, Color(0.6, 1.0, 0.6))
		AudioSynth.play("ding", -6.0)
		return
	var step: Callable = _boarding_steps.pop_front()
	step.call()
	_boarding_timer = BOARDING_INTERVAL


func _alight_one(stop: BusStop) -> void:
	if onboard <= 0:
		return
	onboard -= 1
	delivered += 1
	score += PASSENGER_POINTS
	var p := Passenger.new()
	world.add_child(p)
	p.alight(bus.rear_door_position(), stop.sidewalk_point(), 1.1)
	AudioSynth.play("coin", -10.0, 1.1)


func _board_one(stop: BusStop, p: Passenger) -> void:
	if p == null or not is_instance_valid(p):
		return
	stop.waiting.erase(p)
	onboard += 1
	score += PASSENGER_POINTS
	p.board(bus.front_door_position(), 0.9)
	AudioSynth.play("coin", -8.0)


func _complete_stop() -> void:
	var stop := world.stops[current_stop]
	stop.mark_served()
	stops_served += 1
	score += STOP_BONUS
	hud.show_message(tr("MSG_STOP_DONE") % STOP_BONUS, 1.8, Color(0.6, 1.0, 0.6))
	AudioSynth.play("success", -6.0)
	current_stop += 1
	_update_stop_targets()
	state = State.DRIVING
	if current_stop >= world.stops.size():
		await get_tree().create_timer(1.6).timeout
		if is_inside_tree() and state != State.FINISHED:
			hud.show_message(tr("MSG_TERMINAL"), 2.5, Color(0.6, 0.9, 1.0))


func _miss_stop(stop: BusStop) -> void:
	stop.mark_served()
	missed_stops += 1
	score = maxi(0, score - MISSED_PENALTY)
	hud.show_message(tr("MSG_STOP_MISSED"), 2.2, Color(1.0, 0.45, 0.4))
	AudioSynth.play("fail", -8.0)
	current_stop += 1
	_update_stop_targets()
	state = State.DRIVING


func _on_doors_changed(open: bool) -> void:
	if not open and state == State.BOARDING:
		# Doors closed early: remaining passengers keep waiting.
		_boarding_steps.clear()
		state = State.DRIVING


func _on_doors_button() -> void:
	if state == State.FINISHED or state == State.COUNTDOWN:
		return
	if not bus.toggle_doors():
		hud.show_message(tr("MSG_STOP_HERE"), 1.0, Color(1.0, 0.9, 0.5))


func _check_speeding(delta: float) -> void:
	_speeding_msg_timer = maxf(0.0, _speeding_msg_timer - delta)
	if bus.speed_kmh() > speed_limit + 5.0:
		_speeding_timer += delta
		if _speeding_timer >= 1.0:
			_speeding_timer -= 1.0
			score = maxi(0, score - 5)
		if _speeding_msg_timer <= 0.0:
			hud.show_message(tr("MSG_SPEEDING") % speed_limit, 1.2, Color(1.0, 0.55, 0.4))
			_speeding_msg_timer = 4.0
	else:
		_speeding_timer = 0.0


func _on_bus_collided(strength: float) -> void:
	if state == State.FINISHED:
		return
	collisions += 1
	var penalty := mini(150, 40 + int(strength * 12.0))
	score = maxi(0, score - penalty)
	bus.apply_damage(clampf(strength * 3.5, 4.0, 30.0))
	camera_rig.add_shake(clampf(strength / 6.0, 0.2, 1.0))
	hud.flash_damage()
	hud.show_message(tr("MSG_COLLISION") % penalty, 1.5, Color(1.0, 0.4, 0.35))
	AudioSynth.play("hit", -2.0, randf_range(0.9, 1.1))
	GameState.vibrate(int(clampf(strength * 40.0, 60.0, 250.0)))
	if bus.damage >= 100.0:
		_finish(false, "RESULT_FAILED_DAMAGE")


# ---------------------------------------------------------------- finishing
func _finish(success: bool, title_key: String) -> void:
	if _finish_started:
		return
	_finish_started = true
	state = State.FINISHED
	bus.engine_on = false
	AudioSynth.stop_engine()
	hud.touch_controls.release_all()
	var time_bonus := int(time_left) * 5 if success else 0
	if success:
		# Everyone still on board gets off at the terminal.
		var leaving := onboard
		delivered += leaving
		score += leaving * PASSENGER_POINTS
		onboard = 0
		bus.set_doors(true)
		for i in mini(leaving, 6):
			var p := Passenger.new()
			world.add_child(p)
			p.alight(bus.rear_door_position(), world.terminal.sidewalk_point(), 1.2)
		AudioSynth.play("success", -2.0)
	else:
		AudioSynth.play("fail", -2.0)
	var total := score + time_bonus
	var stars := 0
	if success:
		stars = 1
		if missed_stops == 0 and collisions <= 2:
			stars = 2
		if missed_stops == 0 and collisions == 0 and red_lights == 0 and time_left >= float(route.time_limit) * 0.15:
			stars = 3
	var coins := int(total / 10) if success else int(total / 25)
	var new_best := false
	if success:
		new_best = GameState.record_result(String(route.id), total, stars, coins)
	elif coins > 0:
		GameState.add_coins(coins)
		GameState.save_game()
	GameState.last_result = {
		"route_id": route.id, "success": success, "title_key": title_key, "score": score,
		"time_bonus": time_bonus, "total": total, "stars": stars, "coins": coins,
		"delivered": delivered, "total_passengers": total_passengers, "stops_served": stops_served,
		"stops_total": world.stops.size(), "collisions": collisions, "new_best": new_best,
		"perfect_stops": perfect_stops, "red_lights": red_lights,
	}
	await get_tree().create_timer(1.8).timeout
	if is_inside_tree():
		results.show_results(GameState.last_result)


# ---------------------------------------------------------------- pause / navigation
func _on_pause_pressed() -> void:
	if state == State.FINISHED:
		return
	if get_tree().paused:
		_resume()
		return
	hud.touch_controls.release_all()
	AudioSynth.play("click", -6.0)
	AudioSynth.stop_engine()
	get_tree().paused = true
	pause_menu.open()


func _resume() -> void:
	pause_menu.close()
	get_tree().paused = false


func _restart() -> void:
	get_tree().paused = false
	AudioSynth.stop_engine()
	GameState.change_scene("res://scenes/game.tscn")


func _to_menu() -> void:
	get_tree().paused = false
	AudioSynth.stop_engine()
	GameState.change_scene("res://scenes/ui/main_menu.tscn")


func _next_route() -> void:
	var next_id := RouteData.next_route_id(String(route.id))
	if next_id != "":
		GameState.selected_route_id = next_id
		_restart()
	else:
		_to_menu()


func _notification(what: int) -> void:
	# Android back button: pause instead of quitting (results screen has its own buttons).
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_inside_tree() and not results.visible:
		_on_pause_pressed()


func _exit_tree() -> void:
	TrafficCar.bus_ref = null
	AudioSynth.stop_engine()
