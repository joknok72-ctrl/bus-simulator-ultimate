extends SceneTree
## Captures PNG screenshots of the menu pages and of gameplay for the docs.
## Needs a display (real or Xvfb) because it renders real frames:
##   xvfb-run -s "-screen 0 1280x720x24" Godot_v4.7.2-stable_linux.x86_64 --path . \
##       --rendering-driver opengl3 --resolution 1280x720 -s res://tools/screenshot.gd
## Output directory: $SHOT_DIR or res://docs/screenshots

const CAM_CHASE := 0
const CAM_DRIVER := 1
const CAM_TOP := 2
const STATE_DRIVING := 1
const STATE_WAIT_CLOSE := 3

var _dir := ""


func _init() -> void:
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = ProjectSettings.globalize_path("res://docs/screenshots")
	DirAccess.make_dir_recursive_absolute(_dir)
	# One physics tick per rendered frame keeps the simulated drives repeatable under
	# software rendering, where a frame can take much longer than 1/60 s.
	Engine.max_physics_steps_per_frame = 1
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames(2)
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var path := _dir.path_join(name + ".png")
	var err := img.save_png(path)
	print("  shot %s -> %s (%s)" % [name, path, error_string(err)])


func _run() -> void:
	print("== screenshots (Godot %s, %s) ==" % [Engine.get_version_info().string, RenderingServer.get_video_adapter_name()])
	var gs := root.get_node("GameState")
	# --- main menu pages (English then Arabic home) ---
	gs.set_setting("language", "en")
	var menu = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	await _frames(20)
	await _shot("01_menu_home_en")
	menu._show_page(menu.get_node("UI/Root/PageRoutes"), false)
	await _shot("02_menu_routes")
	menu._show_page(menu.get_node("UI/Root/PageGarage"), false)
	await _shot("03_menu_garage")
	menu._show_page(menu.get_node("UI/Root/PageSettings"), false)
	await _shot("04_menu_settings")
	menu._show_page(menu.get_node("UI/Root/PageHowTo"), false)
	await _shot("05_menu_howto")
	menu._show_page(menu.get_node("UI/Root/PageAbout"), false)
	await _shot("06_menu_about")
	gs.set_setting("language", "ar")
	menu._refresh_all()
	menu._show_page(menu.get_node("UI/Root/PageHome"), false)
	await _frames(5)
	await _shot("07_menu_home_ar")
	menu.queue_free()
	await _frames(3)
	# --- gameplay: countdown, driving (chase + driver seat), turning, stop with open doors ---
	gs.set_setting("language", "en")
	gs.set_setting("camera", CAM_CHASE)
	gs.selected_route_id = "route_1"
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await _frames(10)
	await _shot("08_game_countdown")
	game.state = STATE_DRIVING
	game.bus.engine_on = true
	game.hud.touch_controls.gas.press()
	await _frames(150)
	await _shot("09_game_driving_chase")
	# High view while still driving straight in the lane.
	game.camera_rig.set_mode(CAM_TOP)
	await _frames(40)
	await _shot("14_game_top_camera")
	game.camera_rig.set_mode(CAM_DRIVER)
	await _frames(40)
	await _shot("10_game_driver_camera")
	# Steer into a turn (towards the road centre, away from the curb): the cockpit wheel turns,
	# the body rolls and the view looks into the bend.
	game.hud.touch_controls.wheel.angle = deg_to_rad(-70.0)
	game.hud.touch_controls.wheel.held = true
	await _frames(40)
	await _shot("13_game_driver_turning")
	game.hud.touch_controls.wheel.held = false
	game.hud.touch_controls.gas.release()
	# Bus stop with open doors, seen from the driver's seat and from behind.
	var stop = game.world.stops[0]
	game.bus.stop_immediately()
	game.bus.global_transform = stop.global_transform
	game.bus.reset_physics_interpolation()
	game.camera_rig.set_mode(CAM_DRIVER)
	await _frames(5)
	game.bus.toggle_doors()
	await _frames(45)
	await _shot("15_game_driver_at_stop")
	game.camera_rig.set_mode(CAM_CHASE)
	await _frames(40)
	await _shot("11_game_bus_stop_boarding")
	# Let boarding finish, close the doors (stop 1 done), then show the turn-by-turn guidance
	# towards stop 2 from 22 m before the first corner (chase view).
	var waited := 0
	while game.state != STATE_WAIT_CLOSE and waited < 600:
		await _frames(5)
		waited += 5
	game.bus.toggle_doors()
	await create_timer(2.6).timeout   # let the "stop complete" message fade (real time)
	await _frames(2)
	var path: Array = game.route.path
	var corner_seg_frac: float = 1.0 - 22.0 / (CityLayout.BLOCK * 2.0)
	game.bus.stop_immediately()
	var pre_corner: Vector3 = CityLayout.lane_point(path[0], path[1], corner_seg_frac)
	game.bus.global_transform = Transform3D(Basis.IDENTITY, pre_corner).looking_at(pre_corner + CityLayout.seg_dir(path[0], path[1]), Vector3.UP)
	game.bus.reset_physics_interpolation()
	game.hud.touch_controls.gas.press()
	await _frames(45)
	await _shot("16_game_turn_guidance")
	game.hud.touch_controls.gas.release()
	# Damage smoke from the engine bay once the bus is badly hit.
	game.bus.apply_damage(70.0)
	game.hud.flash_damage()
	await _frames(70)
	await _shot("17_game_damage_smoke")
	game.queue_free()
	await _frames(3)
	# --- night route from the driver's seat ---
	gs.selected_route_id = "route_3"
	var night = load("res://scenes/game.tscn").instantiate()
	root.add_child(night)
	await _frames(10)
	night.state = STATE_DRIVING
	night.bus.engine_on = true
	night.camera_rig.set_mode(CAM_DRIVER)
	night.hud.touch_controls.gas.press()
	await _frames(120)
	await _shot("12_game_night_route")
	night.queue_free()
	await _frames(2)
	gs.set_setting("camera", CAM_CHASE)
	gs.selected_route_id = "route_1"
	print("== screenshots done ==")
	quit(0)
