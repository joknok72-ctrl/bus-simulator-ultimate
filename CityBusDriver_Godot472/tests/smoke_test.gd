extends SceneTree
## Headless smoke test for City Bus Driver.
## Run from the project folder with the exact engine version:
##   Godot_v4.7.2-stable_linux.x86_64 --headless --path . -s res://tests/smoke_test.gd
## Exit code 0 = all checks passed.

const STATE_DRIVING := 1
const STATE_BOARDING := 2
const STATE_WAIT_CLOSE := 3
const STATE_FINISHED := 4

var _failures := 0
var _checks := 0


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  [PASS] %s" % label)
	else:
		_failures += 1
		printerr("  [FAIL] %s" % label)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	print("== City Bus Driver smoke test (Godot %s) ==" % Engine.get_version_info().string)
	# Speed up physics so the test does not take long in real time.
	Engine.physics_ticks_per_second = 240
	Engine.max_physics_steps_per_frame = 32
	await _test_autoloads()
	await _test_main_menu()
	await _test_gameplay()
	await _test_all_routes()
	print("== %d checks, %d failures ==" % [_checks, _failures])
	if _failures == 0:
		print("SMOKE TEST OK")
	quit(0 if _failures == 0 else 1)


func _test_autoloads() -> void:
	print("-- autoloads")
	var gs := root.get_node_or_null("GameState")
	var audio := root.get_node_or_null("AudioSynth")
	_check(gs != null, "GameState autoload present")
	_check(audio != null, "AudioSynth autoload present")
	if audio:
		_check(audio.sounds.size() >= 9, "procedural sounds generated (%d)" % audio.sounds.size())
	if gs:
		_check(RouteData.all().size() == 4, "4 routes defined")
		gs.set_setting("language", "ar")
		_check(tr("MENU_PLAY") == "ابدأ اللعب", "Arabic translation loaded")
		gs.set_setting("language", "en")
		_check(tr("MENU_PLAY") == "Play", "English translation loaded")
		_check(gs.is_route_unlocked(RouteData.get_route("route_1")), "route_1 unlocked by default")
	await _frames(1)


func _test_main_menu() -> void:
	print("-- main menu")
	var packed: PackedScene = load("res://scenes/ui/main_menu.tscn")
	_check(packed != null, "main_menu.tscn loads")
	if packed == null:
		return
	var menu := packed.instantiate()
	root.add_child(menu)
	await _frames(3)
	_check(menu.get_node("Turntable/Bus") != null, "menu bus instanced")
	for page_name in ["PageRoutes", "PageGarage", "PageSettings", "PageHowTo", "PageAbout", "PageHome"]:
		menu._show_page(menu.get_node("UI/Root/" + page_name), false)
		await _frames(1)
	_check(menu.get_node("UI/Root/PageRoutes/Cards").get_child_count() == 4, "4 route cards built")
	_check(menu.get_node("UI/Root/PageGarage/Cards").get_child_count() == 6, "6 garage cards built")
	_check(menu.get_node("UI/Root/PageSettings/Panel/Grid").get_child_count() == 16, "settings rows built")
	var about_count: int = menu.get_node("UI/Root/PageAbout/Panel/Scroll/Lines").get_child_count()
	_check(about_count > 10, "about/licenses page built (%d lines)" % about_count)
	menu.queue_free()
	await _frames(2)


