class_name MeshFactory
extends RefCounted
## Small helpers to build primitive-based props in code. Everything visual in the
## game (bus, cars, buildings, props) is assembled from Godot primitives, so the
## project has no external 3D assets.

static var _material_cache: Dictionary = {}


## Returns a cached StandardMaterial3D for a plain colour.
static func mat(color: Color, roughness: float = 0.8, metallic: float = 0.0, emission: Color = Color.BLACK, emission_energy: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%s|%.2f" % [color.to_html(), roughness, metallic, emission.to_html(), emission_energy]
	if _material_cache.has(key):
		return _material_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	_material_cache[key] = m
	return m


## Shared material whose albedo comes from the mesh vertex colours. Together with
## MeshMerger this draws a prop made of many differently coloured parts in ONE draw call.
static func vertex_color_mat(roughness: float = 0.8) -> StandardMaterial3D:
	var key := "vcol|%.2f" % roughness
	if _material_cache.has(key):
		return _material_cache[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = roughness
	_material_cache[key] = m
	return m


## Tinted glass. Lower metallic/higher roughness gives glass that is looked *through* at grazing
## angles (cabin windows) instead of mirroring the sky.
static func glass_mat(color: Color = Color(0.25, 0.4, 0.55, 0.65), metallic: float = 0.3, roughness: float = 0.1) -> StandardMaterial3D:
	var key := "glass|%s|%.2f|%.2f" % [color.to_html(), metallic, roughness]
	if _material_cache.has(key):
		return _material_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = roughness
	m.metallic = metallic
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material_cache[key] = m
	return m


static func box(parent: Node, size: Vector3, pos: Vector3, material: Material, rot_y_deg: float = 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	if rot_y_deg != 0.0:
		mi.rotation.y = deg_to_rad(rot_y_deg)
	parent.add_child(mi)
	return mi


static func cylinder(parent: Node, radius: float, height: float, pos: Vector3, material: Material, rot: Vector3 = Vector3.ZERO, radial_segments: int = 16) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = radial_segments
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func sphere(parent: Node, radius: float, pos: Vector3, material: Material, segments: int = 12) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = maxi(4, segments / 2)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	parent.add_child(mi)
	return mi


static func plane(parent: Node, size: Vector2, pos: Vector3, material: Material, rot_y_deg: float = 0.0) -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation.y = deg_to_rad(rot_y_deg)
	parent.add_child(mi)
	return mi


static func static_box(parent: Node, size: Vector3, pos: Vector3, layer: int = 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.position = pos
	parent.add_child(body)
	return body


## Appends a primitive's geometry (offset and scaled) as a new surface of an ArrayMesh.
static func append_surface(target: ArrayMesh, primitive: PrimitiveMesh, offset: Vector3, material: Material) -> void:
	var arrays := primitive.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i] = verts[i] + offset
	arrays[Mesh.ARRAY_VERTEX] = verts
	target.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	target.surface_set_material(target.get_surface_count() - 1, material)


## Builds a low-poly tree mesh (trunk + crown) usable in a MultiMesh.
static func tree_mesh(crown_color: Color) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16
	trunk.bottom_radius = 0.24
	trunk.height = 2.4
	trunk.radial_segments = 6
	append_surface(mesh, trunk, Vector3(0, 1.2, 0), mat(Color(0.36, 0.25, 0.15), 0.95))
	var crown := SphereMesh.new()
	crown.radius = 1.5
	crown.height = 3.0
	crown.radial_segments = 8
	crown.rings = 5
	append_surface(mesh, crown, Vector3(0, 3.3, 0), mat(crown_color, 0.9))
	return mesh


## Builds a street lamp mesh (pole + head). The head glows at night.
static func lamp_mesh(night: bool) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var pole := CylinderMesh.new()
	pole.top_radius = 0.07
	pole.bottom_radius = 0.1
	pole.height = 5.2
	pole.radial_segments = 6
	append_surface(mesh, pole, Vector3(0, 2.6, 0), mat(Color(0.3, 0.32, 0.35), 0.5, 0.6))
	var arm := BoxMesh.new()
	arm.size = Vector3(0.12, 0.12, 1.4)
	append_surface(mesh, arm, Vector3(0, 5.2, -0.6), mat(Color(0.3, 0.32, 0.35), 0.5, 0.6))
	var head := BoxMesh.new()
	head.size = Vector3(0.5, 0.2, 0.9)
	var head_mat := mat(Color(1.0, 0.95, 0.8), 0.3, 0.0, Color(1.0, 0.9, 0.6), 3.0) if night else mat(Color(0.85, 0.85, 0.85), 0.4)
	append_surface(mesh, head, Vector3(0, 5.15, -1.3), head_mat)
	return mesh
