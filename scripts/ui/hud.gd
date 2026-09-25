class_name Hud
extends Control
## In-game heads-up display: mission info, gauges, minimap, messages and the
## touch control layer.

@onready var touch_controls: TouchControls = $TouchControls
@onready var minimap: Minimap = $Minimap
@onready var speedometer: Speedometer = $Speedometer
@onready var stop_label: Label = $TopCenter/VBox/StopLabel
@onready var distance_label: Label = $TopCenter/VBox/DistanceLabel
@onready var time_label: Label = $TopRight/Grid/TimeLabel
@onready var score_label: Label = $TopRight/Grid/ScoreLabel
@onready var passengers_label: Label = $TopRight/Grid/PassengersLabel
@onready var damage_bar: ProgressBar = $TopRight/Grid/DamageBar
@onready var message_label: Label = $MessageLabel
@onready var countdown_label: Label = $Countdown

var _message_tween: Tween
var _time_warning := false


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
	distance_label.text = "%d m" % int(distance)


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
