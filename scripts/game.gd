extends Node3D
## Mission controller for a bus route: builds the city, spawns the bus, runs the
## stop/boarding state machine, scoring, timer, collisions and the results screen.

enum State { COUNTDOWN, DRIVING, BOARDING, WAIT_CLOSE, FINISHED }

const BUS_SCENE := preload("res://scenes/bus.tscn")
const MISSED_STOP_DISTANCE := 30.0
const STOP_BONUS := 100
const PASSENGER_POINTS := 50
const MISSED_PENALTY := 200
const BOARDING_INTERVAL := 0.6

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

var _boarding_steps: Array[Callable] = []
var _boarding_timer := 0.0
var _hint_timer := 0.0
var _speeding_timer := 0.0
var _speeding_msg_timer := 0.0
var _guide_arrow: Node3D
var _arrow_bob := 0.0
var _finish_started := false


func _ready() -> void:
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
	hud.touch_controls.camera_pressed.connect(func() -> void:
		camera_rig.cycle_mode()
		AudioSynth.play("click", -6.0))
	hud.touch_controls.pause_pressed.connect(_on_pause_pressed)
	pause_menu.resume_requested.connect(_resume)
	pause_menu.restart_requested.connect(_restart)
	pause_menu.menu_requested.connect(_to_menu)
	results.retry_requested.connect(_restart)
	results.menu_requested.connect(_to_menu)
	results.next_requested.connect(_next_route)
	_build_guide_arrow()
	_update_stop_targets()
	hud.set_stats(time_left, score, onboard, delivered, total_passengers, 0.0)
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
	var mat := MeshFactory.mat(Color(0.3, 0.95, 0.4), 0.4, 0.0, Color(0.3, 1.0, 0.4), 1.5)
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


func _update_guide_arrow(delta: float, target: Vector3) -> void:
	if _guide_arrow == null or bus == null:
		return
	_arrow_bob += delta * 3.0
	var pos := bus.global_position + Vector3(0, 5.2 + sin(_arrow_bob) * 0.2, 0)
	_guide_arrow.global_position = pos
	var flat_target := Vector3(target.x, pos.y, target.z)
	if flat_target.distance_squared_to(pos) > 0.5:
		_guide_arrow.look_at(flat_target, Vector3.UP)
	_guide_arrow.visible = state != State.FINISHED and camera_rig.mode != GameState.CameraMode.DRIVER


# ---------------------------------------------------------------- main loop
func _physics_process(_delta: float) -> void:
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


func _process(delta: float) -> void:
	if bus == null:
		return
	var target := _current_target_position()
	_update_guide_arrow(delta, target)
	hud.set_speed(bus.speed_kmh(), speed_limit, bus.reverse_gear or bus.speed < -0.05, bus.doors_open)
	hud.minimap.current_stop_index = current_stop
	if state == State.FINISHED or state == State.COUNTDOWN:
		return
	time_left -= delta
	_hint_timer = maxf(0.0, _hint_timer - delta)
	if time_left <= 0.0:
		time_left = 0.0
		_finish(false, "RESULT_FAILED_TIME")
		return
	_check_speeding(delta)
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
	hud.set_stats(time_left, score, onboard, delivered, total_passengers, bus.damage)


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
	hud.show_message(tr("MSG_BOARDING"), 1.2, Color(0.8, 0.9, 1.0))


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
		if missed_stops == 0 and collisions == 0 and time_left >= float(route.time_limit) * 0.15:
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


func _exit_tree() -> void:
	TrafficCar.bus_ref = null
	AudioSynth.stop_engine()
