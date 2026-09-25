extends Node3D
## Main menu with pages: home, route selection, garage, settings and how-to-play.
## A slowly rotating bus on a turntable is rendered behind the UI.

@onready var turntable: Node3D = $Turntable
@onready var bus: Bus = $Turntable/Bus
@onready var root: Control = $UI/Root
@onready var lang_button: Button = $UI/Root/TopBar/LangButton
@onready var coins_label: Label = $UI/Root/TopBar/StatsPanel/Stats/CoinsLabel
@onready var stars_label: Label = $UI/Root/TopBar/StatsPanel/Stats/StarsLabel
@onready var page_home: Control = $UI/Root/PageHome
@onready var page_routes: Control = $UI/Root/PageRoutes
@onready var page_garage: Control = $UI/Root/PageGarage
@onready var page_settings: Control = $UI/Root/PageSettings
@onready var page_howto: Control = $UI/Root/PageHowTo
@onready var page_about: Control = $UI/Root/PageAbout
@onready var about_lines: VBoxContainer = $UI/Root/PageAbout/Panel/Scroll/Lines
@onready var route_cards: HBoxContainer = $UI/Root/PageRoutes/Cards
@onready var garage_cards: HBoxContainer = $UI/Root/PageGarage/Cards
@onready var settings_grid: GridContainer = $UI/Root/PageSettings/Panel/Grid
@onready var howto_lines: VBoxContainer = $UI/Root/PageHowTo/Panel/Lines

## The turntable, ground and platform sit low on the home page so the bus stays clear of the
## title; on the card pages (routes, garage) the whole stage is lifted so the bus shows
## above the card row.
const STAGE_LIFT_PAGES := 1.1

var _pages: Array[Control] = []
var _current_page: Control
var _stage_nodes: Array[Node3D] = []
var _stage_base_y: Array[float] = []
var _stage_tween: Tween


func _ready() -> void:
	_pages = [page_home, page_routes, page_garage, page_settings, page_howto, page_about]
	_stage_nodes = [turntable, $Ground, $Platform]
	for n in _stage_nodes:
		_stage_base_y.append(n.position.y)
	bus.set_physics_process(false)
	bus.configure(GameState.get_bus_color(), false)
	bus.position = Vector3(0, 0, 0)
	# Footer: real project version and engine version instead of a hard-coded string.
	var engine_info := Engine.get_version_info()
	$UI/Root/PageHome/Version.text = "v%s - Godot %s.%s.%s" % [
		str(ProjectSettings.get_setting("application/config/version", "")),
		engine_info.get("major", 0), engine_info.get("minor", 0), engine_info.get("patch", 0)]
	# Home buttons
	$UI/Root/PageHome/Buttons/Play.pressed.connect(func() -> void: _show_page(page_routes))
	$UI/Root/PageHome/Buttons/Garage.pressed.connect(func() -> void: _show_page(page_garage))
	$UI/Root/PageHome/Buttons/Settings.pressed.connect(func() -> void: _show_page(page_settings))
	$UI/Root/PageHome/Buttons/HowTo.pressed.connect(func() -> void: _show_page(page_howto))
	$UI/Root/PageHome/Buttons/Quit.pressed.connect(func() -> void: get_tree().quit())
	$UI/Root/PageHome/About.pressed.connect(func() -> void: _show_page(page_about))
	for page in [page_routes, page_garage, page_settings, page_howto, page_about]:
		page.get_node("Back").pressed.connect(func() -> void: _show_page(page_home))
	lang_button.pressed.connect(func() -> void:
		GameState.toggle_language()
		AudioSynth.play("click", -6.0)
		_refresh_all())
	GameState.coins_changed.connect(func(_c: int) -> void: _refresh_stats())
	_show_page(page_home, false)
	_refresh_all()


func _physics_process(delta: float) -> void:
	# Rotated on the physics tick so physics interpolation keeps it smooth.
	turntable.rotate_y(delta * 0.35)


