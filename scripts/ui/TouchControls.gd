class_name TouchControls
extends Control
## تحكم لمس بيد واحدة: عجلة قيادة (سحب دائري) يسار + دواسات يمين + أزرار أبواب/كلاكس/كاميرا.
## يرسم كل شيء برمجياً (لا صور) — خفيف وقابل للتخصيص.

signal doors_pressed()
signal horn_pressed(down: bool)
signal camera_pressed()
signal pause_pressed()

var steer := 0.0       # -1..1
var throttle := 0.0    # 0..1
var brake := 0.0       # 0..1

var _wheel_center := Vector2.ZERO
var _wheel_radius := 120.0
var _wheel_touch := -1
var _wheel_angle := 0.0
var _wheel_start_angle := 0.0
var _wheel_angle_at_start := 0.0
const WHEEL_MAX_ANGLE := deg_to_rad(120.0)

var _gas_rect := Rect2()
var _brake_rect := Rect2()
var _gas_touch := -1
var _brake_touch := -1

var _btn_doors := Rect2()
var _btn_horn := Rect2()
var _btn_cam := Rect2()
var _btn_pause := Rect2()
var _horn_touch := -1
var _pressed_flash: Dictionary = {}
var _font: Font
var doors_open := false
var _keyboard_steer := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	var s := size
	_wheel_radius = clampf(s.x * 0.19, 80.0, 150.0)
	_wheel_center = Vector2(_wheel_radius + 28.0, s.y - _wheel_radius - 40.0)
	var pw := clampf(s.x * 0.17, 70.0, 130.0)
	var ph := pw * 1.35
	_gas_rect = Rect2(Vector2(s.x - pw - 24.0, s.y - ph - 40.0), Vector2(pw, ph))
	_brake_rect = Rect2(Vector2(s.x - pw * 2.0 - 44.0, s.y - ph * 0.75 - 40.0), Vector2(pw, ph * 0.75))
	var bsz := clampf(s.x * 0.15, 64.0, 110.0)
	_btn_doors = Rect2(Vector2(s.x - bsz - 24.0, s.y - ph - 40.0 - bsz - 20.0), Vector2(bsz, bsz))
	_btn_horn = Rect2(Vector2(s.x - bsz * 2.0 - 44.0, s.y - ph - 40.0 - bsz - 20.0), Vector2(bsz, bsz))
	_btn_cam = Rect2(Vector2(24.0, _wheel_center.y - _wheel_radius - bsz - 30.0), Vector2(bsz, bsz))
	_btn_pause = Rect2(Vector2(s.x - 76.0, 20.0), Vector2(56.0, 56.0))
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_touch(event.index, event.position, event.pressed)
		accept_event()
	elif event is InputEventScreenDrag:
		_drag(event.index, event.position)
		accept_event()

