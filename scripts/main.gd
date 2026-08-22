extends Node3D

# Оставлены для совместимости со старым main.tscn.
@export var bot_count := 8
@export var bot_speed := 13.0

const WORLD_SCENE := preload("res://scenes/world.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")


func _ready() -> void:
    var world := WORLD_SCENE.instantiate() as Node3D
    add_child(world)

    var city = _get_city(world)

    var player := PLAYER_SCENE.instantiate() as PlayerCar
    player.position = Vector3.ZERO
    world.add_child(player)

    if city and city.has_method("set_target"):
        city.set_target(player)
    elif city:
        city.target = player

    var bot_manager := world.get_node_or_null("BotManager") as BotManager
    if bot_manager and city:
        bot_manager.setup(city, player)

    var pedestrian_manager := world.get_node_or_null("PedestrianManager") as PedestrianManager
    if pedestrian_manager and city:
        pedestrian_manager.setup(city, player)


func _get_city(world: Node3D):
    for child in world.get_children():
        if child is CityGenerator:
            return child

    return null