extends Node
## نقطة الدخول: يدير الحالات (القائمة ← الجراج ← القيادة ← النتائج) ويبني كل القوائم برمجياً.

enum State { MENU, GARAGE, DRIVING, PAUSED, RESULTS, SETTINGS }

var state := State.MENU
var ui_layer: CanvasLayer
var current_screen: Control
var driving: DrivingScene
var _shot_dir := ""
var _shot_frame := 0
var _shot_queue: Array = []

const C_BG := Color(0.07, 0.09, 0.14)
const C_PANEL := Color(0.11, 0.14, 0.2)
const C_ACCENT := Color(0.98, 0.78, 0.2)
const C_OK := Color(0.35, 0.85, 0.5)
const C_BAD := Color(0.95, 0.35, 0.3)
const C_TEXT := Color(0.95, 0.96, 0.98)
const C_MUTED := Color(0.65, 0.7, 0.8)

func _ready() -> void:
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)
	_parse_args()
	show_menu()

func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--shots="):
			_shot_dir = a.substr(8)
			DirAccess.make_dir_recursive_absolute(_shot_dir)
		if a.begins_with("--flow="):
			_shot_queue = a.substr(7).split(",")
	if _shot_dir != "":
		_run_test_flow()

# ==================================================================== أدوات بناء الواجهة
func _clear_screen() -> void:
	if current_screen and is_instance_valid(current_screen):
		current_screen.queue_free()
	current_screen = null

func _screen(bg := true) -> Control:
	_clear_screen()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	if bg:
		var cr := ColorRect.new()
		cr.color = C_BG
		cr.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(cr)
	ui_layer.add_child(root)
	current_screen = root
	return root

