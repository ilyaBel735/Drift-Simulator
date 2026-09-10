class_name GrassPatch
extends MultiMeshInstance3D

@export var blade_width := 0.35
@export var blade_height := 0.6

# count — число кустиков, bmin/bmax — границы области (X и Z, локальные).
func generate(rng: RandomNumberGenerator, count: int, bmin: Vector2, bmax: Vector2) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _make_blade_mesh()
	mm.instance_count = count

	for i in count:
		var pos := Vector3(
			rng.randf_range(bmin.x, bmax.x),
			0.0,
			rng.randf_range(bmin.y, bmax.y)
		)
		var s := rng.randf_range(0.6, 1.4)
		var rot := rng.randf_range(0.0, TAU)
		var b := Basis(Vector3.UP, rot).scaled(Vector3(s, s, s))
		mm.set_instance_transform(i, Transform3D(b, pos))

	multimesh = mm

# Крестообразная травинка: две перпендикулярные плоскости.
func _make_blade_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var hw := blade_width * 0.5
	var h := blade_height

	_add_quad(st,
		Vector3(-hw, 0.0, 0.0), Vector2(0, 1),
		Vector3(hw, 0.0, 0.0), Vector2(1, 1),
		Vector3(hw, h, 0.0), Vector2(1, 0),
		Vector3(-hw, h, 0.0), Vector2(0, 0))

	_add_quad(st,
		Vector3(0.0, 0.0, -hw), Vector2(0, 1),
		Vector3(0.0, 0.0, hw), Vector2(1, 1),
		Vector3(0.0, h, hw), Vector2(1, 0),
		Vector3(0.0, h, -hw), Vector2(0, 0))

	st.generate_normals()
	return st.commit()

func _add_quad(
	st: SurfaceTool,
	p0: Vector3, uv0: Vector2,
	p1: Vector3, uv1: Vector2,
	p2: Vector3, uv2: Vector2,
	p3: Vector3, uv3: Vector2
) -> void:
	st.set_uv(uv0)
	st.add_vertex(p0)
	st.set_uv(uv1)
	st.add_vertex(p1)
	st.set_uv(uv2)
	st.add_vertex(p2)
	st.set_uv(uv0)
	st.add_vertex(p0)
	st.set_uv(uv2)
	st.add_vertex(p2)
	st.set_uv(uv3)
	st.add_vertex(p3)