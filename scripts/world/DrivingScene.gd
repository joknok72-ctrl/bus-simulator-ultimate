class_name DrivingScene
extends Node3D
## مشهد القيادة: يجمع المدينة + الباص + المحطات + المرور + HUD + الكاميرا،
## ويدير Core Loop: قُد ← اصطف ← افتح الأبواب ← ركاب ومال ← المحطة التالية ← نهاية الخط.

signal route_finished(result: Dictionary)
signal pause_requested()

var route_id := "line1"
var route: Dictionary
var bus: Bus
var city: CityBuilder
var traffic: Traffic
var hud: HUD
var controls: TouchControls
var stops: Array[BusStop] = []
var next_stop_idx := 0
var camera: Camera3D
var cam_mode := 0   # 0 خلفية، 1 قريبة، 2 داخلية
var sun: DirectionalLight3D
var world_env: WorldEnvironment
var is_night := false
var is_rain := false
var rain: GPUParticles3D

# حالة الجولة
var passengers := 0
var capacity := 14
var comfort := 100.0
var earned := 0
var fines := 0
var perfect_stops := 0
var good_stops := 0
var collisions := 0
var total_passengers := 0
var distance := 0.0
var _last_pos := Vector3.ZERO
var _start_time := 0.0
var _finished := false
var _speeding_timer := 0.0
var _at_stop: BusStop = null
var _stop_handled := false
var _cam_shake := 0.0
var _horn_on := false
var fare := 5
var speed_limit := 50
var _autopilot := false
var _cam_yaw_smooth := 0.0

func start(p_route_id: String) -> void:
	route_id = p_route_id
	route = RouteData.get_route(route_id)
	is_night = route["time"] == "night"
	is_rain = route["weather"] == "rain"
	speed_limit = int(route["speed_limit"])
	_autopilot = GameState.test_mode
	_build_environment()
	city = CityBuilder.new()
	add_child(city)
	city.build(is_night or route["time"] == "evening")
	_spawn_bus()
	_spawn_stops()
	traffic = Traffic.new()
	add_child(traffic)
	traffic.setup(bus, is_night, GameState.level >= 2 or route_id != "line1")
	traffic.red_light_violation.connect(_on_red_light)
	_build_camera()
	_build_ui()
	if is_rain:
		_build_rain()
	_start_time = Time.get_ticks_msec() / 1000.0
	_last_pos = bus.global_position
	AudioFX.engine_start()
	AudioFX.ambience_start()
	AudioFX.music_start()
	_set_next_stop(0)
	hud.show_big("انطلق! 🚌", HUD.COL_ACCENT, 1.6)
	bus.flipped_recovered.connect(func(): hud.show_big("تمت إعادة الباص", Color(0.85, 0.9, 1.0), 1.2))

# ------------------------------------------------------------------ البيئة
func _build_environment() -> void:
	world_env = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	if is_night:
		mat.sky_top_color = Color(0.02, 0.03, 0.08)
		mat.sky_horizon_color = Color(0.12, 0.1, 0.2)
		mat.ground_bottom_color = Color(0.02, 0.02, 0.04)
		mat.ground_horizon_color = Color(0.1, 0.08, 0.16)
		env.ambient_light_color = Color(0.25, 0.28, 0.4)
		env.ambient_light_energy = 0.6
	elif route["time"] == "evening":
		mat.sky_top_color = Color(0.25, 0.3, 0.5)
		mat.sky_horizon_color = Color(0.95, 0.6, 0.4)
		mat.ground_bottom_color = Color(0.2, 0.18, 0.2)
		mat.ground_horizon_color = Color(0.6, 0.45, 0.4)
		env.ambient_light_color = Color(0.7, 0.6, 0.6)
		env.ambient_light_energy = 0.8
	else:
		mat.sky_top_color = Color(0.3, 0.55, 0.9)
		mat.sky_horizon_color = Color(0.75, 0.85, 0.95)
		mat.ground_bottom_color = Color(0.4, 0.5, 0.35)
		mat.ground_horizon_color = Color(0.7, 0.8, 0.8)
		env.ambient_light_color = Color(0.7, 0.78, 0.9)
		env.ambient_light_energy = 0.45
	mat.sun_angle_max = 20.0
	sky.sky_material = mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(0.1, 0.1, 0.15) if is_night else Color(0.75, 0.8, 0.9)
	env.fog_density = 0.004 if is_rain else 0.0015
	env.fog_sky_affect = 0.2
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 0.15 if is_night else (0.7 if route["time"] == "evening" else 0.85)
	sun.light_color = Color(0.6, 0.65, 0.9) if is_night else (Color(1.0, 0.75, 0.55) if route["time"] == "evening" else Color(1.0, 0.97, 0.9))
	sun.shadow_enabled = bool(GameState.settings.get("shadows", true)) and not is_night and not GameState.test_mode
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)