func _notification(what: int) -> void:
	# Android back button: return to the home page, or quit from the home page.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_inside_tree():
		if _current_page != null and _current_page != page_home:
			_show_page(page_home)
		else:
			get_tree().quit()


func _show_page(page: Control, click: bool = true) -> void:
	if click:
		AudioSynth.play("click", -6.0)
	for p in _pages:
		p.visible = p == page
	_current_page = page
	_set_stage_lift(0.0 if page == page_home else STAGE_LIFT_PAGES, click)
	if page == page_routes:
		_build_route_cards()
	elif page == page_garage:
		_build_garage_cards()
	elif page == page_settings:
		_build_settings()
	elif page == page_howto:
		_build_howto()
	elif page == page_about:
		_build_about()
	_refresh_stats()


func _set_stage_lift(lift: float, animate: bool) -> void:
	if _stage_tween and _stage_tween.is_valid():
		_stage_tween.kill()
	if animate:
		_stage_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	for i in _stage_nodes.size():
		var target_y := _stage_base_y[i] + lift
		if animate:
			_stage_tween.tween_property(_stage_nodes[i], "position:y", target_y, 0.35)
		else:
			_stage_nodes[i].position.y = target_y
			_stage_nodes[i].reset_physics_interpolation()


func _refresh_all() -> void:
	_refresh_stats()
	if _current_page != null:
		_show_page(_current_page, false)


func _refresh_stats() -> void:
	coins_label.text = "%s: %d" % [tr("MENU_COINS"), GameState.get_coins()]
	stars_label.text = "%s: %d / %d" % [tr("MENU_STARS"), GameState.total_stars(), RouteData.all().size() * 3]


# ---------------------------------------------------------------- routes
func _build_route_cards() -> void:
	for child in route_cards.get_children():
		child.queue_free()
	var time_names := {"day": "TIME_DAY", "sunset": "TIME_SUNSET", "night": "TIME_NIGHT"}
	var time_colors := {"day": Color(0.45, 0.75, 1.0), "sunset": Color(1.0, 0.65, 0.35), "night": Color(0.55, 0.5, 0.95)}
	for route in RouteData.all():
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(260, 400)
		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 6)
		card.add_child(vbox)
		var name_label := Label.new()
		name_label.text = tr(String(route.name))
		name_label.theme_type_variation = &"HeaderLabel"
		name_label.add_theme_font_size_override("font_size", 28)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(name_label)
		var tod := Label.new()
		tod.text = tr(String(time_names[route.time_of_day]))
		tod.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tod.add_theme_color_override("font_color", time_colors[route.time_of_day])
		vbox.add_child(tod)
		var preview := _make_route_preview(route)
		vbox.add_child(preview)
		var info := Label.new()
		info.text = "%s  |  %s" % [tr("ROUTE_STOPS") % route.stops.size(), tr("ROUTE_TIME") % int(ceil(float(route.time_limit) / 60.0))]
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.theme_type_variation = &"SmallLabel"
		vbox.add_child(info)
		var stars := StarsDisplay.new()
		stars.star_size = 16.0
		stars.custom_minimum_size = Vector2(0, 40)
		vbox.add_child(stars)
		stars.set_stars(GameState.get_route_stars(String(route.id)))
		var best := Label.new()
		best.text = tr("ROUTE_BEST") % GameState.get_route_best(String(route.id))
		best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		best.theme_type_variation = &"SmallLabel"
		vbox.add_child(best)
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.add_child(spacer)
		if GameState.is_route_unlocked(route):
			var start := Button.new()
			start.text = tr("START")
			start.theme_type_variation = &"SuccessButton"
			var route_id := String(route.id)
			start.pressed.connect(func() -> void: _start_route(route_id))
			vbox.add_child(start)
		else:
			var locked := Label.new()
			locked.text = tr("ROUTE_LOCKED") % int(route.stars_required)
			locked.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			locked.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			locked.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5))
			vbox.add_child(locked)
			card.modulate = Color(0.75, 0.75, 0.75)
		route_cards.add_child(card)


