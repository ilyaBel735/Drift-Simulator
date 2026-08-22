class_name PedestrianManager
extends Node3D

@export var pedestrian_scene: PackedScene

@export var city_path: NodePath
@export var target_path: NodePath

@export var max_pedestrians := 14
@export var spawn_radius_chunks := 2
@export var despawn_distance := 120.0
@export var min_distance_from_player := 8.0
@export var max_distance_from_player := 90.0
@export var min_distance_between_pedestrians := 3.0
@export var update_interval := 1.5

var city: CityGenerator
var target: Node3D
var active_pedestrians := []
var timer := 0.0


func _ready() -> void:
	if pedestrian_scene == null:
		pedestrian_scene = preload("res://scenes/pedestrian.tscn")

	if city_path != NodePath(""):
		city = get_node_or_null(city_path) as CityGenerator

	if target_path != NodePath(""):
		target = get_node_or_null(target_path) as Node3D


func setup(c: CityGenerator, t: Node3D) -> void:
	city = c
	target = t
	_update_pedestrians()


func _physics_process(delta: float) -> void:
	timer += delta

	if timer >= update_interval:
		timer = 0.0
		_update_pedestrians()


func _update_pedestrians() -> void:
	if not is_instance_valid(city) or not is_instance_valid(target):
		return

	_clean_pedestrians()
	_despawn_pedestrians()

	var need := max_pedestrians - active_pedestrians.size()

	for i in need:
		_try_spawn_one()


func _clean_pedestrians() -> void:
	var valid := []

	for ped in active_pedestrians:
		if is_instance_valid(ped):
			valid.append(ped)

	active_pedestrians = valid


func _despawn_pedestrians() -> void:
	var remove := []

	for ped in active_pedestrians:
		if not is_instance_valid(ped):
			continue

		var p := ped as Pedestrian

		var far_away: bool = bool(p.global_position.distance_to(target.global_position) > despawn_distance)
		var block_unloaded := not city.chunks.has(ped.current_block)

		if far_away or block_unloaded:
			remove.append(ped)

	for ped in remove:
		active_pedestrians.erase(ped)
		ped.queue_free()


func _try_spawn_one() -> void:
	if pedestrian_scene == null:
		return

	var spacing := city.spacing

	if spacing <= 0.0:
		return

	for attempt in 40:
		var block := _random_block_near_player(spacing)
		var corner := randi_range(0, 3)
		var pos := _corner_point(block, corner, spacing, city.road_width)

		var dist := pos.distance_to(target.global_position)

		if dist < min_distance_from_player or dist > max_distance_from_player:
			continue

		if _too_close_to_pedestrians(pos):
			continue

		var ped := pedestrian_scene.instantiate() as Pedestrian
		if ped == null:
			return

		add_child(ped)
		ped.setup(city, block, corner, pos)

		active_pedestrians.append(ped)

		return


func _random_block_near_player(spacing: float) -> Vector2i:
	var center := Vector2i(
		int(floor(target.global_position.x / spacing)),
		int(floor(target.global_position.z / spacing))
	)

	return Vector2i(
		center.x + randi_range(-spawn_radius_chunks, spawn_radius_chunks),
		center.y + randi_range(-spawn_radius_chunks, spawn_radius_chunks)
	)


func _corner_point(
	block: Vector2i,
	corner: int,
	spacing: float,
	road_width: float
) -> Vector3:
	var center := Vector3(
		(block.x + 0.5) * spacing,
		0.0,
		(block.y + 0.5) * spacing
	)

	var h := maxf(2.0, spacing * 0.5 - road_width * 0.5 - 1.5)

	match corner:
		0:
			return center + Vector3(-h, 0.0, -h)
		1:
			return center + Vector3(h, 0.0, -h)
		2:
			return center + Vector3(h, 0.0, h)
		_:
			return center + Vector3(-h, 0.0, h)


func _too_close_to_pedestrians(pos: Vector3) -> bool:
	for ped in active_pedestrians:
		if is_instance_valid(ped):
			if ped.global_position.distance_to(pos) < min_distance_between_pedestrians:
				return true

	return false
