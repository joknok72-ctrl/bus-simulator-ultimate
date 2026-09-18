class_name BusData
extends RefCounted
## بيانات كل الباصات المتاحة في اللعبة.
## القاعدة التصميمية: الباص الأكبر = دخل أعلى لكن أثقل وأصعب اصطفافاً (التحدي يتطور مع المهارة).

const BUSES := {
	"mini": {
		"name": "ميني باص",
		"name_en": "Mini Bus",
		"price": 0,
		"capacity": 14,
		"length": 6.0,
		"width": 2.2,
		"height": 2.6,
		"mass": 3500.0,
		"engine_power": 220.0,
		"max_speed": 70.0,
		"brake_force": 45.0,
		"steer_angle": 0.62,
		"color": Color(0.95, 0.75, 0.15),
		"fare": 5,
		"unlock_level": 1,
	},
	"city": {
		"name": "باص المدينة",
		"name_en": "City Bus",
		"price": 1800,
		"capacity": 32,
		"length": 10.0,
		"width": 2.5,
		"height": 3.0,
		"mass": 9000.0,
		"engine_power": 420.0,
		"max_speed": 80.0,
		"brake_force": 80.0,
		"steer_angle": 0.55,
		"color": Color(0.16, 0.55, 0.85),
		"fare": 7,
		"unlock_level": 2,
	},
	"coach": {
		"name": "باص سياحي",
		"name_en": "Coach",
		"price": 5200,
		"capacity": 48,
		"length": 12.0,
		"width": 2.55,
		"height": 3.4,
		"mass": 13000.0,
		"engine_power": 620.0,
		"max_speed": 95.0,
		"brake_force": 115.0,
		"steer_angle": 0.5,
		"color": Color(0.85, 0.22, 0.25),
		"fare": 10,
		"unlock_level": 3,
	},
	"articulated": {
		"name": "باص مفصلي",
		"name_en": "Articulated",
		"price": 12000,
		"capacity": 80,
		"length": 16.0,
		"width": 2.55,
		"height": 3.2,
		"mass": 18000.0,
		"engine_power": 780.0,
		"max_speed": 85.0,
		"brake_force": 150.0,
		"steer_angle": 0.45,
		"color": Color(0.25, 0.7, 0.45),
		"fare": 12,
		"unlock_level": 5,
	},
}

## ترقيات قابلة للشراء لكل باص (تعمل على كل الباصات)
const UPGRADES := {
	"engine": {"name": "محرك أقوى", "icon": "⚙️", "base_price": 400, "max": 3, "desc": "+15% تسارع لكل مستوى"},
	"brakes": {"name": "فرامل محسّنة", "icon": "🛑", "base_price": 300, "max": 3, "desc": "+20% قوة فرامل"},
	"suspension": {"name": "تعليق مريح", "icon": "🪑", "base_price": 500, "max": 3, "desc": "الركاب يتحملون الانعطاف أكثر"},
	"seats": {"name": "مقاعد فاخرة", "icon": "💺", "base_price": 600, "max": 2, "desc": "+1 جنيه على كل تذكرة"},
}

static func get_bus(id: String) -> Dictionary:
	return BUSES.get(id, BUSES["mini"])

static func upgrade_price(upgrade_id: String, current_level: int) -> int:
	var u: Dictionary = UPGRADES[upgrade_id]
	return int(u["base_price"] * (1.0 + current_level * 0.8))
