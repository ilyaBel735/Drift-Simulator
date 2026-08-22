class_name CityGenerator
extends Node3D

@export var spacing := 48.0
@export var road_width := 12.0
@export var building_margin := 4.0
@export var building_min_height := 5.0
@export var building_max_height := 20.0
@export var random_seed := 2024
@export var lane_markings := true
@export var traffic_lights := true

# Радиус генерации вокруг игрока.
@export var view_radius := 3

# Радиус, за которым чанки удаляются.
@export var unload_radius := 5

# Держать загруженной стартовую зону вокруг нуля.
@export var origin_radius := 2
@export var keep_origin_loaded := true

# Как часто проверять, нужно ли подгружать новые чанки.
@export var update_interval := 0.4

var target: Node3D

var chunks := {}
var last_center_chunk := Vector2i.ZERO
var initialized := false
var update_timer := 0.0

var ground_mesh: PlaneMesh
var road_h_mesh: PlaneMesh
var road_v_mesh: PlaneMesh
var line_h_mesh: PlaneMesh
var line_v_mesh: PlaneMesh

var ground_material: StandardMaterial3D
var road_material: StandardMaterial3D
var line_material: StandardMaterial3D
var building_materials := []

var light_meshes := {}
var light_materials := {}


func _ready() -> void:
    if random_seed == 0:
        randomize()
        random_seed = randi()

    _setup_resources()
    _update_chunks(true)


func set_target(node: Node3D) -> void:
    target = node
    _update_chunks(true)


func update_now() -> void:
    _update_chunks(true)


func get_bot_loop_min_max() -> Vector2:
    # Оставлено для совместимости, если ты захочешь вернуть старые маршруты.
    return Vector2(-spacing, spacing)


func _physics_process(delta: float) -> void:
    update_timer += delta

    if update_timer >= update_interval:
        update_timer = 0.0
        _update_chunks(false)


func _setup_resources() -> void:
    ground_mesh = PlaneMesh.new()
    ground_mesh.size = Vector2(spacing, spacing)

    road_h_mesh = PlaneMesh.new()
    road_h_mesh.size = Vector2(spacing + road_width, road_width)

    road_v_mesh = PlaneMesh.new()
    road_v_mesh.size = Vector2(road_width, spacing + road_width)

    line_h_mesh = PlaneMesh.new()
    line_h_mesh.size = Vector2(spacing + road_width, 0.25)

    line_v_mesh = PlaneMesh.new()
    line_v_mesh.size = Vector2(0.25, spacing + road_width)

    ground_material = StandardMaterial3D.new()
    ground_material.albedo_color = Color(0.22, 0.45, 0.22)

    road_material = StandardMaterial3D.new()
    road_material.albedo_color = Color(0.13, 0.13, 0.15)

    line_material = StandardMaterial3D.new()
    line_material.albedo_color = Color(0.8, 0.8, 0.2)

    var palette := [
        Color(0.62, 0.55, 0.48),
        Color(0.52, 0.58, 0.66),
        Color(0.68, 0.64, 0.58),
        Color(0.46, 0.50, 0.56),
        Color(0.72, 0.58, 0.52),
        Color(0.55, 0.68, 0.60),
        Color(0.60, 0.52, 0.62),
        Color(0.50, 0.50, 0.50),
    ]

    for c in palette:
        var mat := StandardMaterial3D.new()
        mat.albedo_color = c
        building_materials.append(mat)

    _setup_traffic_light_resources()


