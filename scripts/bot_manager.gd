class_name BotManager
extends Node3D

@export var bot_scene: PackedScene

@export var city_path: NodePath
@export var target_path: NodePath

@export var max_bots := 12
@export var spawn_radius_chunks := 2
@export var despawn_distance := 140.0
@export var min_distance_from_player := 18.0
@export var max_distance_from_player := 110.0
@export var min_distance_between_bots := 10.0
@export var update_interval := 1.0

var city: CityGenerator
var target: Node3D
var active_bots := []
var timer := 0.0


func _ready() -> void:
    if bot_scene == null:
        bot_scene = preload("res://scenes/traffic_bot.tscn")

    if city_path != NodePath(""):
        city = get_node_or_null(city_path) as CityGenerator

    if target_path != NodePath(""):
        target = get_node_or_null(target_path) as Node3D


func setup(c: CityGenerator, t: Node3D) -> void:
    city = c
    target = t
    _update_bots()


func _physics_process(delta: float) -> void:
    timer += delta

    if timer >= update_interval:
        timer = 0.0
        _update_bots()


func _update_bots() -> void:
    if not is_instance_valid(city) or not is_instance_valid(target):
        return

    _clean_bots()
    _despawn_far_bots()

    var need := max_bots - active_bots.size()

    for i in need:
        _try_spawn_one()


func _clean_bots() -> void:
    var valid := []

    for bot in active_bots:
        if is_instance_valid(bot):
            valid.append(bot)

    active_bots = valid


func _despawn_far_bots() -> void:
    var remove := []

    for bot in active_bots:
        if bot.global_position.distance_to(target.global_position) > despawn_distance:
            remove.append(bot)

    for bot in remove:
        active_bots.erase(bot)
        bot.queue_free()


func _try_spawn_one() -> void:
    if bot_scene == null:
        return

    var spacing := city.spacing
    if spacing <= 0.0:
        return

    var lane := city.road_width * 0.25

    for attempt in 40:
        var chunk := _random_chunk_near_player(spacing)

        var horizontal := randf() < 0.5

        var dir2 := Vector2i(1, 0)
        var start := Vector3.ZERO
        var next_inter := Vector2i.ZERO

        var base_x := chunk.x * spacing
        var base_z := chunk.y * spacing

        var t := randf_range(0.25, 0.75) * spacing

        if horizontal:
            if randf() < 0.5:
                # East
                dir2 = Vector2i(1, 0)
                start = Vector3(base_x + t, 0.0, base_z + lane)
                next_inter = Vector2i(chunk.x + 1, chunk.y)
            else:
                # West
                dir2 = Vector2i(-1, 0)
                start = Vector3(base_x + spacing - t, 0.0, base_z - lane)
                next_inter = Vector2i(chunk.x, chunk.y)
        else:
            if randf() < 0.5:
                # South
                dir2 = Vector2i(0, 1)
                start = Vector3(base_x - lane, 0.0, base_z + t)
                next_inter = Vector2i(chunk.x, chunk.y + 1)
            else:
                # North
                dir2 = Vector2i(0, -1)
                start = Vector3(base_x + lane, 0.0, base_z + spacing - t)
                next_inter = Vector2i(chunk.x, chunk.y)

        var dist := start.distance_to(target.global_position)

        if dist < min_distance_from_player or dist > max_distance_from_player:
            continue

        if _too_close_to_bots(start):
            continue

        var bot := bot_scene.instantiate() as TrafficBot
        if bot == null:
            return

        bot.max_speed = randf_range(9.0, 14.0)

        add_child(bot)
        bot.setup(spacing, city.road_width, start, dir2, next_inter)

        active_bots.append(bot)

        return


func _random_chunk_near_player(spacing: float) -> Vector2i:
    var center := Vector2i(
        int(floor(target.global_position.x / spacing)),
        int(floor(target.global_position.z / spacing))
    )

    return Vector2i(
        center.x + randi_range(-spawn_radius_chunks, spawn_radius_chunks),
        center.y + randi_range(-spawn_radius_chunks, spawn_radius_chunks)
    )


func _too_close_to_bots(pos: Vector3) -> bool:
    for bot in active_bots:
        if is_instance_valid(bot):
            if bot.global_position.distance_to(pos) < min_distance_between_bots:
                return true

    return false