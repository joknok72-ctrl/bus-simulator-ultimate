extends Node
## اهتزاز الجهاز (Game Feel): ردود فعل لمسية للفرامل/الصدم/المكافآت.
## Autoload: Haptics

func light() -> void:
	_vibe(18)

func medium() -> void:
	_vibe(40)

func heavy() -> void:
	_vibe(90)

func _vibe(ms: int) -> void:
	if not bool(GameState.settings.get("haptics", true)):
		return
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)
