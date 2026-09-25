class_name ResultsPanel
extends Control
## End-of-route summary with stars, score breakdown and navigation buttons.

signal retry_requested()
signal menu_requested()
signal next_requested()

@onready var title_label: Label = $Panel/VBox/Title
@onready var stars: StarsDisplay = $Panel/VBox/Stars
@onready var grid: GridContainer = $Panel/VBox/Grid
@onready var best_label: Label = $Panel/VBox/BestLabel
@onready var retry_button: Button = $Panel/VBox/Buttons/Retry
@onready var next_button: Button = $Panel/VBox/Buttons/Next
@onready var menu_button: Button = $Panel/VBox/Buttons/Menu


func _ready() -> void:
	visible = false
	retry_button.pressed.connect(func() -> void:
		AudioSynth.play("click", -6.0)
		retry_requested.emit())
	next_button.pressed.connect(func() -> void:
		AudioSynth.play("click", -6.0)
		next_requested.emit())
	menu_button.pressed.connect(func() -> void:
		AudioSynth.play("click", -6.0)
		menu_requested.emit())


func show_results(result: Dictionary) -> void:
	var success: bool = result.get("success", false)
	title_label.text = tr(String(result.get("title_key", "RESULT_COMPLETE")))
	title_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6) if success else Color(1.0, 0.5, 0.45))
	for child in grid.get_children():
		child.queue_free()
	_add_row(tr("RESULT_PASSENGERS"), "%d / %d" % [int(result.get("delivered", 0)), int(result.get("total_passengers", 0))])
	_add_row(tr("RESULT_STOPS"), "%d / %d" % [int(result.get("stops_served", 0)), int(result.get("stops_total", 0))])
	_add_row(tr("RESULT_COLLISIONS"), str(int(result.get("collisions", 0))))
	_add_row(tr("RESULT_TIME_BONUS"), "+%d" % int(result.get("time_bonus", 0)))
	_add_row(tr("RESULT_TOTAL"), str(int(result.get("total", 0))), true)
	_add_row(tr("RESULT_COINS"), "+%d" % int(result.get("coins", 0)))
	best_label.visible = bool(result.get("new_best", false))
	var next_id := RouteData.next_route_id(String(result.get("route_id", "")))
	var next_route := RouteData.get_route(next_id) if next_id != "" else {}
	next_button.visible = success and next_id != "" and GameState.is_route_unlocked(next_route)
	visible = true
	stars.set_stars(int(result.get("stars", 0)), true)
	$Panel.pivot_offset = $Panel.size * 0.5
	$Panel.scale = Vector2(0.8, 0.8)
	var tween := create_tween()
	tween.tween_property($Panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _add_row(title: String, value: String, highlight: bool = false) -> void:
	var a := Label.new()
	a.text = title
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b := Label.new()
	b.text = value
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if highlight:
		a.theme_type_variation = &"HudValue"
		b.theme_type_variation = &"HudValue"
		b.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	grid.add_child(a)
	grid.add_child(b)