func _label(text: String, fs: int, col := C_TEXT, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _button(text: String, col := C_ACCENT, fs := 30, h := 84.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, h)
	b.add_theme_font_size_override("font_size", fs)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(18)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	b.add_theme_stylebox_override("normal", sb)
	var sbh := sb.duplicate()
	sbh.bg_color = col.lightened(0.12)
	b.add_theme_stylebox_override("hover", sbh)
	var sbp := sb.duplicate()
	sbp.bg_color = col.darkened(0.15)
	b.add_theme_stylebox_override("pressed", sbp)
	var sbd := sb.duplicate()
	sbd.bg_color = Color(0.25, 0.27, 0.33)
	b.add_theme_stylebox_override("disabled", sbd)
	var dark_text := col.get_luminance() > 0.55
	b.add_theme_color_override("font_color", Color(0.1, 0.1, 0.12) if dark_text else C_TEXT)
	b.add_theme_color_override("font_hover_color", Color(0.1, 0.1, 0.12) if dark_text else C_TEXT)
	b.add_theme_color_override("font_pressed_color", Color(0.1, 0.1, 0.12) if dark_text else C_TEXT)
	b.add_theme_color_override("font_disabled_color", C_MUTED)
	b.pressed.connect(func(): AudioFX.play("ui_click", -6.0))
	return b

func _card(col := C_PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(22)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	p.add_theme_stylebox_override("panel", sb)
	return p

func _vbox(parent: Control, margin := 28, sep := 16) -> VBoxContainer:
	var mc := MarginContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	mc.add_theme_constant_override("margin_left", margin)
	mc.add_theme_constant_override("margin_right", margin)
	mc.add_theme_constant_override("margin_top", margin + 20)
	mc.add_theme_constant_override("margin_bottom", margin)
	parent.add_child(mc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", sep)
	mc.add_child(vb)
	return vb

func _scroll_vbox(parent: Control, margin := 28, sep := 16) -> VBoxContainer:
	var mc := MarginContainer.new()
	mc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mc.add_theme_constant_override("margin_left", margin)
	mc.add_theme_constant_override("margin_right", margin)
	parent.add_child(mc)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mc.add_child(sc)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", sep)
	sc.add_child(vb)
	return vb

func _stat_row(parent: Control, key: String, value: String, col := C_TEXT) -> void:
	var hb := HBoxContainer.new()
	var k := _label(key, 24, C_MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := _label(value, 24, col, HORIZONTAL_ALIGNMENT_RIGHT)
	hb.add_child(k)
	hb.add_child(v)
	parent.add_child(hb)

func _bus_preview(bus_id: String, w := 200.0, h := 90.0) -> Control:
	## رسم مبسّط للباص (2D) لعرضه في الجراج
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	var data := BusData.get_bus(bus_id)
	var col: Color = data["color"]
	var len_ratio: float = float(data["length"]) / 16.0
	c.draw.connect(func():
		var bw := w * (0.45 + 0.55 * len_ratio)
		var x0 := (w - bw) * 0.5
		c.draw_rect(Rect2(x0, h * 0.25, bw, h * 0.5), col)
		c.draw_rect(Rect2(x0 + 6, h * 0.3, bw - 12, h * 0.2), Color(0.55, 0.7, 0.85))
		c.draw_rect(Rect2(x0, h * 0.2, bw, h * 0.08), Color(0.95, 0.95, 0.95))
		var n := 2 if len_ratio < 0.8 else 3
		for i in range(n):
			var wx := x0 + bw * (0.15 + 0.7 * i / max(n - 1, 1))
			c.draw_circle(Vector2(wx, h * 0.78), h * 0.11, Color(0.1, 0.1, 0.12))
			c.draw_circle(Vector2(wx, h * 0.78), h * 0.05, Color(0.7, 0.7, 0.72))
		c.draw_rect(Rect2(x0 + bw - 8, h * 0.45, 8, h * 0.12), Color(1, 0.95, 0.7))
	)
	return c

# ==================================================================== القائمة الرئيسية
func show_menu() -> void:
	state = State.MENU
	get_tree().paused = false
	AudioFX.music_start()
	var root := _screen()
	# خلفية متدرجة
	var grad := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.05, 0.12, 0.25))
	g.set_color(1, Color(0.9, 0.55, 0.25))
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	grad.texture = gt
	grad.set_anchors_preset(Control.PRESET_FULL_RECT)
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	root.add_child(grad)
	# "طريق" في الأسفل
	var road := ColorRect.new()
	road.color = Color(0.2, 0.21, 0.24)
	road.anchor_top = 0.72
	road.anchor_bottom = 1.0
	road.anchor_right = 1.0
	root.add_child(road)
	var line := ColorRect.new()
	line.color = C_ACCENT
	line.anchor_left = 0.0
	line.anchor_right = 1.0
	line.anchor_top = 0.78
	line.anchor_bottom = 0.785
	root.add_child(line)
	# مبانٍ سيلويت
	var sky := Control.new()
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky.draw.connect(func():
		var s := sky.size
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		var x := 0.0
		while x < s.x:
			var bw := rng.randf_range(40, 90)
			var bh := rng.randf_range(80, 260)
			sky.draw_rect(Rect2(x, s.y * 0.72 - bh, bw - 6, bh), Color(0.08, 0.1, 0.18, 0.9))
			for wy in range(int(bh / 28)):
				for wx in range(int(bw / 22)):
					if rng.randf() < 0.55:
						sky.draw_rect(Rect2(x + 6 + wx * 22, s.y * 0.72 - bh + 10 + wy * 28, 10, 14), Color(1, 0.85, 0.5, 0.7))
			x += bw
	)
	root.add_child(sky)
	var vb := _vbox(root, 32, 18)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 40)
	vb.add_child(spacer)
	var title := _label("🚌", 96)
	vb.add_child(title)
	var t1 := _label("Bus Simulator", 56, C_TEXT)
	t1.add_theme_constant_override("outline_size", 10)
	t1.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	vb.add_child(t1)
	var t2 := _label("ULTIMATE", 44, C_ACCENT)
	t2.add_theme_constant_override("outline_size", 10)
	t2.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	vb.add_child(t2)
	var sub := _label("محاكي الباص المطلق", 28, Color(1, 1, 1, 0.85))
	vb.add_child(sub)
	var sp2 := Control.new()
	sp2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(sp2)
	# بطاقة الحالة
	var card := _card(Color(0.07, 0.09, 0.14, 0.85))
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	card.add_child(cv)
	var xp := GameState.xp_progress()
	cv.add_child(_label("المستوى %d  •  💰 %s" % [GameState.level, GameState.fmt_money(GameState.money)], 26, C_ACCENT))
	var pb := ProgressBar.new()
	pb.min_value = 0
	pb.max_value = xp.y
	pb.value = xp.x
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, 14)
	var f := StyleBoxFlat.new()
	f.bg_color = C_OK
	f.set_corner_radius_all(7)
	pb.add_theme_stylebox_override("fill", f)
	var bgs := StyleBoxFlat.new()
	bgs.bg_color = Color(0.2, 0.22, 0.28)
	bgs.set_corner_radius_all(7)
	pb.add_theme_stylebox_override("background", bgs)
	cv.add_child(pb)
	cv.add_child(_label("الباص الحالي: %s" % BusData.get_bus(GameState.current_bus)["name"], 20, C_MUTED))
	vb.add_child(card)
	var play := _button("▶  ابدأ القيادة", C_ACCENT, 34, 96)
	play.pressed.connect(show_garage)
	vb.add_child(play)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	var garage := _button("🚌 الجراج", Color(0.2, 0.45, 0.8), 26, 74)
	garage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	garage.pressed.connect(func(): show_garage(true))
	var settings := _button("⚙️ الإعدادات", Color(0.3, 0.33, 0.42), 26, 74)
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.pressed.connect(show_settings)
	hb.add_child(garage)
	hb.add_child(settings)
	vb.add_child(hb)
	var stats := _label("👥 %d راكب  •  🛣 %.1f كم  •  ✨ %d توقف مثالي" % [int(GameState.stats["passengers"]), float(GameState.stats["distance_km"]), int(GameState.stats["perfect_stops"])], 18, Color(1, 1, 1, 0.8))
	vb.add_child(stats)
	var ver := _label("v1.0 • Godot 4.7.2", 14, Color(1, 1, 1, 0.5))
	vb.add_child(ver)

