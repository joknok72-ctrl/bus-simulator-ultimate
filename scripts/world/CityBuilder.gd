class_name CityBuilder
extends Node3D
## يبني المدينة برمجياً: شبكة طرق 5×5، أرصفة، مبانٍ باستيل، أشجار، إشارات مرور، وأعمدة إنارة.
## للأداء: MultiMesh للمباني والأشجار، ومواد مشتركة.

const BLOCK := RouteData.BLOCK
const N := RouteData.GRID_N
const ROAD_W := 14.0     # عرض الطريق الكلي (حارتان + رصيف)
const SIDEWALK_W := 3.0
const LANE_OFFSET := 3.2  # مركز الحارة اليمنى من منتصف الطريق

var mat_road: StandardMaterial3D
var mat_sidewalk: StandardMaterial3D
var mat_grass: StandardMaterial3D
var mat_line: StandardMaterial3D
var mat_tree_trunk: StandardMaterial3D
var mat_tree_leaf: StandardMaterial3D
var building_mats: Array[StandardMaterial3D] = []
var night := false
var _rng := RandomNumberGenerator.new()

func build(is_night: bool) -> void:
	night = is_night
	_rng.seed = 1337
	_setup_materials()
	_build_ground()
	_build_roads()
	_build_blocks()
	_build_boundary()