func _build_rain() -> void:
	rain = GPUParticles3D.new()
	rain.amount = 600
	rain.lifetime = 1.2
	rain.visibility_aabb = AABB(Vector3(-30, -5, -30), Vector3(60, 40, 60))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(25, 1, 25)
	pm.direction = Vector3(0.1, -1, 0)
	pm.initial_velocity_min = 22.0
	pm.initial_velocity_max = 28.0
	pm.gravity = Vector3(0, -10, 0)
	rain.process_material = pm
	var m := BoxMesh.new()
	m.size = Vector3(0.03, 0.6, 0.03)
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.7, 0.8, 1.0, 0.5)
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material = mm
	rain.draw_pass_1 = m
	add_child(rain)

# ------------------------------------------------------------------ الباص والمحطات
func _spawn_bus() -> void:
	bus = Bus.new()
	add_child(bus)
	bus.setup(GameState.current_bus)
	capacity = int(bus.data["capacity"])
	fare = int(bus.data["fare"]) + GameState.upgrade_level("seats")
	# نقطة البداية: قبل المحطة الأولى بقليل في الحارة اليمنى
	var first_stop: Dictionary = route["stops"][0]
	var p := RouteData.point_on_segment(route, int(first_stop["seg"]), maxf(float(first_stop["t"]) - 0.3, 0.05))
	var dir: Vector3 = p["dir"]
	var right := Vector3(-dir.z, 0, dir.x)  # يمين اتجاه الحركة (forward × up)
	var lane_pos: Vector3 = p["pos"] + right * CityBuilder.LANE_OFFSET
	bus.reset_to(lane_pos, dir)
	bus.collided.connect(_on_collision)
	bus.comfort_event.connect(_on_comfort_event)
	bus.doors_changed.connect(_on_doors_changed)
	bus.set_headlights(is_night or route["time"] == "evening" or is_rain)

func _spawn_stops() -> void:
	var i := 0
	for s in route["stops"]:
		var p := RouteData.point_on_segment(route, int(s["seg"]), float(s["t"]))
		var dir: Vector3 = p["dir"]
		var right := Vector3(-dir.z, 0, dir.x)
		var stop := BusStop.new()
		add_child(stop)
		# المحطة على الرصيف الأيمن (ROAD_W/2 + قليلاً)
		stop.global_position = p["pos"] + right * (CityBuilder.ROAD_W * 0.5 + 1.2)
		stop.global_position.y = 0.0
		# المحور -Z المحلي للمحطة = اتجاه الحركة، و -X المحلي نحو الطريق
		stop.look_at(stop.global_position + dir, Vector3.UP)
		var waiting := randi_range(3, 7) if i < route["stops"].size() - 1 else 0
		stop.setup(str(s["name"]), i, waiting, is_night)
		stop.bus_arrived.connect(_on_bus_at_stop)
		stop.bus_left.connect(_on_bus_left_stop)
		stops.append(stop)
		i += 1

func _set_next_stop(idx: int) -> void:
	for s in stops:
		s.set_active(false)
	next_stop_idx = idx
	if idx < stops.size():
		stops[idx].set_active(true)
		hud.update_next_stop(stops[idx].stop_name, 0.0, idx + 1, stops.size()) if hud else null
		AudioFX.play("bell", -6.0)