# ==================================================================== الجراج + اختيار الخط
func show_garage(garage_only := false) -> void:
	state = State.GARAGE
	var root := _screen()
	var vb := _vbox(root, 24, 12)
	var top := HBoxContainer.new()
	var back := _button("‹", Color(0.3, 0.33, 0.42), 30, 64)
	back.custom_minimum_size = Vector2(64, 64)
	back.pressed.connect(show_menu)
	top.add_child(back)
	var title := _label("الجراج والخطوط" if not garage_only else "الجراج", 34, C_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var money := _label("💰 " + GameState.fmt_money(GameState.money), 26, C_ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
	top.add_child(money)
	vb.add_child(top)
	var list := _scroll_vbox(vb, 0, 14)
	# ---- الباصات
	list.add_child(_label("اختر باصك", 26, C_MUTED, HORIZONTAL_ALIGNMENT_LEFT))
	for id in ["mini", "city", "coach", "articulated"]:
		var d := BusData.get_bus(id)
		var owned := GameState.owns_bus(id)
		var selected := GameState.current_bus == id
		var locked := GameState.level < int(d["unlock_level"])
		var card := _card(Color(0.13, 0.22, 0.32) if selected else C_PANEL)
		if selected:
			var sb: StyleBoxFlat = card.get_theme_stylebox("panel")
			sb.border_color = C_ACCENT
			sb.set_border_width_all(3)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 14)
		card.add_child(hb)
		hb.add_child(_bus_preview(id, 170, 80))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(_label(d["name"], 26, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT))
		info.add_child(_label("👥 %d راكب  •  🎫 %d ج/تذكرة  •  ⚡ %d كم/س" % [d["capacity"], d["fare"], d["max_speed"]], 17, C_MUTED, HORIZONTAL_ALIGNMENT_LEFT))
		var btn: Button
		if selected:
			btn = _button("✓ مختار", C_OK, 20, 52)
			btn.disabled = true
		elif owned:
			btn = _button("اختيار", Color(0.2, 0.45, 0.8), 20, 52)
			btn.pressed.connect(func(): GameState.select_bus(id); show_garage(garage_only))
		elif locked:
			btn = _button("🔒 المستوى %d" % d["unlock_level"], Color(0.3, 0.33, 0.42), 18, 52)
			btn.disabled = true
		else:
			btn = _button("شراء %s ج" % GameState.fmt_money(d["price"]), C_ACCENT if GameState.can_afford(d["price"]) else Color(0.3, 0.33, 0.42), 20, 52)
			btn.disabled = not GameState.can_afford(d["price"])
			btn.pressed.connect(func():
				if GameState.buy_bus(id):
					AudioFX.play("success")
				show_garage(garage_only)
			)
		info.add_child(btn)
		hb.add_child(info)
		list.add_child(card)
	# ---- الترقيات
	list.add_child(_label("الترقيات", 26, C_MUTED, HORIZONTAL_ALIGNMENT_LEFT))
	var ug := GridContainer.new()
	ug.columns = 2
	ug.add_theme_constant_override("h_separation", 12)
	ug.add_theme_constant_override("v_separation", 12)
	for uid in BusData.UPGRADES.keys():
		var u: Dictionary = BusData.UPGRADES[uid]
		var lvl := GameState.upgrade_level(uid)
		var maxl := int(u["max"])
		var card := _card()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 4)
		card.add_child(cv)
		cv.add_child(_label("%s %s" % [u["icon"], u["name"]], 22, C_TEXT))
		var dots := ""
		for i in range(maxl):
			dots += "●" if i < lvl else "○"
		cv.add_child(_label(dots, 20, C_ACCENT))
		cv.add_child(_label(u["desc"], 15, C_MUTED))
		var b: Button
		if lvl >= maxl:
			b = _button("الحد الأقصى", C_OK, 18, 48)
			b.disabled = true
		else:
			var price := BusData.upgrade_price(uid, lvl)
			b = _button("%s ج" % GameState.fmt_money(price), C_ACCENT if GameState.can_afford(price) else Color(0.3, 0.33, 0.42), 18, 48)
			b.disabled = not GameState.can_afford(price)
			b.pressed.connect(func():
				if GameState.buy_upgrade(uid):
					AudioFX.play("success", -4.0)
				show_garage(garage_only)
			)
		cv.add_child(b)
		ug.add_child(card)
	list.add_child(ug)
	if garage_only:
		return
	# ---- الخطوط
	list.add_child(_label("اختر الخط", 26, C_MUTED, HORIZONTAL_ALIGNMENT_LEFT))
	for rid in RouteData.ORDER:
		var r := RouteData.get_route(rid)
		var locked := GameState.level < int(r["unlock_level"])
		var rec: Dictionary = GameState.route_records.get(rid, {})
		var card := _card()
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		card.add_child(hb)
		var icon := "🌙" if r["time"] == "night" else ("🌧" if r["weather"] == "rain" else ("🌇" if r["time"] == "evening" else "☀️"))
		hb.add_child(_label(icon, 40))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(_label(r["name"], 24, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT))
		var detail := "🚏 %d محطات  •  🎁 مكافأة %d ج" % [r["stops"].size(), r["bonus"]]
		if rec.has("best"):
			detail += "  •  🏆 %d" % int(rec["best"])
		info.add_child(_label(detail, 16, C_MUTED, HORIZONTAL_ALIGNMENT_LEFT))
		hb.add_child(info)
		var b: Button
		if locked:
			b = _button("🔒 مستوى %d" % r["unlock_level"], Color(0.3, 0.33, 0.42), 18, 60)
			b.disabled = true
		else:
			b = _button("انطلق ▶", C_ACCENT, 22, 60)
			b.pressed.connect(func(): start_driving(rid))
		b.custom_minimum_size = Vector2(150, 60)
		hb.add_child(b)
		list.add_child(card)

