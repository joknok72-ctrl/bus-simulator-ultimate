class_name BusStop
extends Node3D
## محطة الباص: مظلة + لافتة + منطقة اصطفاف (Perfect/Good/OK) + ركاب منتظرون.
## دقة الاصطفاف هي التحدي الصغير المتكرر في Core Loop.

signal bus_arrived(stop: BusStop)
signal bus_left(stop: BusStop)

var stop_name := ""
var index := 0
var waiting: Array[Node3D] = []
var waiting_count := 0
var is_active := false      # المحطة التالية المطلوبة
var served := false
var _marker: MeshInstance3D
var _marker_mat: StandardMaterial3D
var _arrow: MeshInstance3D
var _zone_len := 14.0
var _zone_w := 4.0
var _bus_inside := false
var _pulse := 0.0
var _people_root: Node3D
var _label: Label3D
var _mats: Dictionary = {}

func setup(p_name: String, p_index: int, p_waiting: int, night: bool) -> void:
	stop_name = p_name
	index = p_index
	waiting_count = p_waiting
	_build(night)
	_spawn_people(p_waiting)

func _flat(c: Color, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	return m

func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _build(night: bool) -> void:
	# المحطة تُوضع على الرصيف الأيمن؛ الباص يقف على الطريق بجانبها (محور -X المحلي = الطريق)
	var pole := _flat(Color(0.3, 0.32, 0.36), 0.4)
	var roof := _flat(Color(0.95, 0.35, 0.2), 0.6)
	var glass := _flat(Color(0.7, 0.85, 0.95, 0.5), 0.2)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# مظلة
	_box(Vector3(0.15, 2.6, 0.15), Vector3(1.2, 1.3, -1.8), pole)
	_box(Vector3(0.15, 2.6, 0.15), Vector3(1.2, 1.3, 1.8), pole)
	_box(Vector3(2.2, 0.12, 4.2), Vector3(0.8, 2.65, 0), roof)
	_box(Vector3(0.08, 2.0, 4.0), Vector3(1.9, 1.3, 0), glass)
	# مقعد
	_box(Vector3(0.5, 0.08, 3.0), Vector3(1.3, 0.55, 0), _flat(Color(0.55, 0.38, 0.22)))
	# لافتة المحطة
	_box(Vector3(0.1, 3.4, 0.1), Vector3(-0.6, 1.7, -2.6), pole)
	var sign_mat := _flat(Color(0.12, 0.45, 0.85), 0.4)
	_box(Vector3(0.08, 0.6, 0.9), Vector3(-0.6, 3.2, -2.6), sign_mat)
	_label = Label3D.new()
	_label.text = stop_name
	_label.font_size = 72
	_label.pixel_size = 0.012
	_label.position = Vector3(-0.4, 3.9, -2.6)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.outline_size = 12
	_label.modulate = Color(1, 1, 1)
	_label.outline_modulate = Color(0.05, 0.1, 0.25)
	add_child(_label)
	# منطقة التوقف على الطريق (مستطيل أرضي)
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.albedo_color = Color(1.0, 0.85, 0.2, 0.55)
	_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker_mat.emission_enabled = true
	_marker_mat.emission = Color(1.0, 0.7, 0.1)
	_marker_mat.emission_energy_multiplier = 0.6
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker = _box(Vector3(_zone_w, 0.04, _zone_len), Vector3(-5.0, 0.09, 0), _marker_mat)
	_marker.visible = false
	# سهم عائم يشير للمحطة التالية
	_arrow = MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(1.6, 1.4, 0.4)
	_arrow.mesh = prism
	var am := StandardMaterial3D.new()
	am.albedo_color = Color(1.0, 0.8, 0.15)
	am.emission_enabled = true
	am.emission = Color(1.0, 0.7, 0.1)
	am.emission_energy_multiplier = 1.5
	am.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arrow.material_override = am
	_arrow.position = Vector3(-5.0, 6.5, 0)
	_arrow.rotation_degrees = Vector3(180, 0, 0)
	_arrow.visible = false
	add_child(_arrow)
	if night:
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(0.8, 2.5, 0)
		lamp.omni_range = 9
		lamp.light_energy = 1.5
		lamp.light_color = Color(1, 0.9, 0.7)
		lamp.shadow_enabled = false
		add_child(lamp)
	# منطقة استشعار للباص
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(_zone_w + 3.0, 4.0, _zone_len + 6.0)
	cs.shape = bs
	cs.position = Vector3(-4.0, 2.0, 0)
	area.add_child(cs)
	area.body_entered.connect(_on_area_entered)
	area.body_exited.connect(_on_area_exited)
	add_child(area)

func _spawn_people(count: int) -> void:
	_people_root = Node3D.new()
	add_child(_people_root)
	var skin := _flat(Color(0.9, 0.75, 0.6))
	var colors := [Color(0.85, 0.3, 0.3), Color(0.3, 0.5, 0.85), Color(0.35, 0.7, 0.4), Color(0.9, 0.7, 0.2), Color(0.6, 0.4, 0.75), Color(0.2, 0.2, 0.25)]
	for i in range(count):
		var p := Node3D.new()
		var c: Color = colors[i % colors.size()]
		if not _mats.has(c):
			_mats[c] = _flat(c)
		_box(Vector3(0.4, 0.8, 0.28), Vector3(0, 0.95, 0), _mats[c], p)   # جسم
		_box(Vector3(0.26, 0.26, 0.26), Vector3(0, 1.5, 0), skin, p)       # رأس
		_box(Vector3(0.35, 0.55, 0.28), Vector3(0, 0.28, 0), _flat(Color(0.2, 0.22, 0.3)), p)  # أرجل
		p.position = Vector3(0.9 + randf_range(-0.3, 0.3), 0.25, -1.6 + i * (3.4 / max(count, 1)) + randf_range(-0.15, 0.15))
		p.rotation.y = -PI / 2 + randf_range(-0.3, 0.3)
		_people_root.add_child(p)
		waiting.append(p)

func set_active(active: bool) -> void:
	is_active = active
	_marker.visible = active
	_arrow.visible = active

func _process(delta: float) -> void:
	if not is_active:
		return
	_pulse += delta * 3.0
	_arrow.position.y = 6.5 + sin(_pulse) * 0.4
	_arrow.rotation.y += delta * 1.5
	_marker_mat.emission_energy_multiplier = 0.4 + (sin(_pulse * 1.5) + 1.0) * 0.4

func _on_area_entered(body: Node3D) -> void:
	if body is Bus:
		_bus_inside = true
		bus_arrived.emit(self)

func _on_area_exited(body: Node3D) -> void:
	if body is Bus:
		_bus_inside = false
		bus_left.emit(self)

## يحسب جودة الاصطفاف: 0 = خارج المنطقة، 1 = OK، 2 = Good، 3 = Perfect
func evaluate_parking(bus: Bus) -> Dictionary:
	var door_world := bus.door_position()
	var local := to_local(door_world)
	# الباب يجب أن يكون قريباً من الرصيف (x ≈ -1.0) وداخل طول المنطقة
	# الوضع المثالي: الباص في منتصف الحارة (local x = -5.0) فيكون بابه على بُعد ~1.1م ← local x ≈ -3.9
	var lateral := absf(local.x - (-3.9))
	var longitudinal := absf(local.z)
	# اتجاه الباص (+Z) يجب أن يوازي اتجاه المحطة (-Z المحلي = اتجاه الحركة)
	var bus_fwd := bus.global_transform.basis.z
	var stop_fwd := -global_transform.basis.z
	var angle := absf(Vector2(bus_fwd.x, bus_fwd.z).angle_to(Vector2(stop_fwd.x, stop_fwd.z)))
	var score := 0
	if longitudinal <= _zone_len * 0.5 + 2.0 and lateral <= 3.5:
		score = 1
		if lateral <= 1.3 and longitudinal <= 3.5 and angle < 0.25:
			score = 2
		if lateral <= 0.7 and longitudinal <= 1.8 and angle < 0.12:
			score = 3
	return {"score": score, "lateral": lateral, "longitudinal": longitudinal, "angle": angle}

## إنزال الركاب إلى الباص (أنيميشن بسيط: يختفون واحداً واحداً)
func board_all(on_each: Callable) -> void:
	var count := waiting.size()
	for i in range(count):
		var p := waiting[i]
		get_tree().create_timer(0.25 * i).timeout.connect(func():
			if is_instance_valid(p):
				var tw := create_tween()
				tw.tween_property(p, "position:x", -1.4, 0.35).set_ease(Tween.EASE_IN)
				tw.tween_property(p, "scale", Vector3(0.05, 0.05, 0.05), 0.15)
				tw.tween_callback(p.queue_free)
			on_each.call()
		)
	waiting.clear()
	waiting_count = 0
	served = true

func mark_served() -> void:
	served = true
	set_active(false)
	_label.modulate = Color(0.6, 0.9, 0.6)