# ------------------------------------------------------------------ الكاميرا
func _build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 70
	camera.near = 0.3
	camera.far = 400
	add_child(camera)
	cam_mode = int(GameState.settings.get("camera", 0))
	_update_camera(1.0, true)
	camera.current = true

func _update_camera(delta: float, snap := false) -> void:
	var L: float = bus.data["length"]
	var H: float = bus.data["height"]
	var fwd := -bus.global_transform.basis.z
	var flat_fwd := Vector3(fwd.x, 0, fwd.z).normalized()
	var target_pos: Vector3
	var look_at: Vector3
	match cam_mode:
		0:  # خلفية بعيدة
			target_pos = bus.global_position - flat_fwd * (L * 0.9 + 6.0) + Vector3(0, H + 4.5, 0)
			look_at = bus.global_position + flat_fwd * 4.0 + Vector3(0, 1.5, 0)
		1:  # خلفية قريبة/جانبية (للاصطفاف)
			target_pos = bus.global_position - flat_fwd * (L * 0.5 + 3.0) + Vector3(0, H + 7.0, 0)
			look_at = bus.global_position + flat_fwd * 2.0
		_:  # داخلية
			target_pos = bus.global_position + flat_fwd * (L * 0.5 - 1.2) + Vector3(0, H - 0.6, 0) + bus.global_transform.basis.x * -0.6
			look_at = target_pos + fwd * 10.0 + Vector3(0, -0.5, 0)
	if snap:
		camera.global_position = target_pos
	else:
		var k := 1.0 - exp(-delta * (6.0 if cam_mode != 2 else 30.0))
		camera.global_position = camera.global_position.lerp(target_pos, k)
	# اهتزاز الكاميرا عند الصدم/الفرملة القوية (Game Feel)
	if _cam_shake > 0.0:
		camera.global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _cam_shake * 0.3
		_cam_shake = move_toward(_cam_shake, 0.0, delta * 3.0)
	camera.look_at(look_at, Vector3.UP)

# ------------------------------------------------------------------ الواجهة
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HUD.new()
	layer.add_child(hud)
	controls = TouchControls.new()
	layer.add_child(controls)
	controls.doors_pressed.connect(_on_doors_pressed)
	controls.horn_pressed.connect(_on_horn)
	controls.camera_pressed.connect(_on_camera_toggle)
	controls.pause_pressed.connect(func(): pause_requested.emit())
	hud.update_passengers(passengers, capacity)
	hud.update_comfort(comfort)
	var pts: Array = []
	for cell in route["path"]:
		pts.append(RouteData.grid_to_world(cell[0], cell[1]))
	var spts: Array = []
	for s in stops:
		spts.append(s.global_position)
	hud.minimap_set(pts, spts)
	hud.update_next_stop(stops[0].stop_name, 0.0, 1, stops.size())

# ------------------------------------------------------------------ الحلقة
func _process(delta: float) -> void:
	if _finished:
		return
	if _autopilot:
		_autopilot_drive(delta)
	else:
		bus.steer_input = controls.steer
		bus.throttle_input = controls.throttle
		bus.brake_input = controls.brake
	_update_camera(delta)
	# المسافة
	var moved := bus.global_position.distance_to(_last_pos)
	if moved < 5.0:
		distance += moved
	_last_pos = bus.global_position
	# HUD
	hud.update_speed(bus.speed_kmh, speed_limit)
	if next_stop_idx < stops.size():
		var d := bus.global_position.distance_to(stops[next_stop_idx].global_position)
		hud.update_next_stop(stops[next_stop_idx].stop_name, d, next_stop_idx + 1, stops.size())
	hud.minimap_update(bus.global_position, bus.global_rotation.y, next_stop_idx)
	# تجاوز السرعة
	if bus.speed_kmh > speed_limit + 8:
		_speeding_timer += delta
		if _speeding_timer > 3.0:
			_speeding_timer = -4.0
			_fine(30, "تجاوز السرعة! -٣٠")
			_comfort_hit(6.0)
	else:
		_speeding_timer = max(_speeding_timer - delta, -4.0) if _speeding_timer < 0 else 0.0
	# تعافي الرضا التدريجي عند القيادة الهادئة
	if bus.speed_kmh > 5.0 and bus.speed_kmh < speed_limit and comfort < 100.0:
		comfort = min(100.0, comfort + delta * 1.5)
		hud.update_comfort(comfort)
	# رسالة عند الدخول لمنطقة المحطة
	if _at_stop and not _stop_handled and not bus.doors_open and bus.speed_kmh < 3.0 and _at_stop.index == next_stop_idx:
		pass