func _make_route_preview(route: Dictionary) -> Control:
	var preview := Minimap.new()
	preview.custom_minimum_size = Vector2(0, 150)
	preview.route_points = CityLayout.route_polyline(route.path)
	preview.set_process(false)
	return preview


func _start_route(route_id: String) -> void:
	AudioSynth.play("click", -6.0)
	GameState.selected_route_id = route_id
	GameState.change_scene("res://scenes/game.tscn")


# ---------------------------------------------------------------- garage
func _build_garage_cards() -> void:
	for child in garage_cards.get_children():
		child.queue_free()
	for entry in GameState.BUS_COLORS:
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(180, 210)
		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 8)
		card.add_child(vbox)
		var swatch := ColorRect.new()
		swatch.color = entry.color
		swatch.custom_minimum_size = Vector2(0, 60)
		vbox.add_child(swatch)
		var name_label := Label.new()
		name_label.text = tr(String(entry.name))
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(name_label)
		var button := Button.new()
		var color_id := String(entry.id)
		var unlocked := GameState.is_color_unlocked(color_id)
		var selected: bool = String(GameState.progress.bus_color) == color_id
		if selected:
			button.text = tr("GARAGE_SELECTED")
			button.disabled = true
		elif unlocked:
			button.text = tr("GARAGE_SELECT")
		else:
			button.text = tr("GARAGE_BUY") % int(entry.price)
			button.theme_type_variation = &"SecondaryButton"
		button.pressed.connect(func() -> void: _on_color_pressed(color_id))
		vbox.add_child(button)
		garage_cards.add_child(card)


func _on_color_pressed(color_id: String) -> void:
	if not GameState.is_color_unlocked(color_id):
		if not GameState.try_buy_color(color_id):
			AudioSynth.play("fail", -8.0)
			_flash_status(tr("GARAGE_NOT_ENOUGH"))
			return
		AudioSynth.play("coin", -4.0)
	else:
		AudioSynth.play("click", -6.0)
	GameState.select_color(color_id)
	bus.configure(GameState.get_bus_color(), false)
	_build_garage_cards()
	_refresh_stats()


