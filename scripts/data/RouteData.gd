class_name RouteData
extends RefCounted
## تعريف خطوط الباص. المدينة شبكة 5×5 تقاطعات (i, j) من 0..4، المسافة بين التقاطعات 80م.
## كل خط: مسار من التقاطعات + محطات على القطع (seg = رقم القطعة، t = موضعها 0..1).

const GRID_N := 5
const BLOCK := 80.0

const ROUTES := {
	"line1": {
		"name": "الخط ١ — وسط المدينة",
		"short": "خط ١",
		"unlock_level": 1,
		"time": "day",
		"weather": "clear",
		"speed_limit": 50,
		"bonus": 120,
		"path": [[1, 3], [1, 2], [2, 2], [3, 2], [3, 3], [2, 3], [1, 3]],
		"stops": [
			{"seg": 0, "t": 0.5, "name": "ميدان النور"},
			{"seg": 1, "t": 0.5, "name": "سوق المدينة"},
			{"seg": 3, "t": 0.5, "name": "حديقة الأزهار"},
			{"seg": 4, "t": 0.5, "name": "المحطة المركزية"},
		],
	},
	"line2": {
		"name": "الخط ٢ — الجامعة",
		"short": "خط ٢",
		"unlock_level": 2,
		"time": "day",
		"weather": "clear",
		"speed_limit": 50,
		"bonus": 200,
		"path": [[0, 4], [0, 3], [0, 2], [1, 2], [1, 1], [2, 1], [3, 1], [3, 2], [3, 3], [2, 3], [2, 4], [1, 4], [0, 4]],
		"stops": [
			{"seg": 0, "t": 0.5, "name": "البوابة الغربية"},
			{"seg": 2, "t": 0.5, "name": "شارع المعارف"},
			{"seg": 4, "t": 0.5, "name": "الجامعة — كلية الهندسة"},
			{"seg": 6, "t": 0.5, "name": "المكتبة الكبرى"},
			{"seg": 8, "t": 0.5, "name": "برج الساعة"},
			{"seg": 10, "t": 0.5, "name": "حي الفنانين"},
		],
	},
	"line3": {
		"name": "الخط ٣ — الكورنيش الليلي",
		"short": "خط ٣",
		"unlock_level": 3,
		"time": "night",
		"weather": "clear",
		"speed_limit": 50,
		"bonus": 300,
		"path": [[4, 0], [3, 0], [2, 0], [1, 0], [1, 1], [2, 1], [2, 2], [3, 2], [4, 2], [4, 1], [4, 0]],
		"stops": [
			{"seg": 0, "t": 0.5, "name": "الكورنيش — المنارة"},
			{"seg": 2, "t": 0.5, "name": "نادي البحر"},
			{"seg": 4, "t": 0.5, "name": "مطعم السمك"},
			{"seg": 6, "t": 0.5, "name": "ساحة الفنون"},
			{"seg": 8, "t": 0.5, "name": "الفندق الكبير"},
			{"seg": 9, "t": 0.5, "name": "المرسى القديم"},
		],
	},
	"line4": {
		"name": "الخط ٤ — المطار (مطر)",
		"short": "خط ٤",
		"unlock_level": 4,
		"time": "evening",
		"weather": "rain",
		"speed_limit": 60,
		"bonus": 450,
		"path": [[2, 4], [2, 3], [2, 2], [2, 1], [2, 0], [3, 0], [4, 0], [4, 1], [4, 2], [4, 3], [4, 4], [3, 4], [2, 4]],
		"stops": [
			{"seg": 0, "t": 0.5, "name": "الحي الجنوبي"},
			{"seg": 1, "t": 0.5, "name": "المستشفى العام"},
			{"seg": 3, "t": 0.5, "name": "مجمع المكاتب"},
			{"seg": 5, "t": 0.5, "name": "طريق المطار"},
			{"seg": 6, "t": 0.5, "name": "المطار — صالة ١"},
			{"seg": 8, "t": 0.5, "name": "المطار — الشحن"},
			{"seg": 10, "t": 0.5, "name": "منطقة الفنادق"},
			{"seg": 11, "t": 0.5, "name": "الحي الجنوبي — عودة"},
		],
	},
	"line5": {
		"name": "الخط ٥ — الدائري الكبير",
		"short": "خط ٥",
		"unlock_level": 5,
		"time": "day",
		"weather": "clear",
		"speed_limit": 60,
		"bonus": 650,
		"path": [[0, 0], [1, 0], [2, 0], [3, 0], [4, 0], [4, 1], [4, 2], [4, 3], [4, 4], [3, 4], [2, 4], [1, 4], [0, 4], [0, 3], [0, 2], [0, 1], [0, 0]],
		"stops": [
			{"seg": 0, "t": 0.5, "name": "الركن الشمالي"},
			{"seg": 2, "t": 0.5, "name": "الملعب الأولمبي"},
			{"seg": 4, "t": 0.5, "name": "المنطقة الصناعية"},
			{"seg": 6, "t": 0.5, "name": "المطار — صالة ٢"},
			{"seg": 8, "t": 0.5, "name": "الجسر الشرقي"},
			{"seg": 10, "t": 0.5, "name": "المنتزه الكبير"},
			{"seg": 12, "t": 0.5, "name": "البوابة الغربية"},
			{"seg": 14, "t": 0.5, "name": "المتحف الوطني"},
			{"seg": 15, "t": 0.5, "name": "الركن الشمالي — عودة"},
		],
	},
}

const ORDER := ["line1", "line2", "line3", "line4", "line5"]

static func get_route(id: String) -> Dictionary:
	return ROUTES.get(id, ROUTES["line1"])

static func grid_to_world(i: int, j: int) -> Vector3:
	return Vector3((i - 2) * BLOCK, 0.0, (j - 2) * BLOCK)

## يحسب موقع واتجاه نقطة على القطعة seg بنسبة t (الاتجاه = اتجاه الحركة)
static func point_on_segment(route: Dictionary, seg: int, t: float) -> Dictionary:
	var path: Array = route["path"]
	var a := grid_to_world(path[seg][0], path[seg][1])
	var b := grid_to_world(path[seg + 1][0], path[seg + 1][1])
	var dir := (b - a).normalized()
	return {"pos": a.lerp(b, t), "dir": dir}