func _on_bus_at_stop(stop: BusStop) -> void:
	if stop.index != next_stop_idx:
		return
	_at_stop = stop
	_stop_handled = false
	hud.show_big("اصطفّ بجانب الرصيف وافتح الأبواب", Color(0.85, 0.9, 1.0), 2.0)

func _on_bus_left_stop(stop: BusStop) -> void:
	if _at_stop == stop:
		_at_stop = null

func _on_doors_pressed() -> void:
	if not bus.toggle_doors():
		hud.show_big("توقف أولاً لفتح الأبواب", HUD.COL_BAD, 1.0)
		AudioFX.play("fail", -8.0)

func _on_doors_changed(open: bool) -> void:
	controls.doors_open = open
	if open and _at_stop and not _stop_handled and _at_stop.index == next_stop_idx:
		_handle_stop(_at_stop)

## قلب Core Loop: تقييم الاصطفاف ← نزول ← صعود ← مال ← المحطة التالية
func _handle_stop(stop: BusStop) -> void:
	var ev := stop.evaluate_parking(bus)
	var score: int = ev["score"]
	if score == 0:
		hud.show_big("بعيد عن الرصيف! اقترب أكثر", HUD.COL_BAD, 1.5)
		AudioFX.play("fail", -6.0)
		return
	_stop_handled = true
	var bonus := 0
	match score:
		3:
			perfect_stops += 1
			bonus = 25
			hud.show_big("توقف مثالي! ✨ +٢٥", Color(0.4, 1.0, 0.6), 1.6)
			AudioFX.play("perfect")
			Haptics.medium()
			GameState.stats["perfect_stops"] = int(GameState.stats["perfect_stops"]) + 1
		2:
			good_stops += 1
			bonus = 10
			hud.show_big("توقف جيد 👍 +١٠", HUD.COL_ACCENT, 1.3)
			AudioFX.play("success", -6.0)
		_:
			hud.show_big("توقف مقبول", Color(0.85, 0.85, 0.9), 1.2)
	if bonus > 0:
		earned += bonus
		GameState.add_money(bonus)
	# نزول جزء من الركاب (كلهم في المحطة الأخيرة)
	var is_last := stop.index == stops.size() - 1
	var leaving := passengers if is_last else int(round(passengers * randf_range(0.3, 0.6)))
	passengers -= leaving
	# صعود الركاب المنتظرين (بحد السعة)
	var boarding: int = mini(stop.waiting.size(), capacity - passengers)
	var comfort_mult := 1.0 if comfort > 66 else (0.7 if comfort > 33 else 0.4)
	var per_fare := int(round(fare * comfort_mult))
	var screen := camera.unproject_position(bus.door_position() + Vector3(0, 2.5, 0))
	if leaving > 0:
		hud.float_text("↓ %d نزلوا" % leaving, screen + Vector2(-60, 40), Color(0.8, 0.85, 0.95))
	var self_ref := self
	stop.board_all(func():
		if boarding <= 0:
			return
		# يُستدعى لكل راكب منتظر؛ نحسب فقط من صعد فعلاً
		if self_ref.passengers < self_ref.capacity and boarding > 0:
			self_ref.passengers += 1
			self_ref.total_passengers += 1
			self_ref.earned += per_fare
			GameState.add_money(per_fare)
			GameState.stats["passengers"] = int(GameState.stats["passengers"]) + 1
			AudioFX.play("coin", -6.0, randf_range(0.95, 1.1), 0.08)
			self_ref.hud.float_text("+%d ج" % per_fare, screen)
			self_ref.hud.update_passengers(self_ref.passengers, self_ref.capacity)
	)
	hud.update_passengers(passengers, capacity)
	stop.mark_served()
	GameState.add_xp(15 + score * 10)
	# المحطة التالية بعد لحظة
	get_tree().create_timer(1.2 + 0.25 * boarding).timeout.connect(func():
		if is_last:
			_finish_route()
		else:
			_set_next_stop(next_stop_idx + 1)
			hud.show_big("أغلق الأبواب وانطلق ←", Color(0.85, 0.9, 1.0), 1.4)
	)