# ==================================================================== القيادة
func start_driving(rid: String) -> void:
	state = State.DRIVING
	GameState.selected_route = rid
	GameState.save_game()
	_clear_screen()
	AudioFX.music_stop()
	if driving and is_instance_valid(driving):
		driving.cleanup()
		driving.queue_free()
	driving = DrivingScene.new()
	add_child(driving)
	driving.start(rid)
	driving.route_finished.connect(show_results)
	driving.pause_requested.connect(show_pause)

func show_pause() -> void:
	if state != State.DRIVING:
		return
	state = State.PAUSED
	get_tree().paused = true
	var root := _screen(false)
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var card := _card()
	card.custom_minimum_size = Vector2(440, 0)
	center.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	card.add_child(vb)
	vb.add_child(_label("⏸ إيقاف مؤقت", 36))
	var resume := _button("▶ استئناف", C_OK, 28)
	resume.pressed.connect(func():
		get_tree().paused = false
		state = State.DRIVING
		_clear_screen()
	)
	vb.add_child(resume)
	var restart := _button("↻ إعادة الخط", Color(0.2, 0.45, 0.8), 26)
	restart.pressed.connect(func():
		get_tree().paused = false
		start_driving(GameState.selected_route)
	)
	vb.add_child(restart)
	var settings := _button("⚙️ الإعدادات", Color(0.3, 0.33, 0.42), 24)
	settings.pressed.connect(func(): show_settings(true))
	vb.add_child(settings)
	var quit := _button("🏠 القائمة الرئيسية", C_BAD, 24)
	quit.pressed.connect(func():
		get_tree().paused = false
		if driving:
			driving.cleanup()
			driving.queue_free()
			driving = null
		show_menu()
	)
	vb.add_child(quit)