func _test_gameplay() -> void:
	print("-- gameplay")
	var gs := root.get_node("GameState")
	gs.selected_route_id = "route_1"
	var packed: PackedScene = load("res://scenes/game.tscn")
	_check(packed != null, "game.tscn loads")
	if packed == null:
		return
	var game := packed.instantiate()
	root.add_child(game)
	await _frames(5)
	var world = game.world
	var bus = game.bus
	_check(bus != null, "bus spawned")
	_check(world.stops.size() == 4, "4 bus stops built")
	_check(world.terminal != null, "terminal built")
	_check(world.cars.size() == 6, "6 traffic cars spawned")
	_check(world.stops[0].waiting.size() == 4, "first stop has 4 waiting passengers")
	var buildings := 0
	for child in world.get_node("Blocks").get_children():
		if child is StaticBody3D:
			buildings += 1
	_check(buildings > 20, "buildings with collision generated (%d)" % buildings)
	# Skip the countdown and drive forward.
	game.state = STATE_DRIVING
	bus.engine_on = true
	var start_pos: Vector3 = bus.global_position
	game.hud.touch_controls.gas.press()
	await _frames(720)   # 3 simulated seconds
	game.hud.touch_controls.gas.release()
	var moved := start_pos.distance_to(bus.global_position)
	_check(moved > 8.0, "bus drives forward (%.1f m)" % moved)
	_check(bus.speed > 1.0, "bus has speed (%.1f m/s)" % bus.speed)
	_check(bus.is_on_floor(), "bus stays on the ground")
	# Brake to a stop.
	game.hud.touch_controls.brake_pedal.press()
	await _frames(240)
	game.hud.touch_controls.brake_pedal.release()
	await _frames(5)
	_check(absf(bus.speed) < 0.5, "brake stops the bus")
	# Teleport into the first stop zone and board passengers.
	var stop = world.stops[0]
	bus.stop_immediately()
	bus.global_transform = stop.global_transform
	await _frames(3)
	_check(stop.is_bus_in_zone(bus.global_position), "bus detected inside stop zone")
	_check(bus.toggle_doors(), "doors open when stopped")
	await _frames(10)
	_check(game.state == STATE_BOARDING, "boarding started")
	var waited := 0
	while game.state == STATE_BOARDING and waited < 2000:
		await _frames(10)
		waited += 10
	_check(game.state == STATE_WAIT_CLOSE, "boarding finished, waiting for doors")
	_check(game.onboard == 4, "4 passengers boarded (%d)" % game.onboard)
	bus.toggle_doors()
	await _frames(5)
	_check(game.current_stop == 1 and game.stops_served == 1, "stop 1 completed")
	_check(game.score > 0, "score increased (%d)" % game.score)
	# Missed stop detection.
	var stop2 = world.stops[1]
	bus.global_transform = stop2.global_transform.translated(-stop2.global_transform.basis.z * 40.0)
	await _frames(5)
	_check(game.current_stop == 2 and game.missed_stops == 1, "missed stop detected")
	# Collision handling.
	var before_damage: float = bus.damage
	game._on_bus_collided(5.0)
	_check(game.collisions == 1 and bus.damage > before_damage, "collision applies damage and penalty")
	# Terminal completion.
	game.current_stop = world.stops.size()
	game._update_stop_targets()
	bus.stop_immediately()
	bus.global_transform = world.terminal.global_transform
	await _frames(10)
	_check(game.state == STATE_FINISHED, "route finished at terminal")
	_check(gs.last_result.get("success", false) == true, "result recorded as success")
	_check(gs.get_route_stars("route_1") >= 1, "stars saved (%d)" % gs.get_route_stars("route_1"))
	await _frames(600)
	_check(game.results.visible, "results panel shown")
	game.queue_free()
	await _frames(2)


func _test_all_routes() -> void:
	print("-- all routes build")
	var gs := root.get_node("GameState")
	var packed: PackedScene = load("res://scenes/game.tscn")
	for route in RouteData.all():
		gs.selected_route_id = String(route.id)
		var game := packed.instantiate()
		root.add_child(game)
		await _frames(3)
		var ok: bool = game.world.stops.size() == route.stops.size() and game.world.cars.size() == int(route.traffic) and game.bus != null
		_check(ok, "%s builds (%d stops, %d cars, %s)" % [route.id, game.world.stops.size(), game.world.cars.size(), route.time_of_day])
		var spawn: Vector3 = game.bus.global_position
		_check(absf(spawn.x) < 200.0 and absf(spawn.z) < 200.0, "%s bus spawn inside city" % route.id)
		game.queue_free()
		await _frames(2)
	gs.selected_route_id = "route_1"