func _touch(idx: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		if pos.distance_to(_wheel_center) <= _wheel_radius * 1.25 and _wheel_touch == -1:
			_wheel_touch = idx
			_wheel_start_angle = (pos - _wheel_center).angle()
			_wheel_angle_at_start = _wheel_angle
		elif _gas_rect.has_point(pos):
			_gas_touch = idx
			_pressed_flash["gas"] = true
		elif _brake_rect.has_point(pos):
			_brake_touch = idx
			_pressed_flash["brake"] = true
		elif _btn_doors.has_point(pos):
			_flash("doors")
			doors_pressed.emit()
		elif _btn_horn.has_point(pos):
			_horn_touch = idx
			_pressed_flash["horn"] = true
			horn_pressed.emit(true)
		elif _btn_cam.has_point(pos):
			_flash("cam")
			camera_pressed.emit()
		elif _btn_pause.has_point(pos):
			_flash("pause")
			pause_pressed.emit()
	else:
		if idx == _wheel_touch:
			_wheel_touch = -1
		if idx == _gas_touch:
			_gas_touch = -1
			_pressed_flash["gas"] = false
		if idx == _brake_touch:
			_brake_touch = -1
			_pressed_flash["brake"] = false
		if idx == _horn_touch:
			_horn_touch = -1
			_pressed_flash["horn"] = false
			horn_pressed.emit(false)
	queue_redraw()

func _drag(idx: int, pos: Vector2) -> void:
	if idx == _wheel_touch:
		var a := (pos - _wheel_center).angle()
		var delta := wrapf(a - _wheel_start_angle, -PI, PI)
		_wheel_angle = clampf(_wheel_angle_at_start + delta, -WHEEL_MAX_ANGLE, WHEEL_MAX_ANGLE)
	# السماح بالانزلاق بين البنزين والفرامل بنفس الإصبع
	if idx == _gas_touch and _brake_rect.has_point(pos):
		_gas_touch = -1
		_brake_touch = idx
		_pressed_flash["gas"] = false
		_pressed_flash["brake"] = true
	elif idx == _brake_touch and _gas_rect.has_point(pos):
		_brake_touch = -1
		_gas_touch = idx
		_pressed_flash["brake"] = false
		_pressed_flash["gas"] = true
	queue_redraw()

func _flash(key: String) -> void:
	_pressed_flash[key] = true
	get_tree().create_timer(0.15).timeout.connect(func(): _pressed_flash[key] = false; queue_redraw())

func _process(delta: float) -> void:
	# العجلة تعود للمنتصف تلقائياً عند الإفلات (Game Feel: توجيه سلس)
	if _wheel_touch == -1:
		_wheel_angle = move_toward(_wheel_angle, 0.0, delta * 4.5)
	# دعم الكيبورد للاختبار على الكمبيوتر
	var kb_steer := 0.0
	var kb_gas := 0.0
	var kb_brake := 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		kb_steer -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		kb_steer += 1.0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		kb_gas = 1.0
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		kb_brake = 1.0
	_keyboard_steer = move_toward(_keyboard_steer, kb_steer, delta * 3.0)
	if _wheel_touch == -1 and kb_steer != 0.0:
		_wheel_angle = _keyboard_steer * WHEEL_MAX_ANGLE
	steer = _wheel_angle / WHEEL_MAX_ANGLE
	throttle = 1.0 if (_gas_touch != -1 or kb_gas > 0.0) else 0.0
	brake = 1.0 if (_brake_touch != -1 or kb_brake > 0.0) else 0.0
	queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E, KEY_SPACE: doors_pressed.emit()
			KEY_H: horn_pressed.emit(true); get_tree().create_timer(0.4).timeout.connect(func(): horn_pressed.emit(false))
			KEY_C: camera_pressed.emit()
			KEY_ESCAPE, KEY_P: pause_pressed.emit()

# ------------------------------------------------------------------ الرسم
func _draw() -> void:
	_draw_wheel()
	_draw_pedal(_gas_rect, Color(0.25, 0.75, 0.4), "▲", _pressed_flash.get("gas", false))
	_draw_pedal(_brake_rect, Color(0.85, 0.3, 0.3), "▼", _pressed_flash.get("brake", false))
	_draw_button(_btn_doors, Color(0.95, 0.75, 0.2) if doors_open else Color(0.25, 0.55, 0.9), "🚪", _pressed_flash.get("doors", false))
	_draw_button(_btn_horn, Color(0.9, 0.55, 0.2), "📢", _pressed_flash.get("horn", false))
	_draw_button(_btn_cam, Color(0.5, 0.5, 0.6), "📷", _pressed_flash.get("cam", false))
	_draw_button(_btn_pause, Color(0.35, 0.35, 0.45), "II", _pressed_flash.get("pause", false), 22)

func _draw_wheel() -> void:
	var c := _wheel_center
	var r := _wheel_radius
	draw_circle(c, r + 6.0, Color(0, 0, 0, 0.25))
	draw_circle(c, r, Color(0.12, 0.13, 0.17, 0.85))
	draw_arc(c, r - 10.0, 0, TAU, 48, Color(0.32, 0.34, 0.4), 16.0, true)
	# مؤشر الزاوية
	var indicator := Color(0.95, 0.75, 0.2) if _wheel_touch != -1 else Color(0.8, 0.8, 0.85)
	var a := _wheel_angle - PI / 2
	for k in range(3):
		var ang := a + k * TAU / 3.0
		var p1 := c + Vector2(cos(ang), sin(ang)) * (r * 0.28)
		var p2 := c + Vector2(cos(ang), sin(ang)) * (r - 16.0)
		draw_line(p1, p2, Color(0.32, 0.34, 0.4), 12.0, true)
	var top := c + Vector2(cos(a), sin(a)) * (r - 18.0)
	draw_circle(top, 10.0, indicator)
	draw_circle(c, r * 0.26, Color(0.2, 0.21, 0.26))
	draw_circle(c, r * 0.18, Color(0.95, 0.75, 0.2))

func _draw_pedal(rect: Rect2, col: Color, label: String, pressed: bool) -> void:
	var bg := col.darkened(0.55)
	bg.a = 0.8
	var fg := col if pressed else col.darkened(0.15)
	var inner := rect.grow(-4.0) if pressed else rect
	draw_rect(rect.grow(4.0), Color(0, 0, 0, 0.25))
	draw_rect(rect, bg)
	draw_rect(inner.grow(-8.0), fg)
	var fs := int(rect.size.x * 0.42)
	var ts := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	draw_string(_font, rect.get_center() + Vector2(-ts.x * 0.5, ts.y * 0.32), label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(1, 1, 1, 0.95))

func _draw_button(rect: Rect2, col: Color, label: String, pressed: bool, fs_override := 0) -> void:
	var r := rect.size.x * 0.5
	var c := rect.get_center()
	draw_circle(c, r + 3.0, Color(0, 0, 0, 0.25))
	draw_circle(c, r, col.lightened(0.25) if pressed else col)
	draw_arc(c, r - 3.0, 0, TAU, 32, Color(1, 1, 1, 0.35), 3.0, true)
	var fs := fs_override if fs_override > 0 else int(r * 0.9)
	var ts := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	draw_string(_font, c + Vector2(-ts.x * 0.5, ts.y * 0.32), label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(1, 1, 1))
