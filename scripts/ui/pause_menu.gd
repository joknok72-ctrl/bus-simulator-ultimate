class_name PauseMenu
extends Control
## Pause overlay: resume, restart, quick settings toggles and back to menu.

signal resume_requested()
signal restart_requested()
signal menu_requested()

@onready var resume_button: Button = $Panel/VBox/Resume
@onready var restart_button: Button = $Panel/VBox/Restart
@onready var controls_button: Button = $Panel/VBox/Controls
@onready var sound_button: Button = $Panel/VBox/Sound
@onready var menu_button: Button = $Panel/VBox/Menu


func _ready() -> void:
	visible = false
	resume_button.pressed.connect(func() -> void:
		AudioSynth.play("click", -6.0)
		resume_requested.emit())
	restart_button.pressed.connect(func() -> void:
		AudioSynth.play("click", -6.0)
		restart_requested.emit())
	menu_button.pressed.connect(func() -> void:
		AudioSynth.play("click", -6.0)
		menu_requested.emit())
	controls_button.pressed.connect(_cycle_controls)
	sound_button.pressed.connect(_toggle_sound)


func open() -> void:
	_refresh()
	visible = true
	$Panel.scale = Vector2(0.85, 0.85)
	$Panel.pivot_offset = $Panel.size * 0.5
	var tween := create_tween()
	tween.tween_property($Panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close() -> void:
	visible = false


func _refresh() -> void:
	var mode := int(GameState.settings.control_mode)
	var names := ["CTRL_WHEEL", "CTRL_BUTTONS", "CTRL_TILT"]
	controls_button.text = "%s: %s" % [tr("SET_CONTROLS"), tr(names[mode])]
	sound_button.text = "%s: %s" % [tr("SET_SOUND"), tr("ON") if GameState.settings.sound else tr("OFF")]


func _cycle_controls() -> void:
	var mode := (int(GameState.settings.control_mode) + 1) % 3
	GameState.set_setting("control_mode", mode)
	AudioSynth.play("click", -6.0)
	_refresh()


func _toggle_sound() -> void:
	GameState.set_setting("sound", not GameState.settings.sound)
	AudioSynth.play("click", -6.0)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		resume_requested.emit()
		get_viewport().set_input_as_handled()