func _setup_traffic_light_resources() -> void:
    var pole_mesh := BoxMesh.new()
    pole_mesh.size = Vector3(0.18, 3.0, 0.18)

    var lamp_mesh := BoxMesh.new()
    lamp_mesh.size = Vector3(0.2, 0.2, 0.2)

    light_meshes = {
        "pole": pole_mesh,
        "lamp": lamp_mesh,
    }

    var pole_mat := StandardMaterial3D.new()
    pole_mat.albedo_color = Color(0.15, 0.15, 0.17)

    var red_mat := StandardMaterial3D.new()
    red_mat.albedo_color = Color(1.0, 0.15, 0.15)
    red_mat.emission_enabled = true
    red_mat.emission = Color(1.0, 0.1, 0.1)

    var yellow_mat := StandardMaterial3D.new()
    yellow_mat.albedo_color = Color(1.0, 0.8, 0.15)
    yellow_mat.emission_enabled = true
    yellow_mat.emission = Color(1.0, 0.75, 0.1)

    var green_mat := StandardMaterial3D.new()
    green_mat.albedo_color = Color(0.15, 1.0, 0.25)
    green_mat.emission_enabled = true
    green_mat.emission = Color(0.1, 1.0, 0.2)

    light_materials = {
        "pole": pole_mat,
        "red": red_mat,
        "yellow": yellow_mat,
        "green": green_mat,
    }


func _update_chunks(force: bool) -> void:
    if not is_inside_tree():
        return

    if spacing <= 0.0:
        return

    var center_chunk := Vector2i.ZERO

    if is_instance_valid(target):
        center_chunk = Vector2i(
            int(floor(target.global_position.x / spacing)),
            int(floor(target.global_position.z / spacing))
        )
    elif not keep_origin_loaded:
        return

    if initialized and not force and center_chunk == last_center_chunk:
        return

    last_center_chunk = center_chunk
    initialized = true

    var needed := {}

    _add_needed_chunks(needed, center_chunk, view_radius)

    if keep_origin_loaded:
        _add_needed_chunks(needed, Vector2i.ZERO, origin_radius)

    # Создаем недостающие чанки.
    for c in needed.keys():
        if not chunks.has(c):
            var chunk_root := _generate_chunk(c)
            chunks[c] = chunk_root
            add_child(chunk_root)

    # Удаляем далекие чанки.
    var to_erase := []

    for c in chunks.keys():
        var far_from_target := true

        if is_instance_valid(target):
            far_from_target = Vector2(float(c.x), float(c.y)).distance_to(
                Vector2(float(center_chunk.x), float(center_chunk.y))
            ) > unload_radius

        var far_from_origin := true

        if keep_origin_loaded:
            far_from_origin = Vector2(float(c.x), float(c.y)).distance_to(
                Vector2.ZERO
            ) > float(origin_radius) + 1.0

        if far_from_target and far_from_origin:
            to_erase.append(c)

    for c in to_erase:
        var chunk_root = chunks[c]
        chunks.erase(c)

        if is_instance_valid(chunk_root):
            chunk_root.queue_free()


func _add_needed_chunks(dict: Dictionary, center: Vector2i, radius: int) -> void:
    for x in range(center.x - radius, center.x + radius + 1):
        for y in range(center.y - radius, center.y + radius + 1):
            dict[Vector2i(x, y)] = true


func _generate_chunk(chunk: Vector2i) -> Node3D:
    var root := Node3D.new()
    root.name = "Chunk_%d_%d" % [chunk.x, chunk.y]
    root.position = Vector3(
        (chunk.x + 0.5) * spacing,
        0.0,
        (chunk.y + 0.5) * spacing
    )

    var rng := RandomNumberGenerator.new()
    rng.seed = _chunk_seed(chunk)

    # Крошечный сдвиг высоты нужен, чтобы соседние дороги не z-fighting'ли.
    var y_offset := float(posmod(chunk.x + chunk.y, 8)) * 0.00025

    _add_mesh(root, ground_mesh, ground_material, Vector3.ZERO)

    # Горизонтальная дорога по нижней границе чанка.
    _add_mesh(
        root,
        road_h_mesh,
        road_material,
        Vector3(0.0, 0.01 + y_offset, -spacing * 0.5)
    )

    # Вертикальная дорога по левой границе чанка.
    _add_mesh(
        root,
        road_v_mesh,
        road_material,
        Vector3(-spacing * 0.5, 0.02 + y_offset, 0.0)
    )

    if lane_markings:
        _add_mesh(
            root,
            line_h_mesh,
            line_material,
            Vector3(0.0, 0.03 + y_offset, -spacing * 0.5)
        )

        _add_mesh(
            root,
            line_v_mesh,
            line_material,
            Vector3(-spacing * 0.5, 0.04 + y_offset, 0.0)
        )

    if traffic_lights:
        _create_traffic_lights(root, chunk)

    _generate_buildings(root, rng)

    return root