func _flash_status(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"HeaderLabel"
	label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label.position = Vector2(root.size.x * 0.5 - 300.0, 140.0)
	label.size = Vector2(600, 60)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
	root.add_child(label)
	var tween := create_tween()
	tween.tween_interval(1.4)
	tween.tween_property(label, "modulate:a", 0.0, 0.4)
	tween.tween_callback(label.queue_free)


# ---------------------------------------------------------------- settings
func _build_settings() -> void:
	for child in settings_grid.get_children():
		child.queue_free()
	var control_names := ["CTRL_WHEEL", "CTRL_BUTTONS", "CTRL_TILT"]
	var camera_names := ["CAM_CHASE", "CAM_DRIVER", "CAM_TOP"]
	_add_setting(tr("SET_CONTROLS"), tr(control_names[int(GameState.settings.control_mode)]), func() -> void:
		GameState.set_setting("control_mode", (int(GameState.settings.control_mode) + 1) % 3))
	_add_setting(tr("SET_CAMERA"), tr(camera_names[int(GameState.settings.camera)]), func() -> void:
		GameState.set_setting("camera", (int(GameState.settings.camera) + 1) % 3))
	_add_setting(tr("SET_SOUND"), tr("ON") if GameState.settings.sound else tr("OFF"), func() -> void:
		GameState.set_setting("sound", not GameState.settings.sound))
	_add_setting(tr("SET_VIBRATION"), tr("ON") if GameState.settings.vibration else tr("OFF"), func() -> void:
		GameState.set_setting("vibration", not GameState.settings.vibration))
	_add_setting(tr("SET_QUALITY"), tr("QUALITY_HIGH") if int(GameState.settings.quality) >= 1 else tr("QUALITY_LOW"), func() -> void:
		GameState.set_setting("quality", 0 if int(GameState.settings.quality) >= 1 else 1))
	var sens_names := ["SENS_LOW", "SENS_NORMAL", "SENS_HIGH"]
	_add_setting(tr("SET_STEER_SENS"), tr(sens_names[GameState.steer_sensitivity()]), func() -> void:
		GameState.set_setting("steer_sensitivity", (GameState.steer_sensitivity() + 1) % 3))
	_add_setting(tr("SET_INVERT_TILT"), tr("ON") if GameState.settings.invert_tilt else tr("OFF"), func() -> void:
		GameState.set_setting("invert_tilt", not GameState.settings.invert_tilt))
	_add_setting(tr("MENU_LANGUAGE"), "العربية" if GameState.is_arabic() else "English", func() -> void:
		GameState.toggle_language())
	var reset_action := func() -> void:
		GameState.reset_progress()
		_flash_status(tr("SET_RESET_CONFIRM"))
	_add_setting(tr("SET_RESET"), "", reset_action, true)


func _add_setting(title: String, value: String, on_pressed: Callable, danger: bool = false) -> void:
	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	settings_grid.add_child(label)
	var button := Button.new()
	button.text = value if value != "" else title
	button.custom_minimum_size = Vector2(300, 0)
	button.clip_text = true
	button.theme_type_variation = &"SecondaryButton"
	if danger:
		button.add_theme_color_override("font_color", Color(1.0, 0.6, 0.55))
	button.pressed.connect(func() -> void:
		AudioSynth.play("click", -6.0)
		on_pressed.call()
		_build_settings()
		_refresh_stats())
	settings_grid.add_child(button)


# ---------------------------------------------------------------- how to play
func _build_howto() -> void:
	for child in howto_lines.get_children():
		child.queue_free()
	for i in range(1, 8):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var num := Label.new()
		num.text = "%d." % i
		num.theme_type_variation = &"HudValue"
		num.add_theme_font_size_override("font_size", 24)
		num.custom_minimum_size = Vector2(40, 0)
		row.add_child(num)
		var text := Label.new()
		text.text = tr("HOWTO_%d" % i)
		text.add_theme_font_size_override("font_size", 20)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(text)
		howto_lines.add_child(row)


## About / licenses page: game info, Godot's MIT notice and the third-party
## components bundled in the engine (required by their licenses when distributing an APK).
func _build_about() -> void:
	for child in about_lines.get_children():
		child.queue_free()
	var version: String = str(ProjectSettings.get_setting("application/config/version", "1.0.0"))
	_add_about_line(tr("ABOUT_GAME") % version, &"HudValue")
	_add_about_line(tr("ABOUT_ENGINE") % str(Engine.get_version_info().get("string", "")))
	_add_about_line(Engine.get_license_text().strip_edges(), &"SmallLabel")
	_add_about_line(tr("ABOUT_FONT"))
	_add_about_line(tr("ABOUT_THIRD_PARTY"), &"HudValue")
	for component in Engine.get_copyright_info():
		var lines := PackedStringArray()
		var licenses := PackedStringArray()
		for part in component.get("parts", []):
			for holder in part.get("copyright", PackedStringArray()):
				if not lines.has(String(holder)):
					lines.append(String(holder))
			var lic := String(part.get("license", ""))
			if lic != "" and not licenses.has(lic):
				licenses.append(lic)
		var text := "%s - %s" % [String(component.get("name", "")), ", ".join(licenses)]
		if lines.size() > 0:
			text += "\n" + "\n".join(lines)
		_add_about_line(text, &"SmallLabel")


func _add_about_line(text: String, variation: StringName = &"") -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if variation != &"":
		label.theme_type_variation = variation
	about_lines.add_child(label)
