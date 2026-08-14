extends Node3D

@export var bot_count := 8
@export var bot_speed := 13.0

const WORLD_SCENE := preload("res://scenes/world.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const BOT_SCENE := preload("res://scenes/bot_car.tscn")


func _ready() -> void:
    var world := WORLD_SCENE.instantiate() as Node3D
    add_child(world)

    var city = _get_city(world)

    var player := PLAYER_SCENE.instantiate() as PlayerCar
    player.position = _get_player_start(city)
    world.add_child(player)

    var path := world.get_node_or_null("BotPath") as Path3D
    if path:
        _prepare_bot_path(path, city)
        _spawn_bots(path)
    else:
        push_warning("BotPath не найден в world.tscn")


func _get_city(world: Node3D):
    for child in world.get_children():
        if child is CityGenerator:
            return child
    return null


func _get_player_start(city) -> Vector3:
    if city and city.road_coords.size() > 0:
        var idx := int(city.road_coords.size() / 2)
        var road := float(city.road_coords[idx])
        return Vector3(road, 0.0, road)

    return Vector3.ZERO


func _prepare_bot_path(path: Path3D, city) -> void:
    # Сразу заменяем кривую на новую, чтобы гарантированно
    # избавиться от битой/нулевой Curve3D.
    var curve := Curve3D.new()
    curve.bake_interval = 0.25
    path.curve = curve

    var min_max := Vector2(-48.0, 48.0)

    if city and city.has_method("get_bot_loop_min_max"):
        min_max = city.get_bot_loop_min_max()

    var a := min_max.x
    var b := min_max.y

    if b - a < 20.0:
        push_warning("Bot path is too small.")
        return

    var r := minf(10.0, (b - a) * 0.2)

    # Замкнутый маршрут с немного срезанными углами.
    curve.add_point(Vector3(a + r, 0.0, a))
    curve.add_point(Vector3(b - r, 0.0, a))
    curve.add_point(Vector3(b, 0.0, a + r))
    curve.add_point(Vector3(b, 0.0, b - r))
    curve.add_point(Vector3(b - r, 0.0, b))
    curve.add_point(Vector3(a + r, 0.0, b))
    curve.add_point(Vector3(a, 0.0, b - r))
    curve.add_point(Vector3(a, 0.0, a + r))
    curve.add_point(Vector3(a + r, 0.0, a))


func _spawn_bots(path: Path3D) -> void:
    if path.curve == null:
        return

    var length := path.curve.get_baked_length()
    if length <= 0.0:
        return

    for i in bot_count:
        var bot := BOT_SCENE.instantiate() as BotCar
        if bot == null:
            continue

        bot.speed = bot_speed + randf_range(-2.0, 2.0)
        bot.start_offset = fposmod(i * length / float(max(1, bot_count)), length)

        path.add_child(bot)