class_name GasStation
extends Node3D

var station_key := Vector2i.ZERO

# Сколько машин может стоять в очереди на дороге.
# Не путать с тремя местами на самой заправке.
var max_queue_length := 4

var lane_offset := 3.0

var entrance_local := Vector3.ZERO
var pump_locals := []

var occupied := [false, false, false]

var waiting_east := []
var waiting_west := []

var clean_timer := 0.0


func setup(
    key: Vector2i,
    spacing: float,
    road_width: float,
    rng: RandomNumberGenerator
) -> void:
    station_key = key
    lane_offset = road_width * 0.25

    var road_half := road_width * 0.5
    var pad_depth := 16.0
    var pad_width := 24.0

    # Заправка ставится внутри квартала у нижней дороги чанка.
    position = Vector3(
        0.0,
        0.0,
        -spacing * 0.5 + road_half + pad_depth * 0.5 + 2.0
    )

    # Точка въезда находится на дороге.
    entrance_local = Vector3(0.0, 0.0, -spacing * 0.5 - position.z)

    pump_locals = [
        Vector3(-6.0, 0.0, -2.0),
        Vector3(0.0, 0.0, -2.0),
        Vector3(6.0, 0.0, -2.0),
    ]

    _build_visuals(pad_width, pad_depth, rng)


func _process(delta: float) -> void:
    clean_timer += delta

    if clean_timer >= 0.5:
        clean_timer = 0.0
        _clean_queues()


func request(bot: Node3D, dir2: Vector2i) -> Dictionary:
    _clean_queues()

    var east := dir2.x >= 0

    var queue := waiting_east if east else waiting_west
    var other := waiting_west if east else waiting_east

    other.erase(bot)

    var idx := queue.find(bot)

    if idx == -1:
        queue.append(bot)
        idx = queue.size() - 1

    # Первая машина в очереди может занять свободную колонку.
    if idx == 0:
        var spot := _get_free_spot()

        if spot != -1:
            occupied[spot] = true
            queue.remove_at(0)

            return {
                "assigned": true,
                "spot": spot,
                "point": get_pump_global(spot),
                "skip": false,
            }

    # Если очередь слишком длинная, новые машины не пытаются заправиться.
    if idx >= max_queue_length:
        queue.erase(bot)

        return {
            "assigned": false,
            "skip": true,
            "point": Vector3.ZERO,
        }

    return {
        "assigned": false,
        "skip": false,
        "point": get_queue_point(dir2, idx),
    }


func release_spot(index: int) -> void:
    if index >= 0 and index < occupied.size():
        occupied[index] = false


func remove_from_queue(bot: Node3D) -> void:
    waiting_east.erase(bot)
    waiting_west.erase(bot)


func get_entrance_global() -> Vector3:
    return to_global(entrance_local)


func get_pump_global(index: int) -> Vector3:
    if index < 0 or index >= pump_locals.size():
        return to_global(entrance_local)

    return to_global(pump_locals[index])


func get_exit_point(dir2: Vector2i) -> Vector3:
    var east := dir2.x >= 0

    if east:
        return to_global(entrance_local + Vector3(10.0, 0.0, lane_offset))
    else:
        return to_global(entrance_local + Vector3(-10.0, 0.0, -lane_offset))


func get_queue_point(dir2: Vector2i, idx: int) -> Vector3:
    var east := dir2.x >= 0
    var dist := float(idx + 1) * 6.5

    var point := entrance_local

    if east:
        point += Vector3(-dist, 0.0, lane_offset)
    else:
        point += Vector3(dist, 0.0, -lane_offset)

    return to_global(point)


func _get_free_spot() -> int:
    for i in occupied.size():
        if not occupied[i]:
            return i

    return -1


func _clean_queues() -> void:
    var cleaned_east := []

    for bot in waiting_east:
        if is_instance_valid(bot):
            cleaned_east.append(bot)

    waiting_east = cleaned_east

    var cleaned_west := []

    for bot in waiting_west:
        if is_instance_valid(bot):
            cleaned_west.append(bot)

    waiting_west = cleaned_west


func _build_visuals(
    pad_width: float,
    pad_depth: float,
    rng: RandomNumberGenerator
) -> void:
    # Площадка.
    var pad := MeshInstance3D.new()

    var pad_mesh := BoxMesh.new()
    pad_mesh.size = Vector3(pad_width, 0.2, pad_depth)

    pad.mesh = pad_mesh
    pad.position = Vector3(0.0, 0.05, 0.0)

    var pad_mat := StandardMaterial3D.new()
    pad_mat.albedo_color = Color(0.45, 0.45, 0.47)

    pad.material_override = pad_mat

    add_child(pad)

    # Колонки.
    for p in pump_locals:
        var pump := MeshInstance3D.new()

        var pump_mesh := BoxMesh.new()
        pump_mesh.size = Vector3(0.6, 1.2, 0.4)

        pump.mesh = pump_mesh
        pump.position = p + Vector3(0.0, 0.6, 0.0)

        var pump_mat := StandardMaterial3D.new()
        pump_mat.albedo_color = Color(0.8, 0.2, 0.2)

        pump.material_override = pump_mat

        add_child(pump)

    # Билборд.
    var board := MeshInstance3D.new()

    var board_mesh := BoxMesh.new()
    board_mesh.size = Vector3(6.0, 3.0, 0.3)

    board.mesh = board_mesh
    board.position = Vector3(8.0, 2.5, -12.0)

    var board_mat := StandardMaterial3D.new()
    board_mat.albedo_color = Color(0.1, 0.12, 0.16)

    board.material_override = board_mat

    add_child(board)

    # Цены.
    var label := Label3D.new()

    label.text = _make_price_text(rng)
    label.position = Vector3(8.0, 2.5, -12.25)
    label.rotation_degrees = Vector3(0.0, 180.0, 0.0)

    label.pixel_size = 0.015
    label.font_size = 48

    label.modulate = Color(1.0, 1.0, 1.0)
    label.outline_size = 6
    label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)

    add_child(label)


func _make_price_text(rng: RandomNumberGenerator) -> String:
    var a92 := rng.randf_range(30.0, 80.0)
    var a95 := rng.randf_range(35.0, 90.0)
    var diesel := rng.randf_range(32.0, 85.0)

    return "AI-92: %.2f\nAI-95: %.2f\nDiesel: %.2f" % [a92, a95, diesel]