class_name PlanePiece
extends MeshInstance3D

# Базовый размер тайла текстуры в мировых единицах (метрах).
# Меняй это значение, чтобы сделать текстуры мельче или крупнее.
@export var texture_tile_size := 4.0 

func setup_size(new_size: Vector2) -> void:
	var plane := PlaneMesh.new()
	if mesh is PlaneMesh:
		plane = (mesh as PlaneMesh).duplicate() as PlaneMesh
	plane.size = new_size
	mesh = plane

	# Автоматически считаем UV, чтобы текстура не была растянута.
	if material_override is StandardMaterial3D:
		# Дублируем материал, чтобы изменение UV не ломало другие объекты
		var mat := (material_override as StandardMaterial3D).duplicate()
		
		# Считаем, сколько раз текстура должна повториться по X и по Y
		var repeat_x := new_size.x / texture_tile_size
		var repeat_y := new_size.y / texture_tile_size
		
		mat.uv1_scale = Vector3(repeat_x, repeat_y, 1.0)
		material_override = mat