func _flat(color: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = 0.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	if night:
		m.albedo_color = color.darkened(0.35)
	return m

func _setup_materials() -> void:
	mat_road = _flat(Color(0.22, 0.23, 0.26))
	mat_sidewalk = _flat(Color(0.78, 0.76, 0.70))
	mat_grass = _flat(Color(0.45, 0.68, 0.32))
	mat_line = _flat(Color(0.95, 0.92, 0.75))
	mat_tree_trunk = _flat(Color(0.42, 0.28, 0.16))
	mat_tree_leaf = _flat(Color(0.25, 0.55, 0.28))
	var palette := [
		Color(0.93, 0.80, 0.70), Color(0.80, 0.86, 0.94), Color(0.94, 0.88, 0.66),
		Color(0.84, 0.76, 0.90), Color(0.75, 0.88, 0.82), Color(0.96, 0.72, 0.66),
		Color(0.88, 0.88, 0.90), Color(0.70, 0.78, 0.86),
	]
	for c in palette:
		building_mats.append(_flat(c, 0.85))

func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _build_ground() -> void:
	var size := BLOCK * (N + 2)
	var g := _box(Vector3(size, 0.2, size), Vector3(0, -0.1, 0), mat_grass)
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(size, 0.2, size)
	shape.shape = bs
	body.add_child(shape)
	body.position = Vector3(0, -0.1, 0)
	body.collision_layer = 1
	add_child(body)

func _build_roads() -> void:
	var total := BLOCK * (N - 1) + ROAD_W
	var roads := Node3D.new()
	roads.name = "Roads"
	add_child(roads)
	# طرق أفقية (على محور X) وعمودية (على محور Z)
	for k in range(N):
		var c := (k - 2) * BLOCK
		var h := _box(Vector3(total, 0.05, ROAD_W), Vector3(0, 0.03, c), mat_road, roads)
		h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var v := _box(Vector3(ROAD_W, 0.05, total), Vector3(c, 0.03, 0), mat_road, roads)
		v.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# خطوط منتصف متقطعة
	var lines := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var lm := BoxMesh.new()
	lm.size = Vector3(3.0, 0.02, 0.25)
	mm.mesh = lm
	var xforms: Array[Transform3D] = []
	for k in range(N):
		var c := (k - 2) * BLOCK
		for s in range(N - 1):
			var start := (s - 2) * BLOCK + ROAD_W * 0.5 + 2.0
			var end := (s - 1) * BLOCK - ROAD_W * 0.5 - 2.0
			var x := start
			while x < end:
				xforms.append(Transform3D(Basis.IDENTITY, Vector3(x + 1.5, 0.065, c)))
				xforms.append(Transform3D(Basis(Vector3.UP, PI / 2), Vector3(c, 0.065, x + 1.5)))
				x += 6.0
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
	lines.multimesh = mm
	lines.material_override = mat_line
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	roads.add_child(lines)
	# أرصفة عند حواف كل بلوك
	for i in range(N - 1):
		for j in range(N - 1):
			var cx := (i - 2) * BLOCK + BLOCK * 0.5
			var cz := (j - 2) * BLOCK + BLOCK * 0.5
			var inner := BLOCK - ROAD_W
			var sw := _box(Vector3(inner, 0.25, inner), Vector3(cx, 0.12, cz), mat_sidewalk, roads)
			sw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# جسم تصادم للرصيف حتى لا يخرج الباص عن الطريق بسهولة (منخفض ليمكن تجاوزه بحذر)
			var sb := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(inner, 0.25, inner)
			cs.shape = bs
			sb.add_child(cs)
			sb.position = Vector3(cx, 0.12, cz)
			roads.add_child(sb)

func _build_blocks() -> void:
	var buildings := Node3D.new()
	buildings.name = "Buildings"
	add_child(buildings)
	var inner := BLOCK - ROAD_W - SIDEWALK_W * 2.0
	# مبانٍ: MultiMesh لكل لون
	var per_mat: Array = []
	for m in building_mats:
		per_mat.append([])
	var trees: Array[Transform3D] = []
	var collision_root := StaticBody3D.new()
	collision_root.name = "BuildingCollision"
	buildings.add_child(collision_root)
	for i in range(N - 1):
		for j in range(N - 1):
			var cx := (i - 2) * BLOCK + BLOCK * 0.5
			var cz := (j - 2) * BLOCK + BLOCK * 0.5
			var kind := _rng.randi_range(0, 9)
			if kind == 0:
				# حديقة: أشجار فقط
				for k in range(12):
					var tx := cx + _rng.randf_range(-inner * 0.45, inner * 0.45)
					var tz := cz + _rng.randf_range(-inner * 0.45, inner * 0.45)
					trees.append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * _rng.randf_range(0.8, 1.3)), Vector3(tx, 0.25, tz)))
				continue
			# شبكة 2×2 أو 3×3 مبانٍ داخل البلوك
			var cells := 2 if _rng.randf() < 0.6 else 3
			var cell := inner / cells
			for a in range(cells):
				for b in range(cells):
					if _rng.randf() < 0.12:
						continue
					var w := cell * _rng.randf_range(0.6, 0.85)
					var d := cell * _rng.randf_range(0.6, 0.85)
					var h := _rng.randf_range(6.0, 22.0)
					if (i == 2 or j == 2) and _rng.randf() < 0.4:
						h = _rng.randf_range(18.0, 40.0)  # وسط المدينة أعلى
					var bx := cx - inner * 0.5 + cell * (a + 0.5)
					var bz := cz - inner * 0.5 + cell * (b + 0.5)
					var mi := _rng.randi_range(0, building_mats.size() - 1)
					var xf := Transform3D(Basis.IDENTITY.scaled(Vector3(w, h, d)), Vector3(bx, 0.25 + h * 0.5, bz))
					per_mat[mi].append(xf)
					var cs := CollisionShape3D.new()
					var bs := BoxShape3D.new()
					bs.size = Vector3(w, h, d)
					cs.shape = bs
					cs.position = Vector3(bx, 0.25 + h * 0.5, bz)
					collision_root.add_child(cs)
			# أشجار على حواف الرصيف
			for k in range(4):
				var ang := k * PI * 0.5 + PI * 0.25
				var r := (BLOCK - ROAD_W) * 0.5 - SIDEWALK_W * 0.5
				trees.append(Transform3D(Basis.IDENTITY, Vector3(cx + cos(ang) * r, 0.25, cz + sin(ang) * r)))
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	for mi in range(building_mats.size()):
		var arr: Array = per_mat[mi]
		if arr.is_empty():
			continue
		var mmi := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = unit
		mm.instance_count = arr.size()
		for k in range(arr.size()):
			mm.set_instance_transform(k, arr[k])
		mmi.multimesh = mm
		mmi.material_override = building_mats[mi]
		buildings.add_child(mmi)
	_build_trees(trees, buildings)
	_build_lamps(buildings)