func _on_collision(impulse: float) -> void:
	collisions += 1
	GameState.stats["collisions"] = int(GameState.stats["collisions"]) + 1
	_cam_shake = clampf(impulse / 6.0, 0.3, 1.5)
	var fine_amt := int(clampf(impulse * 4.0, 10.0, 80.0))
	_fine(fine_amt, "حادث! 💥 -%d" % fine_amt)
	_comfort_hit(clampf(impulse * 3.0, 8.0, 30.0))

func _on_red_light() -> void:
	_fine(50, "إشارة حمراء! 🚦 -٥٠")
	_comfort_hit(5.0)

func _fine(amount: int, text: String) -> void:
	fines += amount
	GameState.stats["fines"] = int(GameState.stats["fines"]) + amount
	GameState.add_money(-amount)
	hud.show_big(text, HUD.COL_BAD, 1.5)
	AudioFX.play("fail", -4.0)
	Haptics.medium()

func _on_comfort_event(kind: String, severity: float) -> void:
	match kind:
		"brake":
			_comfort_hit(clampf(severity * 6.0, 2.0, 12.0))
			_cam_shake = max(_cam_shake, 0.25)
			if passengers > 0 and severity > 0.8:
				hud.float_text("فرملة مفاجئة!", Vector2(get_viewport().size.x * 0.5 - 60, 400), HUD.COL_BAD)
		"turn":
			_comfort_hit(clampf(severity * 4.0, 1.0, 8.0))
		"bump":
			pass

func _comfort_hit(amount: float) -> void:
	if passengers == 0:
		amount *= 0.3
	comfort = clampf(comfort - amount, 0.0, 100.0)
	hud.update_comfort(comfort)

func _on_horn(down: bool) -> void:
	if down:
		AudioFX.play("horn", -4.0, randf_range(0.97, 1.03), 0.5)

func _on_camera_toggle() -> void:
	cam_mode = (cam_mode + 1) % 3
	GameState.set_setting("camera", cam_mode)
	_update_camera(1.0, true)
	AudioFX.play("ui_click", -8.0)

func _finish_route() -> void:
	if _finished:
		return
	_finished = true
	bus.throttle_input = 0.0
	bus.brake_input = 1.0
	AudioFX.engine_stop()
	var elapsed := Time.get_ticks_msec() / 1000.0 - _start_time
	var bonus := int(route["bonus"])
	var comfort_bonus := int(comfort * 1.5)
	var perf_bonus := perfect_stops * 20
	var total := bonus + comfort_bonus + perf_bonus
	GameState.add_money(total)
	GameState.add_xp(60 + perfect_stops * 15)
	GameState.stats["distance_km"] = float(GameState.stats["distance_km"]) + distance / 1000.0
	var stars := 1
	if comfort > 50 and collisions <= 2:
		stars = 2
	if comfort > 75 and collisions == 0 and fines == 0 and perfect_stops >= stops.size() / 2:
		stars = 3
	var score := earned + total - fines + perfect_stops * 50
	GameState.record_route(route_id, score)
	var result := {
		"route": route["name"], "passengers": total_passengers, "earned": earned,
		"fines": fines, "bonus": bonus, "comfort_bonus": comfort_bonus, "perf_bonus": perf_bonus,
		"perfect": perfect_stops, "good": good_stops, "collisions": collisions,
		"time": elapsed, "distance": distance, "stars": stars, "score": score, "comfort": comfort,
	}
	AudioFX.play("success")
	hud.show_big("اكتمل الخط! 🎉", Color(0.4, 1.0, 0.6), 2.0)
	get_tree().create_timer(1.8).timeout.connect(func(): route_finished.emit(result))

