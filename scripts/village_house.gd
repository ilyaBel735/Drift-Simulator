class_name VillageHouse
extends StaticBody3D

@export var wall_material: StandardMaterial3D

# size — габариты дома, tint — оттенок стен (крыша берётся из сцены).
func setup(size: Vector3, tint: Color) -> void:
	var mesh_node := get_node("Mesh") as MeshInstance3D
	var roof_node := get_node("Roof") as MeshInstance3D
	var col_node := get_node("Collision") as CollisionShape3D

	var box := BoxMesh.new()
	box.size = size
	mesh_node.mesh = box
	mesh_node.position = Vector3(0.0, size.y * 0.5, 0.0)

	var wall := wall_material
	if wall == null and mesh_node.material_override is StandardMaterial3D:
		wall = mesh_node.material_override as StandardMaterial3D
	if wall != null:
		wall = wall.duplicate() as StandardMaterial3D
		wall.albedo_color = tint
		mesh_node.material_override = wall

	var roof_height := minf(2.0, maxf(0.8, minf(size.x, size.z) * 0.35))
	roof_node.scale = Vector3(size.x * 1.15, roof_height, size.z * 1.15)
	roof_node.position = Vector3(0.0, size.y + roof_height * 0.5, 0.0)

	var shape := BoxShape3D.new()
	shape.size = size
	col_node.shape = shape
	col_node.position = Vector3(0.0, size.y * 0.5, 0.0)