func _build_trees(xforms: Array[Transform3D], parent: Node) -> void:
	if xforms.is_empty():
		return
	var trunk := MultiMeshInstance3D.new()
	var tmm := MultiMesh.new()
	tmm.transform_format = MultiMesh.TRANSFORM_3D
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.25
	cyl.bottom_radius = 0.35
	cyl.height = 2.5
	cyl.radial_segments = 6
	tmm.mesh = cyl
	tmm.instance_count = xforms.size()
	var leaf := MultiMeshInstance3D.new()
	var lmm := MultiMesh.new()
	lmm.transform_format = MultiMesh.TRANSFORM_3D
	var sph := SphereMesh.new()
	sph.radius = 1.8
	sph.height = 3.6
	sph.radial_segments = 8
	sph.rings = 4
	lmm.mesh = sph
	lmm.instance_count = xforms.size()
	for i in range(xforms.size()):
		var xf := xforms[i]
		tmm.set_instance_transform(i, Transform3D(xf.basis, xf.origin + Vector3(0, 1.25 * xf.basis.get_scale().y, 0)))
		lmm.set_instance_transform(i, Transform3D(xf.basis, xf.origin + Vector3(0, 3.6 * xf.basis.get_scale().y, 0)))
	trunk.multimesh = tmm
	trunk.material_override = mat_tree_trunk
	leaf.multimesh = lmm
	leaf.material_override = mat_tree_leaf
	parent.add_child(trunk)
	parent.add_child(leaf)

func _build_lamps(parent: Node) -> void:
	var lamps := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var pole := CylinderMesh.new()
	pole.top_radius = 0.08
	pole.bottom_radius = 0.12
	pole.height = 6.0
	pole.radial_segments = 5
	mm.mesh = pole
	var xf: Array[Transform3D] = []
	for k in range(N):
		var c := (k - 2) * BLOCK
		for s in range(-2, 3):
			for off in [-1.0, 1.0]:
				var p := s * BLOCK + BLOCK * 0.25 * off
				xf.append(Transform3D(Basis.IDENTITY, Vector3(p, 3.25, c + (ROAD_W * 0.5 + 0.6) * off)))
	mm.instance_count = xf.size()
	for i in range(xf.size()):
		mm.set_instance_transform(i, xf[i])
	lamps.multimesh = mm
	lamps.material_override = _flat(Color(0.35, 0.36, 0.4), 0.5)
	parent.add_child(lamps)
	if night:
		# أضواء مصابيح (كرات مضيئة) — بلا مصادر إضاءة حقيقية للحفاظ على الأداء
		var glow := MultiMeshInstance3D.new()
		var gmm := MultiMesh.new()
		gmm.transform_format = MultiMesh.TRANSFORM_3D
		var s := SphereMesh.new()
		s.radius = 0.35
		s.height = 0.7
		s.radial_segments = 6
		s.rings = 3
		gmm.mesh = s
		gmm.instance_count = xf.size()
		for i in range(xf.size()):
			gmm.set_instance_transform(i, Transform3D(Basis.IDENTITY, xf[i].origin + Vector3(0, 3.1, 0)))
		glow.multimesh = gmm
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(1.0, 0.9, 0.6)
		gm.emission_enabled = true
		gm.emission = Color(1.0, 0.85, 0.5)
		gm.emission_energy_multiplier = 3.0
		glow.material_override = gm
		parent.add_child(glow)

func _build_boundary() -> void:
	# جدران غير مرئية حول المدينة
	var size := BLOCK * (N - 1) + ROAD_W + 4.0
	var body := StaticBody3D.new()
	for k in range(4):
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		var horizontal := k < 2
		bs.size = Vector3(size, 10, 1) if horizontal else Vector3(1, 10, size)
		cs.shape = bs
		var sign := -1.0 if k % 2 == 0 else 1.0
		cs.position = Vector3(0, 5, sign * size * 0.5) if horizontal else Vector3(sign * size * 0.5, 5, 0)
		body.add_child(cs)
	add_child(body)
