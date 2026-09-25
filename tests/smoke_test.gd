extends SceneTree
## Headless smoke test for City Bus Driver.
## Run from the project folder with the exact engine version:
##   Godot_v4.7.2-stable_linux.x86_64 --headless --path . -s res://tests/smoke_test.gd
## Exit code 0 = all checks passed.

const STATE_DRIVING := 1
const STATE_BOARDING := 2
const STATE_WAIT_CLOSE := 3
const STATE_FINISHED := 4
const CAM_CHASE := 0
const CAM_DRIVER := 1
const CAM_TOP := 2

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
	await _test_guidance()
	await _test_camera()
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
	_check(menu.get_node("UI/Root/PageSettings/Panel/Grid").get_child_count() == 18, "settings rows built (incl. steering sensitivity)")
	_check(menu.get_node("UI/Root/PageHowTo/Panel/Lines").get_child_count() == 7, "7 how-to lines built")
	var menu_meshes: int = menu.get_node("Turntable/Bus").find_children("*", "MeshInstance3D", true, false).size()
	_check(menu_meshes < 20, "bus geometry is merged (%d mesh instances, was ~120)" % menu_meshes)
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
	var block_meshes := 0
	for child in world.get_node("Blocks").get_children():
		if child is StaticBody3D:
			buildings += 1
		elif child is MeshInstance3D:
			block_meshes += 1
	_check(buildings > 20, "buildings with collision generated (%d)" % buildings)
	_check(block_meshes == 1 and world.get_node("Blocks/CityMesh").mesh.get_surface_count() >= 8, "city blocks baked into one mesh (%d surfaces)" % world.get_node("Blocks/CityMesh").mesh.get_surface_count())
	var total_meshes: int = game.find_children("*", "MeshInstance3D", true, false).size()
	_check(total_meshes < 90, "scene uses few mesh instances (%d, was ~590)" % total_meshes)
	_check(world.get_node_or_null("Roads") != null and world.get_node("Roads").mesh.get_surface_count() == 2, "roads merged into one mesh")
	# Turn-by-turn guidance at the spawn: the first stop is on the same road segment.
	_check(game.guidance.turn == RouteGuide.Turn.STOP and game.guidance.distance > 20.0, "guidance at spawn: bus stop ahead (%.0f m)" % game.guidance.distance)
	_check(game.hud.turn_arrow != null and game.hud.distance_label.text.contains("m"), "HUD guidance line shows the distance (\"%s\")" % game.hud.distance_label.text)
	# Traffic yields to the whole bus, not just its centre point: a car aimed at the rear third.
	var car = world.cars[0]
	var saved_car_xf: Transform3D = car.global_transform
	var rear_point: Vector3 = bus.global_position + bus.global_transform.basis.z * 4.5
	var car_pos: Vector3 = rear_point + bus.global_transform.basis.x * 8.0
	car.global_transform = Transform3D(Basis.IDENTITY, car_pos).looking_at(rear_point, Vector3.UP)
	car.speed = 5.0
	_check(car._obstacle_ahead(), "traffic car yields to the side of the bus")
	car.global_transform = saved_car_xf
	_check(bus.smoke != null and not bus.smoke.emitting, "no damage smoke on a fresh bus")
	# Steering sensitivity changes the touch wheel lock angle and is persisted.
	var wheel = game.hud.touch_controls.wheel
	var normal_lock: float = wheel.max_angle
	gs.set_setting("steer_sensitivity", 2)
	_check(wheel.max_angle < normal_lock - 0.3, "high steering sensitivity needs less wheel travel (%.0f deg)" % rad_to_deg(wheel.max_angle))
	gs.set_setting("steer_sensitivity", 1)
	_check(absf(wheel.max_angle - normal_lock) < 0.001, "normal steering sensitivity restored")
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
	_check(game.perfect_stops == 1 and game.score == 4 * 50 + 100 + 50, "perfect stop bonus awarded (%d)" % game.score)
	_check(game.guidance.turn == RouteGuide.Turn.RIGHT or game.guidance.turn == RouteGuide.Turn.LEFT, "guidance now points to the next corner")
	# Missed stop detection.
	var stop2 = world.stops[1]
	bus.global_transform = stop2.global_transform.translated(-stop2.global_transform.basis.z * 40.0)
	await _frames(5)
	_check(game.current_stop == 2 and game.missed_stops == 1, "missed stop detected")
	# Collision handling.
	var before_damage: float = bus.damage
	game._on_bus_collided(5.0)
	_check(game.collisions == 1 and bus.damage > before_damage, "collision applies damage and penalty")
	bus.apply_damage(60.0)
	_check(bus.smoke.emitting, "heavy damage starts the engine smoke")
	# Terminal completion.
	game.current_stop = world.stops.size()
	game._update_stop_targets()
	bus.stop_immediately()
	bus.global_transform = world.terminal.global_transform
	await _frames(10)
	_check(game.state == STATE_FINISHED, "route finished at terminal")
	_check(gs.last_result.get("success", false) == true, "result recorded as success")
	_check(gs.get_route_stars("route_1") >= 1, "stars saved (%d)" % gs.get_route_stars("route_1"))
	_check(int(gs.last_result.get("perfect_stops", -1)) == 1, "perfect stops recorded in the result")
	await _frames(600)
	_check(game.results.visible, "results panel shown")
	game.queue_free()
	await _frames(2)


