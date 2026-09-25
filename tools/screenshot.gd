extends SceneTree
## Captures PNG screenshots of the menu pages and of gameplay for the docs.
## Needs a display (real or Xvfb) because it renders real frames:
##   xvfb-run -s "-screen 0 1280x720x24" Godot_v4.7.2-stable_linux.x86_64 --path . \
##       --rendering-driver opengl3 --resolution 1280x720 -s res://tools/screenshot.gd
## Output directory: $SHOT_DIR or res://docs/screenshots

var _dir := ""


func _init() -> void:
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = ProjectSettings.globalize_path("res://docs/screenshots")
	DirAccess.make_dir_recursive_absolute(_dir)
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
	# --- gameplay: countdown, driving, stop with open doors, night route ---
	gs.set_setting("language", "en")
	gs.selected_route_id = "route_1"
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await _frames(10)
	await _shot("08_game_countdown")
	game.state = 1  # DRIVING
	game.bus.engine_on = true
	game.hud.touch_controls.gas.press()
	await _frames(150)
	await _shot("09_game_driving_chase")
	game.hud.touch_controls.gas.release()
	game.camera_rig.mode = 1  # DRIVER
	game.camera_rig._initialized = false
	await _frames(20)
	await _shot("10_game_driver_camera")
	game.camera_rig.mode = 0  # CHASE
	game.camera_rig._initialized = false
	var stop = game.world.stops[0]
	game.bus.stop_immediately()
	game.bus.global_transform = stop.global_transform
	await _frames(5)
	game.bus.toggle_doors()
	await _frames(40)
	await _shot("11_game_bus_stop_boarding")
	game.queue_free()
	await _frames(3)
	gs.selected_route_id = "route_3"
	var night = load("res://scenes/game.tscn").instantiate()
	root.add_child(night)
	await _frames(10)
	night.state = 1
	night.bus.engine_on = true
	night.hud.touch_controls.gas.press()
	await _frames(120)
	await _shot("12_game_night_route")
	night.queue_free()
	await _frames(2)
	print("== screenshots done ==")
	quit(0)