# ==================================================================== النتائج
func show_results(result: Dictionary) -> void:
	state = State.RESULTS
	var root := _screen(false)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.05, 0.1, 0.85)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var vb := _vbox(root, 28, 12)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(_label("اكتمل الخط! 🎉", 40, C_OK))
	vb.add_child(_label(result["route"], 24, C_MUTED))
	var stars := ""
	for i in range(3):
		stars += "★" if i < int(result["stars"]) else "☆"
	var sl := _label(stars, 64, C_ACCENT)
	vb.add_child(sl)
	var card := _card()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	card.add_child(cv)
	_stat_row(cv, "👥 الركاب", str(result["passengers"]))
	_stat_row(cv, "🎫 التذاكر", "+%d ج" % result["earned"], C_OK)
	_stat_row(cv, "🎁 مكافأة الخط", "+%d ج" % result["bonus"], C_OK)
	_stat_row(cv, "😊 مكافأة الراحة (%d%%)" % int(result["comfort"]), "+%d ج" % result["comfort_bonus"], C_OK)
	_stat_row(cv, "✨ توقفات مثالية ×%d" % result["perfect"], "+%d ج" % result["perf_bonus"], C_OK)
	_stat_row(cv, "⚠️ الغرامات", "-%d ج" % result["fines"], C_BAD if int(result["fines"]) > 0 else C_MUTED)
	_stat_row(cv, "💥 حوادث", str(result["collisions"]), C_BAD if int(result["collisions"]) > 0 else C_MUTED)
	var sep := HSeparator.new()
	cv.add_child(sep)
	var net: int = int(result["earned"]) + int(result["bonus"]) + int(result["comfort_bonus"]) + int(result["perf_bonus"]) - int(result["fines"])
	_stat_row(cv, "💰 الصافي", "%s%d ج" % ["+" if net >= 0 else "", net], C_ACCENT)
	_stat_row(cv, "⏱ الوقت", "%d:%02d" % [int(result["time"]) / 60, int(result["time"]) % 60])
	_stat_row(cv, "🏆 النقاط", str(result["score"]), C_ACCENT)
	vb.add_child(card)
	var xp := GameState.xp_progress()
	vb.add_child(_label("المستوى %d  •  %d / %d XP" % [GameState.level, int(xp.x), int(xp.y)], 20, C_MUTED))
	var again := _button("↻ مرة أخرى", Color(0.2, 0.45, 0.8), 26)
	again.pressed.connect(func(): start_driving(GameState.selected_route))
	vb.add_child(again)
	var cont := _button("التالي ▶", C_ACCENT, 30, 90)
	cont.pressed.connect(func():
		if driving:
			driving.cleanup()
			driving.queue_free()
			driving = null
		show_garage()
	)
	vb.add_child(cont)
	# تأثير النجوم
	sl.scale = Vector2(0.3, 0.3)
	sl.pivot_offset = Vector2(sl.size.x * 0.5, sl.size.y * 0.5)
	var tw := create_tween()
	tw.tween_property(sl, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ==================================================================== الإعدادات
func show_settings(from_pause := false) -> void:
	var prev_state := state
	state = State.SETTINGS
	var root := _screen(not from_pause)
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	if from_pause:
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.85)
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(dim)
	var vb := _vbox(root, 28, 14)
	var top := HBoxContainer.new()
	var back := _button("‹", Color(0.3, 0.33, 0.42), 30, 64)
	back.custom_minimum_size = Vector2(64, 64)
	back.pressed.connect(func():
		if from_pause:
			state = State.DRIVING
			show_pause()
		else:
			show_menu()
	)
	top.add_child(back)
	var title := _label("⚙️ الإعدادات", 34)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	vb.add_child(top)
	var card := _card()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 16)
	card.add_child(cv)
	_slider_row(cv, "🔊 المؤثرات", "sfx", 0.0, 1.0)
	_slider_row(cv, "🎵 الموسيقى", "music", 0.0, 1.0)
	_slider_row(cv, "🎮 حساسية التوجيه", "steer_sensitivity", 0.5, 1.5)
	_toggle_row(cv, "📳 الاهتزاز", "haptics")
	_toggle_row(cv, "🌤 الظلال (أداء)", "shadows")
	vb.add_child(card)
	if not from_pause:
		var reset := _button("🗑 إعادة تعيين التقدم", C_BAD, 22, 64)
		reset.pressed.connect(func():
			GameState.reset_progress()
			show_settings()
		)
		vb.add_child(reset)
	var info := _label("Bus Simulator Ultimate v1.0\nGodot Engine 4.7.2 • Jolt Physics\nكل الأصوات والنماذج مولّدة برمجياً", 16, C_MUTED)
	vb.add_child(info)