func _test_guidance() -> void:
	print("-- route guidance")
	var guide := RouteGuide.new()
	var route := RouteData.get_route("route_1")
	guide.setup(CityLayout.route_polyline(route.path))
	_check(guide.points.size() == 5 and guide.total_length() > 400.0, "route_1 polyline (%d points, %.0f m)" % [guide.points.size(), guide.total_length()])
	# Spawn -> first stop: same segment, straight to the stop.
	var a: Vector2i = route.path[0]
	var b: Vector2i = route.path[1]
	var spawn := CityLayout.lane_point(a, b, 0.1)
	var stop1 := CityLayout.lane_point(a, b, 0.4)
	var g := guide.guidance(spawn, stop1, false)
	_check(g.turn == RouteGuide.Turn.STOP and absf(g.distance - spawn.distance_to(stop1)) < 1.0, "same-segment target: stop ahead (%.0f m)" % g.distance)
	# 10 m before the first corner, heading for stop 2 on the next segment: a right turn.
	var near_corner := CityLayout.lane_point(a, b, 1.0 - 10.0 / CityLayout.BLOCK / 2.0)
	var stop2 := CityLayout.lane_point(route.path[1], route.path[2], 0.5)
	g = guide.guidance(near_corner, stop2, false)
	_check(g.turn == RouteGuide.Turn.RIGHT, "next corner is a right turn")
	# The lane polyline turns OUTER_LANE metres before the intersection centre.
	_check(absf(g.distance - (10.0 - CityLayout.OUTER_LANE)) < 0.3, "distance to the corner is measured along the lane (%.1f m)" % g.distance)
	_check(g.guide_point.distance_to(Vector3(guide.points[1].x, stop2.y, guide.points[1].z)) < 0.01, "arrow target is the corner, not the stop behind the buildings")
	# Leaving the route (40 m sideways, into the next street) and coming back.
	var sideways := spawn + CityLayout.right_of(CityLayout.seg_dir(a, b)) * -40.0
	g = guide.guidance(sideways, stop1, false)
	_check(g.turn == RouteGuide.Turn.OFF_ROUTE and guide.off_route, "off-route detected 40 m from the lane")
	g = guide.guidance(spawn + Vector3(3.0, 0, 0), stop1, false)
	_check(not guide.off_route and g.turn == RouteGuide.Turn.STOP, "back on the route")
	# Terminal guidance on the last segment.
	var last_a: Vector2i = route.path[route.path.size() - 2]
	var last_b: Vector2i = route.path[route.path.size() - 1]
	g = guide.guidance(CityLayout.lane_point(last_a, last_b, 0.3), CityLayout.lane_point(last_a, last_b, 0.9), true)
	_check(g.turn == RouteGuide.Turn.TERMINAL, "terminal guidance on the last segment")
	# MeshMerger: one surface per material, geometry preserved.
	var merger := MeshMerger.new()
	var m1 := MeshFactory.mat(Color.RED)
	var m2 := MeshFactory.mat(Color.BLUE)
	merger.add_box(Vector3.ONE, Vector3.ZERO, m1)
	merger.add_box(Vector3.ONE, Vector3(3, 0, 0), m1)
	merger.add_cylinder(0.5, 1.0, Vector3(0, 2, 0), m2, Vector3(0, 0, PI * 0.5), 8)
	var mesh := merger.build()
	_check(mesh.get_surface_count() == 2 and merger.vertex_count() > 48, "MeshMerger groups by material (%d surfaces, %d vertices)" % [mesh.get_surface_count(), merger.vertex_count()])
	var aabb := mesh.get_aabb()
	_check(aabb.position.x < -0.49 and aabb.end.x > 3.49 and aabb.end.y > 2.49, "merged geometry keeps its placement (%s)" % aabb)
	await _frames(1)


