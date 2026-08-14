class_name CityGenerator
extends Node3D

@export var grid_count := 5
@export var spacing := 48.0
@export var road_width := 12.0
@export var building_min_height := 5.0
@export var building_max_height := 20.0
@export var random_seed := 2024

var road_coords := []


func _ready() -> void:
    if random_seed == 0:
        randomize()
    else:
        seed(random_seed)

    _build_city()


func get_bot_loop_min_max() -> Vector2:
    if road_coords.size() >= 4:
        return Vector2(float(road_coords[1]), float(road_coords[3]))

    if road_coords.size() >= 2:
        return Vector2(float(road_coords[0]), float(road_coords[-1]))

    return Vector2(-48.0, 48.0)


func _build_city() -> void:
    road_coords.clear()

    var half := (grid_count - 1) / 2.0
    for i in grid_count:
        road_coords.append((i - half) * spacing)

    _create_ground()
    _create_roads()
    _create_buildings()


func _create_ground() -> void:
    var size := (grid_count - 1) * spacing + road_width + 120.0

    var mesh := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(size, size)

    mesh.mesh = plane

    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.22, 0.45, 0.22)
    mesh.material_override = mat

    add_child(mesh)

    var body := StaticBody3D.new()
    var col := CollisionShape3D.new()
    var box := BoxShape3D.new()

    box.size = Vector3(size, 1.0, size)

    col.shape = box
    col.position = Vector3(0.0, -0.5, 0.0)

    body.add_child(col)
    add_child(body)


func _create_roads() -> void:
    var total_length := (grid_count - 1) * spacing + road_width + 60.0

    var road_material := StandardMaterial3D.new()
    road_material.albedo_color = Color(0.13, 0.13, 0.15)

    # Горизонтальные дороги.
    for z in road_coords:
        var road := MeshInstance3D.new()
        var plane := PlaneMesh.new()

        plane.size = Vector2(total_length, road_width)

        road.mesh = plane
        road.material_override = road_material
        road.position = Vector3(0.0, 0.01, float(z))

        add_child(road)

    # Вертикальные дороги.
    for x in road_coords:
        var road := MeshInstance3D.new()
        var plane := PlaneMesh.new()

        plane.size = Vector2(road_width, total_length)

        road.mesh = plane
        road.material_override = road_material
        road.position = Vector3(float(x), 0.02, 0.0)

        add_child(road)

    _create_lane_markings(total_length)


func _create_lane_markings(total_length: float) -> void:
    var line_material := StandardMaterial3D.new()
    line_material.albedo_color = Color(0.8, 0.8, 0.2)

    for z in road_coords:
        var line := MeshInstance3D.new()
        var plane := PlaneMesh.new()

        plane.size = Vector2(total_length, 0.25)

        line.mesh = plane
        line.material_override = line_material
        line.position = Vector3(0.0, 0.03, float(z))

        add_child(line)

    for x in road_coords:
        var line := MeshInstance3D.new()
        var plane := PlaneMesh.new()

        plane.size = Vector2(0.25, total_length)

        line.mesh = plane
        line.material_override = line_material
        line.position = Vector3(float(x), 0.04, 0.0)

        add_child(line)


func _create_buildings() -> void:
    for i in range(grid_count - 1):
        for j in range(grid_count - 1):
            var center_x := (float(road_coords[i]) + float(road_coords[i + 1])) / 2.0
            var center_z := (float(road_coords[j]) + float(road_coords[j + 1])) / 2.0

            var inner_size := spacing - road_width
            var margin := 4.0
            var max_size := inner_size - margin * 2.0

            if max_size < 8.0:
                continue

            var w := randf_range(8.0, max_size)
            var d := randf_range(8.0, max_size)
            var h := randf_range(building_min_height, building_max_height)

            _add_building(center_x, center_z, w, h, d)


func _add_building(x: float, z: float, w: float, h: float, d: float) -> void:
    var body := StaticBody3D.new()
    body.position = Vector3(x, 0.0, z)

    var mesh := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = Vector3(w, h, d)

    mesh.mesh = box
    mesh.position = Vector3(0.0, h / 2.0, 0.0)

    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(
        randf_range(0.35, 0.85),
        randf_range(0.35, 0.85),
        randf_range(0.35, 0.85)
    )
    mesh.material_override = mat

    var col := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(w, h, d)

    col.shape = shape
    col.position = Vector3(0.0, h / 2.0, 0.0)

    body.add_child(mesh)
    body.add_child(col)

    add_child(body)