func _slider_row(parent: Control, text: String, key: String, minv: float, maxv: float) -> void:
	var v := VBoxContainer.new()
	v.add_child(_label(text, 22, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT))
	var s := HSlider.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = 0.05
	s.value = float(GameState.settings.get(key, 1.0))
	s.custom_minimum_size = Vector2(0, 40)
	s.value_changed.connect(func(val): GameState.set_setting(key, val))
	v.add_child(s)
	parent.add_child(v)

func _toggle_row(parent: Control, text: String, key: String) -> void:
	var hb := HBoxContainer.new()
	var l := _label(text, 22, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(l)
	var cb := CheckButton.new()
	cb.button_pressed = bool(GameState.settings.get(key, true))
	cb.toggled.connect(func(on): GameState.set_setting(key, on))
	hb.add_child(cb)
	parent.add_child(hb)

# ==================================================================== اختبار آلي + لقطات شاشة
func _run_test_flow() -> void:
	## يشغَّل عبر: godot --path . -- --shots=/tmp/shots --flow=menu,garage,drive,results
	## يأخذ لقطة لكل حالة ثم يخرج. يُستخدم كـ "عين" أثناء التطوير.
	await get_tree().process_frame
	await get_tree().process_frame
	for step in _shot_queue:
		match step:
			"menu":
				show_menu()
				await _snap("01_menu", 5)
			"garage":
				show_garage()
				await _snap("02_garage", 5)
			"settings":
				show_settings()
				await _snap("03_settings", 5)
			"drive":
				start_driving(GameState.selected_route)
				await _snap("04_drive_start", 20)
				# قيادة آلية لبعض الثواني
				var frames := 0
				while frames < 240 and driving and not driving._finished:
					await get_tree().process_frame
					frames += 1
				await _snap("05_drive_moving", 2)
				if driving:
					driving._on_camera_toggle()
					await _snap("06_drive_cam2", 5)
					driving._on_camera_toggle()
					await _snap("07_drive_cockpit", 5)
					driving._on_camera_toggle()
			"drive_long":
				start_driving(GameState.selected_route)
				var frames := 0
				var snap_i := 0
				while frames < 3000 and driving and not driving._finished:
					await get_tree().process_frame
					frames += 1
					if frames % 400 == 0:
						await _snap("drive_%02d" % snap_i, 1)
						snap_i += 1
				await _snap("drive_end", 5)
			"pause":
				if driving:
					show_pause()
					await _snap("08_pause", 5)
					get_tree().paused = false
					state = State.DRIVING
					_clear_screen()
			"results":
				if driving:
					driving._finish_route()
					for i in range(130):
						await get_tree().process_frame
					await _snap("09_results", 5)
	print("TEST_FLOW_DONE")
	get_tree().quit()

func _snap(name: String, wait_frames := 3) -> void:
	for i in range(wait_frames):
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shot_dir.path_join(name + ".png"))
	print("SNAP ", name)
