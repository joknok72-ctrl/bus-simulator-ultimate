class_name MeshMerger
extends RefCounted
## Bakes many primitives into ONE ArrayMesh with one surface per material.
##
## Every MeshInstance3D is at least one draw call (two with shadows) on the mobile renderer,
## and everything in this game is assembled from primitives: the bus alone was ~120 mesh
## instances, the city ~250 and every traffic car ~14. Merging the static parts of a prop
## into a single mesh keeps the exact same look while cutting draw calls and scene-tree
## nodes by an order of magnitude, which is what keeps the frame rate up on phones.
##
## Usage:
##   var m := MeshMerger.new()
##   m.add_box(Vector3(2, 1, 1), Vector3(0, 0.5, 0), some_material)
##   m.add_cylinder(0.3, 2.0, Vector3(1, 1, 0), metal, Vector3(0, 0, PI * 0.5))
##   var mi := m.instance(parent, "Body")
##
## Vertex colours are always written (white by default); pass a colour to add()/add_box()
## together with MeshFactory.vertex_color_mat() to draw many differently coloured parts
## with a single surface (used for passengers).

var _groups: Dictionary = {}          # Material -> Dictionary of packed arrays
var _order: Array[Material] = []
var _vertex_count := 0


## Appends a primitive placed with `xform`. Normals follow the rotation; UVs are kept.
func add(primitive: PrimitiveMesh, xform: Transform3D, material: Material, color: Color = Color.WHITE) -> void:
	var arrays := primitive.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var g := _group(material)
	var base: int = g.verts.size()
	var normal_basis := xform.basis.inverse().transposed()
	var n := verts.size()
	var out_verts: PackedVector3Array = g.verts
	var out_normals: PackedVector3Array = g.normals
	var out_uvs: PackedVector2Array = g.uvs
	var out_colors: PackedColorArray = g.colors
	var out_indices: PackedInt32Array = g.indices
	out_verts.resize(base + n)
	out_normals.resize(base + n)
	out_uvs.resize(base + n)
	out_colors.resize(base + n)
	var has_uv := uvs.size() == n
	var has_normals := normals.size() == n
	for i in n:
		out_verts[base + i] = xform * verts[i]
		out_normals[base + i] = (normal_basis * normals[i]).normalized() if has_normals else Vector3.UP
		out_uvs[base + i] = uvs[i] if has_uv else Vector2.ZERO
		out_colors[base + i] = color
	var ib := out_indices.size()
	out_indices.resize(ib + indices.size())
	for i in indices.size():
		out_indices[ib + i] = indices[i] + base
	# Store back explicitly so this works whether packed arrays are shared or copied.
	g.verts = out_verts
	g.normals = out_normals
	g.uvs = out_uvs
	g.colors = out_colors
	g.indices = out_indices
	_vertex_count += n


func add_box(size: Vector3, pos: Vector3, material: Material, basis: Basis = Basis.IDENTITY, color: Color = Color.WHITE) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	add(mesh, Transform3D(basis, pos), material, color)


## rot is in radians (Euler XYZ), like Node3D.rotation.
func add_cylinder(radius: float, height: float, pos: Vector3, material: Material, rot: Vector3 = Vector3.ZERO,
		radial_segments: int = 16, color: Color = Color.WHITE, top_radius: float = -1.0) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = radial_segments
	mesh.rings = 0
	add(mesh, Transform3D(Basis.from_euler(rot), pos), material, color)


func add_sphere(radius: float, pos: Vector3, material: Material, segments: int = 12, color: Color = Color.WHITE, height: float = -1.0) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0 if height < 0.0 else height
	mesh.radial_segments = segments
	mesh.rings = maxi(3, int(segments / 2.0))
	add(mesh, Transform3D(Basis.IDENTITY, pos), material, color)


func add_plane(size: Vector2, pos: Vector3, material: Material, rot_y: float = 0.0) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = size
	add(mesh, Transform3D(Basis(Vector3.UP, rot_y), pos), material)


func is_empty() -> bool:
	return _order.is_empty()


func surface_count() -> int:
	return _order.size()


func vertex_count() -> int:
	return _vertex_count


## Builds the merged mesh (one surface per material, in insertion order).
func build() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for material in _order:
		var g: Dictionary = _groups[material]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g.verts
		arrays[Mesh.ARRAY_NORMAL] = g.normals
		arrays[Mesh.ARRAY_TEX_UV] = g.uvs
		arrays[Mesh.ARRAY_COLOR] = g.colors
		arrays[Mesh.ARRAY_INDEX] = g.indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh


## Builds the mesh and adds it to `parent` as a MeshInstance3D. Returns null when nothing was added.
func instance(parent: Node, node_name: String = "", pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	if is_empty():
		return null
	var mi := MeshInstance3D.new()
	if node_name != "":
		mi.name = node_name
	mi.mesh = build()
	mi.position = pos
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	parent.add_child(mi)
	return mi


func _group(material: Material) -> Dictionary:
	if _groups.has(material):
		return _groups[material]
	var g := {
		"verts": PackedVector3Array(),
		"normals": PackedVector3Array(),
		"uvs": PackedVector2Array(),
		"colors": PackedColorArray(),
		"indices": PackedInt32Array(),
	}
	_groups[material] = g
	_order.append(material)
	return g
