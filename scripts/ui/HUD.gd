class_name HUD
extends Control
## واجهة القيادة: السرعة، المال، المحطة القادمة والمسافة، الركاب، الرضا، الرسائل العائمة.
## يُبنى برمجياً بأسلوب نظيف ومريح للعين (Art Style متناسق).

var lbl_speed: Label
var lbl_speed_unit: Label
var lbl_money: Label
var lbl_next_stop: Label
var lbl_distance: Label
var lbl_passengers: Label
var bar_comfort: ProgressBar
var lbl_comfort: Label
var lbl_stop_counter: Label
var lbl_time: Label
var speed_limit_box: PanelContainer
var lbl_limit: Label
var msg_root: Control
var big_msg: Label
var _big_tween: Tween
var minimap: Control
var _font_size_scale := 1.0

const COL_BG := Color(0.07, 0.09, 0.14, 0.78)
const COL_ACCENT := Color(0.98, 0.78, 0.2)
const COL_OK := Color(0.35, 0.85, 0.5)
const COL_BAD := Color(0.95, 0.35, 0.3)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()

func _panel(pos: Vector2, sz: Vector2, col := COL_BG, radius := 18) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	p.position = pos
	p.custom_minimum_size = sz
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)
	return p

func _label(text: String, fs: int, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _build() -> void:
	# ---- الشريط العلوي: المال + الوقت
	var top := _panel(Vector2(16, 16), Vector2(0, 0))
	top.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	top.add_child(hb)
	var coin := _label("💰", 26)
	hb.add_child(coin)
	lbl_money = _label(GameState.fmt_money(GameState.money), 30, COL_ACCENT)
	hb.add_child(lbl_money)
	# ---- المحطة القادمة (لوحة عريضة في الأعلى منتصف)
	var np := _panel(Vector2(0, 90), Vector2(0, 0), Color(0.07, 0.09, 0.14, 0.82), 16)
	np.anchor_left = 0.08
	np.anchor_right = 0.92
	np.offset_left = 0
	np.offset_right = 0
	np.position.y = 92
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	np.add_child(vb)
	lbl_stop_counter = _label("المحطة ١ / ٤", 20, Color(0.75, 0.8, 0.9), HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(lbl_stop_counter)
	lbl_next_stop = _label("—", 34, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	lbl_next_stop.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl_next_stop.clip_text = true
	vb.add_child(lbl_next_stop)
	lbl_distance = _label("٠ م", 26, COL_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(lbl_distance)
	# ---- الركاب + الرضا (يسار تحت اللوحة)
	var pp := _panel(Vector2(16, 230), Vector2(0, 0))
	var pv := VBoxContainer.new()
	pp.add_child(pv)
	lbl_passengers = _label("👥 ٠ / ١٤", 24)
	pv.add_child(lbl_passengers)
	var ch := HBoxContainer.new()
	pv.add_child(ch)
	lbl_comfort = _label("😊", 22)
	ch.add_child(lbl_comfort)
	bar_comfort = ProgressBar.new()
	bar_comfort.min_value = 0
	bar_comfort.max_value = 100
	bar_comfort.value = 100
	bar_comfort.show_percentage = false
	bar_comfort.custom_minimum_size = Vector2(150, 16)
	var sbf := StyleBoxFlat.new()
	sbf.bg_color = COL_OK
	sbf.set_corner_radius_all(8)
	bar_comfort.add_theme_stylebox_override("fill", sbf)
	var sbb := StyleBoxFlat.new()
	sbb.bg_color = Color(0.2, 0.22, 0.28)
	sbb.set_corner_radius_all(8)
	bar_comfort.add_theme_stylebox_override("background", sbb)
	bar_comfort.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ch.add_child(bar_comfort)
	# ---- السرعة (منتصف أسفل فوق أزرار التحكم)
	var sp := _panel(Vector2(0, 0), Vector2(150, 0), Color(0.07, 0.09, 0.14, 0.85), 24)
	sp.anchor_left = 0.5
	sp.anchor_right = 0.5
	sp.anchor_top = 1.0
	sp.anchor_bottom = 1.0
	sp.offset_left = -75
	sp.offset_right = 75
	sp.offset_top = -430
	sp.offset_bottom = -340
	sp.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var sv := VBoxContainer.new()
	sv.alignment = BoxContainer.ALIGNMENT_CENTER
	sp.add_child(sv)
	lbl_speed = _label("0", 46, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	sv.add_child(lbl_speed)
	lbl_speed_unit = _label("كم/س", 16, Color(0.7, 0.75, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
	sv.add_child(lbl_speed_unit)
	# ---- لوحة حد السرعة (دائرة حمراء)
	speed_limit_box = _panel(Vector2(0, 0), Vector2(64, 64), Color(0.95, 0.95, 0.95), 32)
	var sbl: StyleBoxFlat = speed_limit_box.get_theme_stylebox("panel")
	sbl.border_color = Color(0.85, 0.1, 0.1)
	sbl.set_border_width_all(6)
	sbl.content_margin_left = 0
	sbl.content_margin_right = 0
	sbl.content_margin_top = 0
	sbl.content_margin_bottom = 0
	speed_limit_box.anchor_left = 0.5
	speed_limit_box.anchor_right = 0.5
	speed_limit_box.anchor_top = 1.0
	speed_limit_box.anchor_bottom = 1.0
	speed_limit_box.offset_left = 85
	speed_limit_box.offset_right = 149
	speed_limit_box.offset_top = -420
	speed_limit_box.offset_bottom = -356
	lbl_limit = _label("50", 26, Color(0.1, 0.1, 0.1), HORIZONTAL_ALIGNMENT_CENTER)
	lbl_limit.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	speed_limit_box.add_child(lbl_limit)
	# ---- رسائل عائمة
	msg_root = Control.new()
	msg_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	msg_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(msg_root)
	big_msg = _label("", 44, COL_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	big_msg.set_anchors_preset(Control.PRESET_CENTER_TOP)
	big_msg.anchor_left = 0.0
	big_msg.anchor_right = 1.0
	big_msg.offset_top = 300
	big_msg.offset_bottom = 380
	big_msg.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	big_msg.add_theme_constant_override("outline_size", 8)
	big_msg.modulate.a = 0.0
	add_child(big_msg)
	# ---- الخريطة الصغيرة
	minimap = Control.new()
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.anchor_left = 1.0
	minimap.anchor_right = 1.0
	minimap.offset_left = -156
	minimap.offset_right = -16
	minimap.offset_top = 230
	minimap.offset_bottom = 370
	add_child(minimap)
	GameState.money_changed.connect(_on_money)

func _on_money(amount: int, delta: int) -> void:
	lbl_money.text = GameState.fmt_money(amount)
	if delta != 0:
		var tw := create_tween()
		lbl_money.scale = Vector2(1.25, 1.25)
		tw.tween_property(lbl_money, "scale", Vector2.ONE, 0.25).set_ease(Tween.EASE_OUT)

func update_speed(kmh: float, limit: int) -> void:
	lbl_speed.text = str(int(round(kmh)))
	lbl_limit.text = str(limit)
	lbl_speed.add_theme_color_override("font_color", COL_BAD if kmh > limit + 3 else Color.WHITE)

func update_next_stop(name: String, dist: float, idx: int, total: int) -> void:
	lbl_next_stop.text = name
	if dist >= 1000.0:
		lbl_distance.text = "%.1f كم" % (dist / 1000.0)
	else:
		lbl_distance.text = "%d م" % int(dist)
	lbl_stop_counter.text = "المحطة %d / %d" % [idx, total]

func update_passengers(count: int, capacity: int) -> void:
	lbl_passengers.text = "👥 %d / %d" % [count, capacity]

func update_comfort(v: float) -> void:
	bar_comfort.value = v
	var sbf: StyleBoxFlat = bar_comfort.get_theme_stylebox("fill")
	if v > 66:
		sbf.bg_color = COL_OK
		lbl_comfort.text = "😊"
	elif v > 33:
		sbf.bg_color = COL_ACCENT
		lbl_comfort.text = "😐"
	else:
		sbf.bg_color = COL_BAD
		lbl_comfort.text = "😡"

## رسالة كبيرة في منتصف الشاشة (Perfect! / غرامة / ...)
func show_big(text: String, col := COL_ACCENT, dur := 1.4) -> void:
	big_msg.text = text
	big_msg.add_theme_color_override("font_color", col)
	if _big_tween:
		_big_tween.kill()
	big_msg.modulate.a = 1.0
	big_msg.scale = Vector2(0.7, 0.7)
	big_msg.pivot_offset = big_msg.size * 0.5
	_big_tween = create_tween()
	_big_tween.tween_property(big_msg, "scale", Vector2.ONE, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_big_tween.tween_interval(dur)
	_big_tween.tween_property(big_msg, "modulate:a", 0.0, 0.4)

## رقم يطفو (+٥ ج) من نقطة على الشاشة
func float_text(text: String, screen_pos: Vector2, col := COL_OK) -> void:
	var l := _label(text, 30, col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 6)
	l.position = screen_pos + Vector2(randf_range(-30, 30), 0)
	msg_root.add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 110.0, 1.1).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 1.1).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)

# ------------------------------------------------------------------ الخريطة الصغيرة
var _mm_route: Array = []
var _mm_stops: Array = []
var _mm_bus := Vector3.ZERO
var _mm_bus_rot := 0.0
var _mm_next := 0

func minimap_set(route_pts: Array, stops: Array) -> void:
	_mm_route = route_pts
	_mm_stops = stops
	minimap.draw.connect(_draw_minimap)

func minimap_update(bus_pos: Vector3, bus_rot: float, next_idx: int) -> void:
	_mm_bus = bus_pos
	_mm_bus_rot = bus_rot
	_mm_next = next_idx
	minimap.queue_redraw()

func _mm_map(p: Vector3) -> Vector2:
	var half := RouteData.BLOCK * (RouteData.GRID_N - 1) * 0.5 + 10.0
	var s := minimap.size
	return Vector2((p.x + half) / (half * 2.0) * s.x, (p.z + half) / (half * 2.0) * s.y)

func _draw_minimap() -> void:
	var s := minimap.size
	var sb := StyleBoxFlat.new()
	minimap.draw_rect(Rect2(Vector2.ZERO, s), Color(0.07, 0.09, 0.14, 0.75))
	# شبكة الطرق
	for k in range(RouteData.GRID_N):
		var c := (k - 2) * RouteData.BLOCK
		var a := _mm_map(Vector3(-200, 0, c))
		var b := _mm_map(Vector3(200, 0, c))
		minimap.draw_line(a, b, Color(0.3, 0.33, 0.4), 2.0)
		a = _mm_map(Vector3(c, 0, -200))
		b = _mm_map(Vector3(c, 0, 200))
		minimap.draw_line(a, b, Color(0.3, 0.33, 0.4), 2.0)
	# مسار الخط
	for i in range(_mm_route.size() - 1):
		minimap.draw_line(_mm_map(_mm_route[i]), _mm_map(_mm_route[i + 1]), COL_ACCENT.darkened(0.2), 3.0)
	# المحطات
	for i in range(_mm_stops.size()):
		var col := COL_OK if i < _mm_next else (COL_ACCENT if i == _mm_next else Color(0.8, 0.8, 0.85))
		minimap.draw_circle(_mm_map(_mm_stops[i]), 5.0 if i == _mm_next else 3.5, col)
	# الباص
	var bp := _mm_map(_mm_bus)
	var d := Vector2(sin(_mm_bus_rot), cos(_mm_bus_rot)) * -1.0
	var pts := PackedVector2Array([bp + d * 8.0, bp + d.rotated(2.5) * 6.0, bp + d.rotated(-2.5) * 6.0])
	minimap.draw_colored_polygon(pts, Color(0.3, 0.7, 1.0))
