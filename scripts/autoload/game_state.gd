extends Node
## Global game state (autoload "GameState").
## Holds player settings, progression (stars, coins, unlocked liveries), the currently
## selected route and the last mission result. Everything is persisted to user://save.cfg.

signal coins_changed(coins: int)
signal settings_changed()

const SAVE_PATH := "user://save.cfg"
const SAVE_VERSION := 1

enum ControlMode { WHEEL, BUTTONS, TILT }
enum CameraMode { CHASE, DRIVER, TOP }
enum SteerSensitivity { LOW, NORMAL, HIGH }

## Bus liveries that can be unlocked with coins in the garage.
const BUS_COLORS: Array[Dictionary] = [
	{"id": "red", "name": "COLOR_RED", "color": Color(0.85, 0.16, 0.14), "price": 0},
	{"id": "blue", "name": "COLOR_BLUE", "color": Color(0.12, 0.42, 0.85), "price": 300},
	{"id": "green", "name": "COLOR_GREEN", "color": Color(0.16, 0.6, 0.32), "price": 300},
	{"id": "yellow", "name": "COLOR_YELLOW", "color": Color(0.96, 0.78, 0.12), "price": 500},
	{"id": "white", "name": "COLOR_WHITE", "color": Color(0.92, 0.93, 0.95), "price": 500},
	{"id": "purple", "name": "COLOR_PURPLE", "color": Color(0.5, 0.2, 0.7), "price": 800},
]

var settings: Dictionary = {
	"language": "",
	"control_mode": ControlMode.WHEEL,
	"sound": true,
	"vibration": true,
	"quality": 1,
	"camera": CameraMode.CHASE,
	"invert_tilt": false,
	"steer_sensitivity": SteerSensitivity.NORMAL,
}

var progress: Dictionary = {
	"coins": 0,
	"stars": {},
	"best": {},
	"unlocked_colors": ["red"],
	"bus_color": "red",
}

## Route chosen in the route selection screen; read by the game scene.
var selected_route_id: String = "route_1"
## Result of the last mission, shown by the results panel.
var last_result: Dictionary = {}

var _fader: ColorRect


func _ready() -> void:
	# The Android back button must not kill the app: the game scene pauses and the main
	# menu steps back one page instead (both handle NOTIFICATION_WM_GO_BACK_REQUEST).
	get_tree().quit_on_go_back = false
	load_game()
	if String(settings.language).is_empty():
		var lang := OS.get_locale_language()
		settings.language = "ar" if lang == "ar" else "en"
	apply_language()
	_setup_fader()


# ---------------------------------------------------------------- persistence
func load_game() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for key in settings.keys():
		settings[key] = cfg.get_value("settings", key, settings[key])
	for key in progress.keys():
		progress[key] = cfg.get_value("progress", key, progress[key])
	# Defensive: make sure required containers exist even after a corrupted save.
	if not (progress.stars is Dictionary):
		progress.stars = {}
	if not (progress.best is Dictionary):
		progress.best = {}
	if not (progress.unlocked_colors is Array) or progress.unlocked_colors.is_empty():
		progress.unlocked_colors = ["red"]


func save_game() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", SAVE_VERSION)
	for key in settings.keys():
		cfg.set_value("settings", key, settings[key])
	for key in progress.keys():
		cfg.set_value("progress", key, progress[key])
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("Could not save game: %s" % error_string(err))


func reset_progress() -> void:
	progress = {
		"coins": 0,
		"stars": {},
		"best": {},
		"unlocked_colors": ["red"],
		"bus_color": "red",
	}
	save_game()
	coins_changed.emit(0)


# ---------------------------------------------------------------- settings
func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	if key == "language":
		apply_language()
	save_game()
	settings_changed.emit()


func apply_language() -> void:
	TranslationServer.set_locale(String(settings.language))


## How far the touch wheel has to be turned (and how quickly buttons / tilt steer):
## 0 = low (more precise), 1 = normal, 2 = high (less thumb travel).
func steer_sensitivity() -> int:
	return clampi(int(settings.get("steer_sensitivity", SteerSensitivity.NORMAL)), 0, 2)


func is_arabic() -> bool:
	return String(settings.language) == "ar"


func toggle_language() -> void:
	set_setting("language", "en" if is_arabic() else "ar")


# ---------------------------------------------------------------- progression
func total_stars() -> int:
	var total := 0
	for route_id in progress.stars.keys():
		total += int(progress.stars[route_id])
	return total


func get_route_stars(route_id: String) -> int:
	return int(progress.stars.get(route_id, 0))


func get_route_best(route_id: String) -> int:
	return int(progress.best.get(route_id, 0))


func is_route_unlocked(route: Dictionary) -> bool:
	return total_stars() >= int(route.get("stars_required", 0))


## Stores a finished mission. Returns true when the score is a new best.
func record_result(route_id: String, score: int, stars: int, coins: int) -> bool:
	var new_best := score > get_route_best(route_id)
	if new_best:
		progress.best[route_id] = score
	if stars > get_route_stars(route_id):
		progress.stars[route_id] = stars
	add_coins(coins)
	save_game()
	return new_best


func add_coins(amount: int) -> void:
	progress.coins = int(progress.coins) + amount
	coins_changed.emit(int(progress.coins))


func get_coins() -> int:
	return int(progress.coins)


# ---------------------------------------------------------------- garage
func get_bus_color() -> Color:
	for entry in BUS_COLORS:
		if entry.id == progress.bus_color:
			return entry.color
	return BUS_COLORS[0].color


func is_color_unlocked(color_id: String) -> bool:
	return progress.unlocked_colors.has(color_id)


func try_buy_color(color_id: String) -> bool:
	for entry in BUS_COLORS:
		if entry.id == color_id:
			if is_color_unlocked(color_id):
				return true
			if get_coins() >= int(entry.price):
				add_coins(-int(entry.price))
				progress.unlocked_colors.append(color_id)
				save_game()
				return true
			return false
	return false


func select_color(color_id: String) -> void:
	if is_color_unlocked(color_id):
		progress.bus_color = color_id
		save_game()


# ---------------------------------------------------------------- scene transitions
func _setup_fader() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fader = ColorRect.new()
	_fader.color = Color(0.03, 0.04, 0.07, 1.0)
	_fader.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fader.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fader.modulate.a = 0.0
	layer.add_child(_fader)


## Fades to black, switches scene and fades back in.
func change_scene(path: String) -> void:
	get_tree().paused = false
	if _fader == null:
		get_tree().change_scene_to_file(path)
		return
	_fader.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.tween_property(_fader, "modulate:a", 1.0, 0.25)
	await tween.finished
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	var tween_in := create_tween()
	tween_in.tween_property(_fader, "modulate:a", 0.0, 0.3)
	await tween_in.finished
	_fader.mouse_filter = Control.MOUSE_FILTER_IGNORE


func vibrate(ms: int) -> void:
	if settings.vibration:
		Input.vibrate_handheld(ms)