func _create_traffic_lights(root: Node3D, chunk: Vector2i) -> void:
    var intersection := Vector2i(chunk.x, chunk.y)

    var directions := [
        Vector2i(1, 0),
        Vector2i(-1, 0),
        Vector2i(0, 1),
        Vector2i(0, -1)
    ]

    for d in directions:
        var light := TrafficLight.new()
        light.setup(intersection, d, light_meshes, light_materials)
        light.position = _traffic_light_local_position(d)
        root.add_child(light)


func _traffic_light_local_position(direction: Vector2i) -> Vector3:
    var local_intersection := Vector3(-spacing * 0.5, 0.0, -spacing * 0.5)

    var dir3 := Vector3(direction.x, 0.0, direction.y)
    var right_dir := Vector3(-direction.y, 0.0, direction.x)

    var stop_dist := road_width * 0.5 + 2.0
    var side_dist := road_width * 0.5 + 1.0

    return local_intersection - dir3 * stop_dist + right_dir * side_dist


func _generate_buildings(parent: Node3D, rng: RandomNumberGenerator) -> void:
    var inner_half := spacing * 0.5 - road_width * 0.5 - building_margin
    var inner_size := inner_half * 2.0

    if inner_size < 8.0:
        return

    # Делим квартал на 2x2 участка.
    var lot_size := inner_size / 2.0

    for lx in 2:
        for lz in 2:
            # Шанс, что участка не будет здания.
            if rng.randf() > 0.78:
                continue

            var lot_center := Vector3(
                -inner_half + lot_size * (lx + 0.5),
                0.0,
                -inner_half + lot_size * (lz + 0.5)
            )

            var w := rng.randf_range(lot_size * 0.55, lot_size * 0.92)
            var d := rng.randf_range(lot_size * 0.55, lot_size * 0.92)
            var h := rng.randf_range(building_min_height, building_max_height)

            var jitter_x := rng.randf_range(-1.0, 1.0) * maxf(0.0, (lot_size - w) * 0.25)
            var jitter_z := rng.randf_range(-1.0, 1.0) * maxf(0.0, (lot_size - d) * 0.25)

            _add_building(
                parent,
                lot_center + Vector3(jitter_x, 0.0, jitter_z),
                w,
                h,
                d,
                rng
            )


func _add_building(
    parent: Node3D,
    local_position: Vector3,
    w: float,
    h: float,
    d: float,
    rng: RandomNumberGenerator
) -> void:
    var body := StaticBody3D.new()
    body.position = local_position
    body.collision_mask = 0

    var mesh := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = Vector3(w, h, d)

    mesh.mesh = box
    mesh.position = Vector3(0.0, h * 0.5, 0.0)
    mesh.material_override = building_materials[rng.randi_range(0, building_materials.size() - 1)]

    var col := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(w, h, d)

    col.shape = shape
    col.position = Vector3(0.0, h * 0.5, 0.0)

    body.add_child(mesh)
    body.add_child(col)

    parent.add_child(body)


func _add_mesh(
    parent: Node3D,
    mesh: Mesh,
    material: Material,
    local_position: Vector3
) -> MeshInstance3D:
    var mi := MeshInstance3D.new()
    mi.mesh = mesh
    mi.material_override = material
    mi.position = local_position

    parent.add_child(mi)

    return mi


func _chunk_seed(chunk: Vector2i) -> int:
    return hash("%d|%d|%d" % [chunk.x, chunk.y, random_seed])