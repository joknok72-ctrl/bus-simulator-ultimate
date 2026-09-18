extends Node
## الحالة العامة للعبة: المال، الخبرة، الباصات، الترقيات، الإعدادات، الحفظ/التحميل.
## Autoload: GameState

signal money_changed(amount: int, delta: int)
signal xp_changed(xp: int, level: int)
signal level_up(new_level: int)
signal settings_changed()

const SAVE_PATH := "user://save.json"
## الخبرة المطلوبة لكل مستوى (المستوى 1 يبدأ من 0)
const XP_TABLE := [0, 120, 320, 650, 1100, 1700, 2500, 3600, 5000, 7000, 9500, 12500]

var money: int = 300
var xp: int = 0
var level: int = 1
var owned_buses: Array = ["mini"]
var current_bus: String = "mini"
var upgrades: Dictionary = {"engine": 0, "brakes": 0, "suspension": 0, "seats": 0}
var stats: Dictionary = {
	"passengers": 0, "routes": 0, "distance_km": 0.0,
	"perfect_stops": 0, "fines": 0, "earned": 0, "collisions": 0,
}
var settings: Dictionary = {
	"sfx": 0.9, "music": 0.5, "haptics": true,
	"camera": 0, "shadows": true, "steer_sensitivity": 1.0,
}
## route_id -> {"best": int, "times": int}
var route_records: Dictionary = {}
## معرّف الخط المختار حالياً للانطلاق
var selected_route: String = "line1"
## وضع الاختبار الآلي (من سطر الأوامر)
var test_mode: bool = false

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	test_mode = "--test" in args or "--autopilot" in args
	load_game()

# ---------------------------------------------------------------- المال
func add_money(amount: int) -> void:
	if amount == 0:
		return
	money = max(0, money + amount)
	if amount > 0:
		stats["earned"] = int(stats["earned"]) + amount
	money_changed.emit(money, amount)

func can_afford(price: int) -> bool:
	return money >= price

func spend(price: int) -> bool:
	if not can_afford(price):
		return false
	add_money(-price)
	return true

# ---------------------------------------------------------------- الخبرة
func add_xp(amount: int) -> void:
	xp += amount
	var new_level := level_for_xp(xp)
	xp_changed.emit(xp, new_level)
	if new_level > level:
		level = new_level
		level_up.emit(level)
	save_game()

static func level_for_xp(value: int) -> int:
	var lvl := 1
	for i in range(XP_TABLE.size()):
		if value >= XP_TABLE[i]:
			lvl = i + 1
	return lvl

func xp_progress() -> Vector2:
	## يرجع (الخبرة الحالية داخل المستوى، الخبرة المطلوبة للمستوى التالي)
	var idx: int = clampi(level - 1, 0, XP_TABLE.size() - 1)
	var cur_base: int = XP_TABLE[idx]
	if idx + 1 >= XP_TABLE.size():
		return Vector2(1, 1)
	var next_base: int = XP_TABLE[idx + 1]
	return Vector2(xp - cur_base, next_base - cur_base)

# ---------------------------------------------------------------- الباصات
func owns_bus(id: String) -> bool:
	return id in owned_buses

func buy_bus(id: String) -> bool:
	var data := BusData.get_bus(id)
	if owns_bus(id) or level < int(data["unlock_level"]):
		return false
	if spend(int(data["price"])):
		owned_buses.append(id)
		current_bus = id
		save_game()
		return true
	return false

func select_bus(id: String) -> void:
	if owns_bus(id):
		current_bus = id
		save_game()

func buy_upgrade(id: String) -> bool:
	var lvl: int = int(upgrades.get(id, 0))
	var maxl: int = int(BusData.UPGRADES[id]["max"])
	if lvl >= maxl:
		return false
	if spend(BusData.upgrade_price(id, lvl)):
		upgrades[id] = lvl + 1
		save_game()
		return true
	return false

func upgrade_level(id: String) -> int:
	return int(upgrades.get(id, 0))

# ---------------------------------------------------------------- الخطوط
func record_route(route_id: String, score: int) -> void:
	var rec: Dictionary = route_records.get(route_id, {"best": 0, "times": 0})
	rec["best"] = max(int(rec["best"]), score)
	rec["times"] = int(rec["times"]) + 1
	route_records[route_id] = rec
	stats["routes"] = int(stats["routes"]) + 1
	save_game()

# ---------------------------------------------------------------- الإعدادات
func set_setting(key: String, value) -> void:
	settings[key] = value
	settings_changed.emit()
	save_game()

# ---------------------------------------------------------------- حفظ/تحميل
func save_game() -> void:
	var data := {
		"version": 1,
		"money": money, "xp": xp, "level": level,
		"owned_buses": owned_buses, "current_bus": current_bus,
		"upgrades": upgrades, "stats": stats, "settings": settings,
		"route_records": route_records, "selected_route": selected_route,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	money = int(d.get("money", money))
	xp = int(d.get("xp", xp))
	level = int(d.get("level", level_for_xp(xp)))
	owned_buses = d.get("owned_buses", owned_buses)
	current_bus = str(d.get("current_bus", current_bus))
	for k in upgrades.keys():
		upgrades[k] = int(d.get("upgrades", {}).get(k, 0))
	for k in stats.keys():
		if d.get("stats", {}).has(k):
			stats[k] = d["stats"][k]
	for k in settings.keys():
		if d.get("settings", {}).has(k):
			settings[k] = d["settings"][k]
	route_records = d.get("route_records", {})
	selected_route = str(d.get("selected_route", selected_route))

func reset_progress() -> void:
	money = 300
	xp = 0
	level = 1
	owned_buses = ["mini"]
	current_bus = "mini"
	for k in upgrades.keys():
		upgrades[k] = 0
	for k in stats.keys():
		stats[k] = 0 if typeof(stats[k]) == TYPE_INT else 0.0
	route_records = {}
	selected_route = "line1"
	save_game()
	money_changed.emit(money, 0)
	xp_changed.emit(xp, level)

static func fmt_money(v: int) -> String:
	## تنسيق الأرقام بفواصل الآلاف
	var s := str(absi(v))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if v < 0 else "") + out
