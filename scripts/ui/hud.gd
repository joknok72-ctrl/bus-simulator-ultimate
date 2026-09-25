class_name Hud
extends Control
## In-game heads-up display: mission info, gauges, minimap, messages and the
## touch control layer.

@onready var touch_controls: TouchControls = $TouchControls
@onready var minimap: Minimap = $Minimap
@onready var speedometer: Speedometer = $Speedometer
@onready var stop_label: Label = $TopCenter/VBox/StopLabel
@onready var distance_label: Label = $TopCenter/VBox/GuideRow/DistanceLabel
@onready var turn_arrow: TurnArrow = $TopCenter/VBox/GuideRow/TurnArrow
@onready var time_label: Label = $TopRight/Grid/TimeLabel
@onready var score_label: Label = $TopRight/Grid/ScoreLabel
@onready var passengers_label: Label = $TopRight/Grid/PassengersLabel
@onready var damage_bar: ProgressBar = $TopRight/Grid/DamageBar
@onready var message_label: Label = $MessageLabel
@onready var countdown_label: Label = $Countdown

var _message_tween: Tween
var _time_warning := false


func _ready() -> void:
	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)


## Keeps the HUD out of the display cutout (camera notch) and rounded corners on phones:
## in immersive mode the game is drawn under the cutout, so the pause button, minimap and
## stats panel are pushed inside DisplayServer.get_display_safe_area().
func _apply_safe_area() -> void:
	if not OS.has_feature("mobile"):
		return
	var vp := get_viewport()
	if vp == null:
		return
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if safe.size.x <= 0 or safe.size.y <= 0 or win.x <= 0 or win.y <= 0:
		return
	var scale := vp.get_final_transform().get_scale()
	if scale.x <= 0.0 or scale.y <= 0.0:
		return
	# Insets in window pixels, converted to canvas units (canvas_items stretch = uniform scale).
	offset_left = maxi(safe.position.x, 0) / scale.x
	offset_top = maxi(safe.position.y, 0) / scale.y
	offset_right = -maxi(win.x - safe.end.x, 0) / scale.x
	offset_bottom = -maxi(win.y - safe.end.y, 0) / scale.y


func set_speed(kmh: float, limit: int, reversing: bool, doors_open: bool) -> void:
	speedometer.speed_kmh = kmh
	speedometer.speed_limit = limit
	speedometer.reversing = reversing
	speedometer.doors_open = doors_open


func set_stats(time_left: float, score: int, onboard: int, delivered: int, total: int, damage: float) -> void:
	var t := int(ceil(maxf(time_left, 0.0)))
	time_label.text = "%d:%02d" % [t / 60, t % 60]
	var low := time_left < 20.0
	time_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3) if low else Color.WHITE)
	if low and not _time_warning:
		_time_warning = true
		show_message(tr("MSG_TIME_LOW"), 1.5, Color(1.0, 0.5, 0.3))
	score_label.text = str(score)
	passengers_label.text = "%d / %d" % [onboard, total] if delivered == 0 else "%d / %d  (+%d)" % [onboard, total, delivered]
	damage_bar.value = damage


func set_next_stop(index: int, distance: float, is_terminal: bool, stops_total: int) -> void:
	if is_terminal:
		stop_label.text = tr("HUD_TERMINAL")
	else:
		stop_label.text = "%s %d / %d" % [tr("HUD_NEXT_STOP"), index + 1, stops_total]
	if turn_arrow == null:
		distance_label.text = "%d m" % int(distance)


## Turn-by-turn line under the stop name (see RouteGuide.guidance()).
func set_guidance(g: Dictionary) -> void:
	var turn: int = int(g.get("turn", RouteGuide.Turn.STRAIGHT))
	var dist := int(round(float(g.get("distance", 0.0))))
	turn_arrow.turn = turn
	var color := Color.WHITE
	match turn:
		RouteGuide.Turn.LEFT:
			distance_label.text = tr("GUIDE_TURN_LEFT") % dist
		RouteGuide.Turn.RIGHT:
			distance_label.text = tr("GUIDE_TURN_RIGHT") % dist
		RouteGuide.Turn.STOP:
			distance_label.text = tr("GUIDE_STOP") % dist if dist >= 3 else tr("GUIDE_AT_STOP")
			color = Color(1.0, 0.92, 0.6)
		RouteGuide.Turn.TERMINAL:
			distance_label.text = tr("GUIDE_TERMINAL") % dist
			color = Color(0.7, 1.0, 0.8)
		RouteGuide.Turn.OFF_ROUTE:
			distance_label.text = tr("GUIDE_OFF_ROUTE")
			color = Color(1.0, 0.65, 0.4)
		_:
			distance_label.text = tr("GUIDE_STRAIGHT") % dist
	distance_label.add_theme_color_override("font_color", color)


func show_message(text: String, duration: float = 2.0, color: Color = Color.WHITE) -> void:
	message_label.text = text
	message_label.add_theme_color_override("font_color", color)
	if _message_tween and _message_tween.is_valid():
		_message_tween.kill()
	message_label.modulate.a = 0.0
	message_label.scale = Vector2.ONE
	_message_tween = create_tween()
	_message_tween.tween_property(message_label, "modulate:a", 1.0, 0.15)
	_message_tween.tween_interval(duration)
	_message_tween.tween_property(message_label, "modulate:a", 0.0, 0.4)


func show_countdown(text: String, hold: float = 0.7) -> void:
	countdown_label.text = text
	countdown_label.visible = true
	countdown_label.scale = Vector2(1.6, 1.6)
	countdown_label.pivot_offset = countdown_label.size * 0.5
	countdown_label.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_property(countdown_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(hold)
	tween.tween_property(countdown_label, "modulate:a", 0.0, 0.2)
	tween.tween_callback(func() -> void: countdown_label.visible = false)


func flash_damage() -> void:
	var flash := ColorRect.new()
	flash.color = Color(1, 0.2, 0.15, 0.35)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	move_child(flash, 0)
	var tween := create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 0.45)
	tween.tween_callback(flash.queue_free)