func cleanup() -> void:
	AudioFX.engine_stop()
	AudioFX.ambience_stop()

# ------------------------------------------------------------------ قيادة آلية للاختبار (--test)
var _auto_wps: Array = []   # [{pos, stop_idx(-1 if none)}]
var _auto_i := 0
var _auto_wait := 0.0

func _build_autopilot_waypoints() -> void:
	_auto_wps.clear()
	var path: Array = route["path"]
	var stops_by_seg: Dictionary = {}
	var si := 0
	for st in route["stops"]:
		stops_by_seg[int(st["seg"])] = si
		si += 1
	for seg in range(path.size() - 1):
		var a := RouteData.grid_to_world(path[seg][0], path[seg][1])
		var b := RouteData.grid_to_world(path[seg + 1][0], path[seg + 1][1])
		var dir := (b - a).normalized()
		var right := Vector3(-dir.z, 0, dir.x)
		# نقطة بعد التقاطع + نقطة قبل التقاطع التالي (في الحارة اليمنى)
		_auto_wps.append({"pos": a + dir * 10.0 + right * CityBuilder.LANE_OFFSET, "stop": -1})
		if stops_by_seg.has(seg):
			var idx: int = stops_by_seg[seg]
			var stop := stops[idx]
			_auto_wps.append({"pos": stop.global_position + stop.global_transform.basis.x * -3.2, "stop": idx})
		_auto_wps.append({"pos": b - dir * 10.0 + right * CityBuilder.LANE_OFFSET, "stop": -1})
	# ابدأ من أقرب نقطة أمام الباص
	_auto_i = 0
	var best := 1e9
	for i in range(_auto_wps.size()):
		var d: float = bus.global_position.distance_to(_auto_wps[i]["pos"])
		if d < best:
			best = d
			_auto_i = i

func _autopilot_drive(delta: float) -> void:
	if _auto_wps.is_empty():
		_build_autopilot_waypoints()
	if _auto_i >= _auto_wps.size():
		bus.throttle_input = 0.0
		bus.brake_input = 1.0
		return
	var wp: Dictionary = _auto_wps[_auto_i]
	var target: Vector3 = wp["pos"]
	var is_stop: bool = int(wp["stop"]) >= 0 and int(wp["stop"]) == next_stop_idx
	var to := target - bus.global_position
	to.y = 0
	var dist := to.length()
	var fwd := -bus.global_transform.basis.z
	var right := bus.global_transform.basis.x
	var ahead := to.normalized().dot(fwd)
	var steer := clampf(to.normalized().dot(right) * 2.5, -1.0, 1.0)
	if ahead < 0.0:
		steer = 1.0 if steer >= 0.0 else -1.0
	bus.steer_input = steer
	# في وضع الانتظار عند المحطة
	if _auto_wait > 0.0:
		_auto_wait -= delta
		bus.throttle_input = 0.0
		bus.brake_input = 1.0
		if _auto_wait <= 0.0 and bus.doors_open:
			bus.toggle_doors()
			_auto_i += 1
		return
	var target_speed := 30.0
	if absf(steer) > 0.5:
		target_speed = 14.0
	if is_stop:
		target_speed = clampf(dist * 2.5, 4.0, 22.0)
	if dist < (2.5 if is_stop else 6.0):
		if is_stop:
			bus.throttle_input = 0.0
			bus.brake_input = 1.0
			if bus.speed_kmh < 1.5:
				if not bus.doors_open:
					bus.toggle_doors()
				_auto_wait = 3.0
			return
		_auto_i += 1
		return
	if bus.speed_kmh < target_speed:
		bus.throttle_input = 1.0
		bus.brake_input = 0.0
	elif bus.speed_kmh > target_speed + 6.0:
		bus.throttle_input = 0.0
		bus.brake_input = 0.6
	else:
		bus.throttle_input = 0.0
		bus.brake_input = 0.0
