extends SceneTree
## Prints renderer statistics (draw calls, objects, primitives, node count) for the
## chase and driver cameras of route_1 and the main menu. Needs a display (Xvfb is fine):
##   xvfb-run -s "-screen 0 1280x720x24" Godot_v4.7.2-stable_linux.x86_64 --path . \
##       --rendering-driver opengl3 --resolution 1280x720 -s res://tools/perf_probe.gd

const CAM_CHASE := 0
const CAM_DRIVER := 1
const STATE_DRIVING := 1


func _init() -> void:
	Engine.max_physics_steps_per_frame = 1
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _stats(label: String, scene: Node) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	var rs := RenderingServer
	var dc := rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var ob := rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	var pr := rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var nodes := scene.get_tree().get_node_count() if scene.is_inside_tree() else -1
	var meshes := scene.find_children("*", "MeshInstance3D", true, false).size()
	print("STATS %-24s draw_calls=%d objects=%d primitives=%d nodes=%d mesh_instances=%d" % [label, dc, ob, pr, nodes, meshes])


func _run() -> void:
	print("== perf probe (Godot %s, %s) ==" % [Engine.get_version_info().string, RenderingServer.get_video_adapter_name()])
	var gs := root.get_node("GameState")
	gs.set_setting("language", "en")
	var menu = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	await _frames(10)
	await _stats("main_menu", menu)
	menu.queue_free()
	await _frames(3)
	for route_id in ["route_1", "route_4"]:
		gs.set_setting("camera", CAM_CHASE)
		gs.selected_route_id = route_id
		var game = load("res://scenes/game.tscn").instantiate()
		root.add_child(game)
		await _frames(10)
		game.state = STATE_DRIVING
		game.bus.engine_on = true
		game.hud.touch_controls.gas.press()
		await _frames(60)
		await _stats(route_id + " chase", game)
		game.camera_rig.set_mode(CAM_DRIVER)
		await _frames(40)
		await _stats(route_id + " driver", game)
		game.queue_free()
		await _frames(3)
	gs.set_setting("camera", CAM_CHASE)
	gs.selected_route_id = "route_1"
	print("== perf probe done ==")
	quit(0)
