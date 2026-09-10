class_name Building
extends StaticBody3D

# Можно назначить свой материал в инспекторе; если пусто — возьмётся из сцены.
@export var base_material: StandardMaterial3D

# size — габариты здания, tint — оттенок из палитры (умножается на текстуру).
func setup(size: Vector3, tint: Color) -> void:
	var mesh_node := get_node("Mesh") as MeshInstance3D
	var col_node := get_node("Collision") as CollisionShape3D

	var box := BoxMesh.new()
	box.size = size
	mesh_node.mesh = box
	mesh_node.position = Vector3(0.0, size.y * 0.5, 0.0)

	var mat := base_material
	if mat == null and mesh_node.material_override is StandardMaterial3D:
		mat = mesh_node.material_override as StandardMaterial3D
	if mat != null:
		mat = mat.duplicate() as StandardMaterial3D
		#mat.albedo_color = tint
		mesh_node.material_override = mat

	var shape := BoxShape3D.new()
	shape.size = size
	col_node.shape = shape
	col_node.position = Vector3(0.0, size.y * 0.5, 0.0)