func _test_camera() -> void:
	print("-- camera rig")
	var gs := root.get_node("GameState")
	gs.selected_route_id = "route_1"
	gs.set_setting("camera", CAM_CHASE)
	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await _frames(5)
	var bus = game.bus
	var rig = game.camera_rig
	_check(rig.mode == CAM_CHASE, "camera starts in the mode from settings (chase)")
	_check(rig.global_position.distance_to(bus.global_position) > 8.0, "chase camera sits behind the bus")
	_check(bus.hand_wheel != null and bus.driver_eye_transform().origin.y > 2.0, "cockpit built (hand wheel + driver eye point)")
	# Driver seat: the camera must sit exactly at the driver's eye and look forward, slightly down.
	rig.set_mode(CAM_DRIVER)
	_check(int(gs.settings.camera) == CAM_DRIVER, "camera mode persisted to settings")
	var blend_ticks := int(0.7 * Engine.physics_ticks_per_second)   # longer than the 0.45 s blend
	await _frames(blend_ticks)
	var eye: Vector3 = bus.driver_eye_transform().origin
	var cam_err: float = rig.global_position.distance_to(eye)
	_check(cam_err < 0.01, "driver camera at the driver's eye (error %.3f m)" % cam_err)
	var local_eye: Vector3 = bus.to_local(rig.global_position)
	_check(local_eye.x < -0.5 and local_eye.z < -3.0 and local_eye.y > 2.3 and local_eye.y < 2.9, "driver eye is in the front-left seat (%s)" % local_eye)
	var fwd: Vector3 = -rig.global_transform.basis.z
	var bus_fwd: Vector3 = -bus.global_transform.basis.z
	_check(fwd.dot(bus_fwd) > 0.98 and fwd.y < 0.0 and fwd.y > -0.2, "driver camera looks forward and slightly down")
	# Nothing of the bus interior may sit between the eye and the windshield.
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(eye, eye + bus_fwd * 30.0, 1)
	_check(space.intersect_ray(ray).is_empty(), "clear line of sight ahead of the driver camera")
	# The cockpit wheel follows the steering input and the camera looks into the turn.
	game.state = STATE_DRIVING
	bus.engine_on = true
	game.hud.touch_controls.gas.press()
	game.hud.touch_controls.wheel.angle = deg_to_rad(90.0)
	game.hud.touch_controls.wheel.held = true
	await _frames(240)
	var wheel_spin: float = bus.hand_wheel.basis.get_euler().y
	_check(absf(wheel_spin) > 0.5, "cockpit steering wheel turns with the input (%.2f rad)" % wheel_spin)
	var yaw_offset: float = (-rig.global_transform.basis.z).signed_angle_to(-bus.global_transform.basis.z, Vector3.UP)
	_check(absf(yaw_offset) > deg_to_rad(2.0) and absf(yaw_offset) <= deg_to_rad(16.0), "driver camera looks into the turn (%.1f deg)" % rad_to_deg(yaw_offset))
	game.hud.touch_controls.wheel.held = false
	game.hud.touch_controls.gas.release()
	# Switching back blends smoothly (no teleport) and ends behind the bus again.
	var before: Vector3 = rig.global_position
	rig.set_mode(CAM_CHASE)
	await _frames(2)
	_check(rig.global_position.distance_to(before) < 3.0, "camera switch blends instead of jumping")
	await _frames(blend_ticks)
	_check(rig.global_position.distance_to(bus.global_position) > 8.0, "back in chase view behind the bus")
	# The chase camera never sits inside a building: park the bus right in front of a tall one,
	# facing away from it, so the follow position behind the bus would be inside the wall.
	var building: StaticBody3D = null
	for child in game.world.get_node("Blocks").get_children():
		if child is StaticBody3D:
			var shape: BoxShape3D = child.get_child(0).shape
			if shape.size.y > 8.0 and shape.size.z > 12.0:
				building = child
				break
	if building != null:
		var shape: BoxShape3D = building.get_child(0).shape
		bus.stop_immediately()
		var front := building.global_position + Vector3(0, -building.global_position.y, -shape.size.z * 0.5 - 7.0)
		bus.global_transform = Transform3D(Basis.IDENTITY, front).looking_at(front + Vector3(0, 0, -30.0), Vector3.UP)
		bus.reset_physics_interpolation()
		rig.set_mode(CAM_TOP)
		rig.set_mode(CAM_CHASE)
		await _frames(blend_ticks)
		var cam_ray := PhysicsRayQueryParameters3D.create(bus.global_position + Vector3(0, 2.5, 0), rig.global_position, 1)
		_check(space.intersect_ray(cam_ray).is_empty(), "chase camera keeps a clear view of the bus near buildings")
		_check(rig.global_position.distance_to(bus.global_position) < 12.0, "chase camera moved in front of the wall (%.1f m from bus)" % rig.global_position.distance_to(bus.global_position))
	gs.set_setting("camera", CAM_CHASE)
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
