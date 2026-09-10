class_name CityGenerator
extends Node3D

enum Biome { NATURE, VILLAGE, CITY }

const TreeScene = preload("res://scenes/tree.tscn")
const GasStationScene = preload("res://scenes/gas_station.tscn")
const BuildingScene = preload("res://scenes/building.tscn")
const VillageHouseScene = preload("res://scenes/village_house.tscn")
const GrassPatchScene = preload("res://scenes/grass_patch.tscn")
const GroundNatureScene = preload("res://scenes/ground_nature.tscn")
const GroundCityScene = preload("res://scenes/ground_city.tscn")
const GroundVillageScene = preload("res://scenes/ground_village.tscn")
const RoadCityScene = preload("res://scenes/road_city.tscn")
const RoadVillageScene = preload("res://scenes/road_village.tscn")
const RoadLineScene = preload("res://scenes/road_line.tscn")

@export var tree_density := 0.15
@export var gas_station_chance := 0.08
@export var parking_chance := 0.12

# Количество кустиков травы на чанк (рисуются одним MultiMesh — дёшево).
@export var grass_nature_count := 90
@export var grass_village_count := 40

@export var spacing := 48.0
@export var road_width := 12.0
@export var building_margin := 4.0
@export var building_min_height := 5.0
@export var building_max_height := 20.0
@export var random_seed := 2024
@export var lane_markings := true
@export var traffic_lights := true

# Вероятность светофора на перекрёстке в городе (1.0 = на каждом).
@export_range(0.0, 1.0) var traffic_light_chance := 0.7
# Прибавка к порогу дорог: чем больше, тем реже дороги.
@export var village_road_sparsity := 0.12
@export var nature_road_sparsity := 0.25

# Настройки шума.
@export var noise_seed := 2024
@export var city_frequency := 0.025
@export var road_frequency := 0.07
@export var detail_frequency := 0.18
@export var village_frequency := 0.022

# Циклические биомы: ГОРОД -> ЛЕС -> ДЕРЕВНЯ -> ЛЕС -> ...
@export var biome_size := 20
@export var city_width := 1.0
@export var forest_width := 1.0
@export var village_width := 1.0
@export var edge_frequency := 0.06
@export var edge_noise_amount := 0.35
@export var cycle_offset := 1.35

# Пороги.
@export var city_threshold := -0.10
@export var road_threshold := -0.05
@export var pedestrian_threshold := -0.35
@export var village_threshold := 0.10

# Зона рядом со стартом, где гарантированно есть дороги и город.
@export var guaranteed_radius := 2
# Каждая N-ная линия дороги гарантированно существует.
@export var main_road_interval := 3

# Радиус генерации вокруг игрока.
@export var view_radius := 3
@export var unload_radius := 5
@export var origin_radius := 2
@export var keep_origin_loaded := true
@export var update_interval := 0.4

var gas_stations := {}
var building_doors := {}
var parking_spots := {}

var target: Node3D

var chunks := {}
var last_center_chunk := Vector2i.ZERO
var initialized := false
var update_timer := 0.0

var city_noise := FastNoiseLite.new()
var road_noise := FastNoiseLite.new()
var detail_noise := FastNoiseLite.new()
var village_noise := FastNoiseLite.new()
var edge_noise := FastNoiseLite.new()

var light_meshes := {}
var light_materials := {}

# Оттенки зданий/домов. Когда добавишь текстуры — будут работать как вариации цвета.
var building_colors := [
	Color(0.62, 0.55, 0.48),
	Color(0.52, 0.58, 0.66),
	Color(0.68, 0.64, 0.58),
	Color(0.46, 0.50, 0.56),
	Color(0.72, 0.58, 0.52),
	Color(0.55, 0.68, 0.60),
	Color(0.60, 0.52, 0.62),
	Color(0.50, 0.50, 0.50),
]

var village_colors := [
	Color(0.55, 0.42, 0.3),
	Color(0.65, 0.55, 0.4),
	Color(0.5, 0.38, 0.28),
	Color(0.7, 0.6, 0.45),
	Color(0.58, 0.47, 0.35),
]

func _ready() -> void:
	if random_seed == 0:
		randomize()
		random_seed = randi()
	if noise_seed == 0:
		noise_seed = randi()
	_setup_noise()
	_setup_traffic_light_resources()
	_update_chunks(true)

func set_target(node: Node3D) -> void:
	target = node
	_update_chunks(true)

func update_now() -> void:
	_update_chunks(true)

func _physics_process(delta: float) -> void:
	update_timer += delta
	if update_timer >= update_interval:
		update_timer = 0.0
		_update_chunks(false)

# ----------------------------------
# Noise helpers
# ----------------------------------

func _setup_noise() -> void:
	city_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	road_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	detail_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	village_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	edge_noise.noise_type = FastNoiseLite.TYPE_PERLIN

	city_noise.seed = noise_seed
	road_noise.seed = noise_seed + 101
	detail_noise.seed = noise_seed + 202
	village_noise.seed = noise_seed + 303
	edge_noise.seed = noise_seed + 404

	city_noise.frequency = city_frequency
	road_noise.frequency = road_frequency
	detail_noise.frequency = detail_frequency
	village_noise.frequency = village_frequency
	edge_noise.frequency = edge_frequency

func _district_value(chunk: Vector2i) -> float:
	return city_noise.get_noise_2d(chunk.x + 0.5, chunk.y + 0.5)

func _village_value(chunk: Vector2i) -> float:
	return village_noise.get_noise_2d(chunk.x + 0.5, chunk.y + 0.5)

func _district_density(value: float) -> float:
	var v := (value - city_threshold) / maxf(0.001, 1.0 - city_threshold)
	return clampf(v, 0.0, 1.0)

func _village_density(value: float) -> float:
	var v := (value - village_threshold) / maxf(0.001, 1.0 - village_threshold)
	return clampf(v, 0.0, 1.0)

func get_biome(chunk: Vector2i) -> int:
	# Стартовая зона всегда город.
	if _is_guaranteed_chunk(chunk):
		return Biome.CITY
	return _cycle_biome(chunk)

# Биомы всегда идут строгим циклом:
# ГОРОД -> ЛЕС -> ДЕРЕВНЯ -> ЛЕС -> ГОРОД -> ...
func _cycle_biome(chunk: Vector2i) -> int:
	var wob := edge_noise.get_noise_2d(chunk.x + 0.5, chunk.y + 0.5) * edge_noise_amount
	var axis := float(chunk.x + chunk.y) / float(biome_size) + wob + cycle_offset
	var cycle := city_width + forest_width + village_width + forest_width
	var t := posmod(axis, cycle)

	if t < city_width:
		return Biome.CITY
	t -= city_width
	if t < forest_width:
		return Biome.NATURE
	t -= forest_width
	if t < village_width:
		return Biome.VILLAGE
	return Biome.NATURE

func _is_guaranteed_chunk(chunk: Vector2i) -> bool:
	if guaranteed_radius < 0:
		return false
	return abs(chunk.x) <= guaranteed_radius and abs(chunk.y) <= guaranteed_radius

func _is_guaranteed_h(ix: int, iz: int) -> bool:
	if guaranteed_radius < 0:
		return false
	return abs(iz) <= guaranteed_radius and (
		abs(ix) <= guaranteed_radius or abs(ix + 1) <= guaranteed_radius
	)

func _is_guaranteed_v(ix: int, iz: int) -> bool:
	if guaranteed_radius < 0:
		return false
	return abs(ix) <= guaranteed_radius and (
		abs(iz) <= guaranteed_radius or abs(iz + 1) <= guaranteed_radius
	)

# ----------------------------------
# Public road queries
# ----------------------------------

func has_horizontal_road(ix: int, iz: int) -> bool:
	if _is_guaranteed_h(ix, iz):
		return true
	if main_road_interval > 0 and posmod(iz, main_road_interval) == 0:
		return true
	var n := road_noise.get_noise_2d(ix + 0.5, iz)
	return n > _road_threshold_for(Vector2i(ix, iz))

func has_vertical_road(ix: int, iz: int) -> bool:
	if _is_guaranteed_v(ix, iz):
		return true
	if main_road_interval > 0 and posmod(ix, main_road_interval) == 0:
		return true
	var n := road_noise.get_noise_2d(ix, iz + 0.5)
	return n > _road_threshold_for(Vector2i(ix, iz))

# В городе дороги плотные, в деревне реже, в лесу — в основном магистрали.
func _road_threshold_for(chunk: Vector2i) -> float:
	match get_biome(chunk):
		Biome.VILLAGE:
			return road_threshold + village_road_sparsity
		Biome.NATURE:
			return road_threshold + nature_road_sparsity
		_:
			return road_threshold

func has_road_segment(from: Vector2i, direction: Vector2i) -> bool:
	if direction == Vector2i(1, 0):
		return has_horizontal_road(from.x, from.y)
	if direction == Vector2i(-1, 0):
		return has_horizontal_road(from.x - 1, from.y)
	if direction == Vector2i(0, 1):
		return has_vertical_road(from.x, from.y)
	if direction == Vector2i(0, -1):
		return has_vertical_road(from.x, from.y - 1)
	return false

func intersection_has_cross_roads(intersection: Vector2i) -> bool:
	var h := has_horizontal_road(intersection.x, intersection.y) or has_horizontal_road(intersection.x - 1, intersection.y)
	var v := has_vertical_road(intersection.x, intersection.y) or has_vertical_road(intersection.x, intersection.y - 1)
	return h and v

func has_traffic_lights_at(intersection: Vector2i) -> bool:
	if not traffic_lights:
		return false
	if not intersection_has_cross_roads(intersection):
		return false
	# Вне города светофоров нет.
	if get_biome(intersection) != Biome.CITY:
		return false
	# В городе — не на каждом перекрёстке.
	if traffic_light_chance >= 1.0:
		return true
	var h := hash("%d|%d|light|%d" % [intersection.x, intersection.y, random_seed])
	return float(h % 1000) / 1000.0 < traffic_light_chance

func is_pedestrian_chunk(chunk: Vector2i) -> bool:
	if _is_guaranteed_chunk(chunk):
		return true
	var biome := get_biome(chunk)
	if biome == Biome.CITY or biome == Biome.VILLAGE:
		return true
	return _district_value(chunk) > pedestrian_threshold

# ----------------------------------
# Chunk update
# ----------------------------------

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

	for c in needed.keys():
		if not chunks.has(c):
			var chunk_root := _generate_chunk(c)
			chunks[c] = chunk_root
			add_child(chunk_root)

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
		if chunk_root.has_meta("gas_station_key"):
			gas_stations.erase(chunk_root.get_meta("gas_station_key"))
		building_doors.erase(c)
		parking_spots.erase(c)
		if is_instance_valid(chunk_root):
			chunk_root.queue_free()

func _add_needed_chunks(dict: Dictionary, center: Vector2i, radius: int) -> void:
	for x in range(center.x - radius, center.x + radius + 1):
		for y in range(center.y - radius, center.y + radius + 1):
			dict[Vector2i(x, y)] = true

# ----------------------------------
# Chunk generation
# ----------------------------------

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

	var biome := get_biome(chunk)
	var district := _district_value(chunk)
	var guaranteed := _is_guaranteed_chunk(chunk)

	var density := _district_density(district)
	if guaranteed:
		density = maxf(density, 0.4)

	# --- Пол ---
	var ground_scene: PackedScene = GroundNatureScene
	if biome == Biome.CITY:
		ground_scene = GroundCityScene
	elif biome == Biome.VILLAGE:
		ground_scene = GroundVillageScene

	var ground := ground_scene.instantiate() as PlanePiece
	ground.setup_size(Vector2(spacing, spacing))
	ground.position = Vector3.ZERO
	root.add_child(ground)

	# Крошечный сдвиг высоты, чтобы соседние дороги не z-fighting'или.
	var y_offset := float(posmod(chunk.x + chunk.y, 8)) * 0.00025

	var h_road := has_horizontal_road(chunk.x, chunk.y)
	var v_road := has_vertical_road(chunk.x, chunk.y)

	# --- Дороги ---
	var road_scene: PackedScene = RoadCityScene
	if biome == Biome.VILLAGE:
		road_scene = RoadVillageScene

	if h_road:
		var rh := road_scene.instantiate() as PlanePiece
		rh.setup_size(Vector2(spacing + road_width, road_width))
		rh.position = Vector3(0.0, 0.01 + y_offset, -spacing * 0.5)
		root.add_child(rh)

		if lane_markings and biome == Biome.CITY:
			var lh := RoadLineScene.instantiate() as PlanePiece
			lh.setup_size(Vector2(spacing + road_width, 0.25))
			lh.position = Vector3(0.0, 0.03 + y_offset, -spacing * 0.5)
			root.add_child(lh)

	if v_road:
		var rv := road_scene.instantiate() as PlanePiece
		rv.setup_size(Vector2(road_width, spacing + road_width))
		rv.position = Vector3(-spacing * 0.5, 0.02 + y_offset, 0.0)
		root.add_child(rv)

		if lane_markings and biome == Biome.CITY:
			var lv := RoadLineScene.instantiate() as PlanePiece
			lv.setup_size(Vector2(0.25, spacing + road_width))
			lv.position = Vector3(-spacing * 0.5, 0.04 + y_offset, 0.0)
			root.add_child(lv)

	if traffic_lights and has_traffic_lights_at(Vector2i(chunk.x, chunk.y)):
		_create_traffic_lights(root, chunk)

	if biome == Biome.NATURE or biome == Biome.VILLAGE:
		_generate_grass(root, rng, biome, chunk)

	var special := false

	if biome == Biome.CITY and h_road and rng.randf() < gas_station_chance:
		_generate_gas_station(root, chunk, rng)
		special = true

	if not special and biome == Biome.CITY and rng.randf() < parking_chance:
		_generate_parking(root, chunk, rng)
		special = true

	if not special:
		match biome:
			Biome.CITY:
				_generate_buildings(root, rng, density, chunk)
			Biome.VILLAGE:
				_generate_village(root, rng, _village_density(_village_value(chunk)), chunk)
			_:
				_generate_nature(root, rng, chunk)

	return root

func _generate_buildings(parent: Node3D, rng: RandomNumberGenerator, density: float, chunk: Vector2i) -> void:
	var inner_half := spacing * 0.5 - road_width * 0.5 - building_margin
	var inner_size := inner_half * 2.0
	if inner_size < 8.0:
		return
	var lot_size := inner_size / 2.0
	var building_chance := clampf(0.2 + density * 0.7, 0.0, 0.95)
	var height_multiplier := lerpf(0.7, 1.4, density)
	for lx in 2:
		for lz in 2:
			if rng.randf() > building_chance:
				continue
			var lot_center := Vector3(
				-inner_half + lot_size * (lx + 0.5),
				0.0,
				-inner_half + lot_size * (lz + 0.5)
			)
			var w := rng.randf_range(lot_size * 0.55, lot_size * 0.92)
			var d := rng.randf_range(lot_size * 0.55, lot_size * 0.92)
			var h := rng.randf_range(building_min_height, building_max_height) * height_multiplier
			var jitter_x := rng.randf_range(-1.0, 1.0) * maxf(0.0, (lot_size - w) * 0.25)
			var jitter_z := rng.randf_range(-1.0, 1.0) * maxf(0.0, (lot_size - d) * 0.25)
			_add_building(parent, lot_center + Vector3(jitter_x, 0.0, jitter_z), w, h, d, rng, chunk)

func _generate_village(parent: Node3D, rng: RandomNumberGenerator, density: float, chunk: Vector2i) -> void:
	var inner_half := spacing * 0.5 - road_width * 0.5 - building_margin
	var inner_size := inner_half * 2.0
	if inner_size < 10.0:
		return
	var lot_size := inner_size / 2.0
	var house_chance := clampf(0.25 + density * 0.5, 0.0, 0.85)
	for lx in 2:
		for lz in 2:
			if rng.randf() > house_chance:
				continue
			var lot_center := Vector3(
				-inner_half + lot_size * (lx + 0.5),
				0.0,
				-inner_half + lot_size * (lz + 0.5)
			)
			var w := rng.randf_range(lot_size * 0.35, lot_size * 0.65)
			var d := rng.randf_range(lot_size * 0.35, lot_size * 0.65)
			var h := rng.randf_range(3.0, 6.5)
			var jitter_x := rng.randf_range(-1.0, 1.0) * maxf(0.0, (lot_size - w) * 0.25)
			var jitter_z := rng.randf_range(-1.0, 1.0) * maxf(0.0, (lot_size - d) * 0.25)
			_add_village_house(parent, lot_center + Vector3(jitter_x, 0.0, jitter_z), w, h, d, rng, chunk)
	# Немного деревьев рядом с деревней.
	var tree_count := rng.randi_range(1, 4)
	for i in tree_count:
		var pos := _random_nature_local(rng)
		_add_tree(parent, pos, rng)

func _generate_nature(parent: Node3D, rng: RandomNumberGenerator, chunk: Vector2i) -> void:
	var district := _district_value(chunk)
	var tree_count := rng.randi_range(3, 8)
	# Если это почти городская зона, деревьев меньше.
	if district > -0.2:
		tree_count = int(min(tree_count, 2))
	for i in tree_count:
		var pos := _random_nature_local(rng)
		_add_tree(parent, pos, rng)

func _generate_grass(root: Node3D, rng: RandomNumberGenerator, biome: int, chunk: Vector2i) -> void:
	var count := grass_nature_count if biome == Biome.NATURE else grass_village_count
	if count <= 0:
		return

	var bmin := Vector2(-spacing * 0.5 + 1.0, -spacing * 0.5 + 1.0)
	var bmax := Vector2(spacing * 0.5 - 1.0, spacing * 0.5 - 1.0)

	# Нижняя дорога (своя) и верхняя (соседнего чанка).
	if has_horizontal_road(chunk.x, chunk.y):
		bmin.y = -spacing * 0.5 + road_width * 0.5 + 0.6
	if has_horizontal_road(chunk.x, chunk.y + 1):
		bmax.y = spacing * 0.5 - road_width * 0.5 - 0.6

	# Левая дорога (своя) и правая (соседнего чанка).
	if has_vertical_road(chunk.x, chunk.y):
		bmin.x = -spacing * 0.5 + road_width * 0.5 + 0.6
	if has_vertical_road(chunk.x + 1, chunk.y):
		bmax.x = spacing * 0.5 - road_width * 0.5 - 0.6

	# Если дороги "съели" всю площадь чанка — траву не сыпем.
	if bmin.x >= bmax.x or bmin.y >= bmax.y:
		return

	var patch := GrassPatchScene.instantiate() as GrassPatch
	patch.generate(rng, count, bmin, bmax)
	root.add_child(patch)

func _random_nature_local(rng: RandomNumberGenerator) -> Vector3:
	var inner := maxf(4.0, spacing * 0.5 - road_width * 0.5 - building_margin)
	return Vector3(
		rng.randf_range(-inner, inner),
		0.0,
		rng.randf_range(-inner, inner)
	)

func _add_building(
	parent: Node3D,
	local_position: Vector3,
	w: float,
	h: float,
	d: float,
	rng: RandomNumberGenerator,
	chunk: Vector2i
) -> void:
	var building := BuildingScene.instantiate() as Building
	building.setup(
		Vector3(w, h, d),
		building_colors[rng.randi_range(0, building_colors.size() - 1)]
	)
	building.position = local_position
	parent.add_child(building)
	_register_door(chunk, parent.position + _door_point(local_position, w, d))

func _add_village_house(
	parent: Node3D,
	local_position: Vector3,
	w: float,
	h: float,
	d: float,
	rng: RandomNumberGenerator,
	chunk: Vector2i
) -> void:
	var house := VillageHouseScene.instantiate() as VillageHouse
	house.setup(
		Vector3(w, h, d),
		village_colors[rng.randi_range(0, village_colors.size() - 1)]
	)
	house.position = local_position
	parent.add_child(house)
	_register_door(chunk, parent.position + _door_point(local_position, w, d))

func _add_tree(parent: Node3D, local_position: Vector3, rng: RandomNumberGenerator) -> void:
	var tree = TreeScene.instantiate()
	tree.position = local_position
	var crown = tree.get_node("Crown")
	var s := rng.randf_range(0.7, 1.3)
	crown.scale = Vector3(s, s, s)
	parent.add_child(tree)

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

func _chunk_seed(chunk: Vector2i) -> int:
	return hash("%d|%d|%d" % [chunk.x, chunk.y, random_seed])

# ----------------------------------
# Двери и парковки
# ----------------------------------

# Точка "двери" на наружной стороне здания.
func _door_point(local_position: Vector3, w: float, d: float) -> Vector3:
	var dir3 := Vector3.ZERO
	if abs(local_position.x) > abs(local_position.z):
		dir3 = Vector3(sign(local_position.x), 0.0, 0.0)
	else:
		dir3 = Vector3(0.0, 0.0, sign(local_position.z))
	if dir3 == Vector3.ZERO:
		dir3 = Vector3(0.0, 0.0, 1.0)
	var p := local_position + dir3 * (maxf(w, d) * 0.5 + 0.9)
	p.y = 0.0
	return p

func _register_door(chunk: Vector2i, world_pos: Vector3) -> void:
	if not building_doors.has(chunk):
		building_doors[chunk] = []
	building_doors[chunk].append(world_pos)

# Ближайшая дверь в радиусе. Если нет — вернёт далёкий "пустой" вектор.
func get_nearby_door(pos: Vector3, max_dist: float) -> Vector3:
	var center := Vector2i(int(floor(pos.x / spacing)), int(floor(pos.z / spacing)))
	var best := Vector3(999999.0, 0.0, 999999.0)
	var best_d := max_dist
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var c := Vector2i(center.x + dx, center.y + dy)
			if not building_doors.has(c):
				continue
			for door in building_doors[c]:
				var dd := pos.distance_to(door)
				if dd < best_d:
					best_d = dd
					best = door
	return best

# Случайное место у припаркованной машины.
func get_random_parking_spot() -> Vector3:
	var all := []
	for c in parking_spots.keys():
		if chunks.has(c):
			for s in parking_spots[c]:
				all.append(s)
	if all.is_empty():
		return Vector3(999999.0, 0.0, 999999.0)
	return all[randi() % all.size()]

# Парковка: площадка + ряды припаркованных машин.
func _generate_parking(root: Node3D, chunk: Vector2i, rng: RandomNumberGenerator) -> void:
	var pad_size := spacing * 0.62
	var pad := MeshInstance3D.new()
	var pad_mesh := BoxMesh.new()
	pad_mesh.size = Vector3(pad_size, 0.18, pad_size)
	pad.mesh = pad_mesh
	pad.position = Vector3(0.0, 0.04, 0.0)
	var pad_mat := StandardMaterial3D.new()
	pad_mat.albedo_color = Color(0.32, 0.32, 0.35)
	pad.material_override = pad_mat
	root.add_child(pad)

	if not parking_spots.has(chunk):
		parking_spots[chunk] = []

	for z in [-7.0, 7.0]:
		for i in 5:
			if rng.randf() > 0.75:
				continue  # пустое место
			var local := Vector3(-6.0 + i * 3.0, 0.0, z)
			var car := _make_parked_car(rng)
			car.position = local
			car.rotation_degrees.y = rng.randf_range(-6.0, 6.0)
			root.add_child(car)
			var spot := root.position + local + Vector3(1.3, 0.0, -sign(z) * 1.4)
			parking_spots[chunk].append(spot)

func _make_parked_car(rng: RandomNumberGenerator) -> StaticBody3D:
	var colors := [
		Color(0.72, 0.16, 0.16), Color(0.16, 0.32, 0.70),
		Color(0.82, 0.82, 0.84), Color(0.22, 0.22, 0.24),
		Color(0.90, 0.70, 0.25), Color(0.30, 0.60, 0.35),
	]
	var col_color: Color = colors[rng.randi_range(0, colors.size() - 1)]
	var body := StaticBody3D.new()
	body.collision_mask = 0
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.8, 0.7, 4.0)
	mesh.mesh = box
	mesh.position = Vector3(0.0, 0.55, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col_color
	mesh.material_override = mat
	var cabin := MeshInstance3D.new()
	var cabin_box := BoxMesh.new()
	cabin_box.size = Vector3(1.6, 0.55, 2.0)
	cabin.mesh = cabin_box
	cabin.position = Vector3(0.0, 1.1, -0.2)
	var cabin_mat := StandardMaterial3D.new()
	cabin_mat.albedo_color = Color(0.12, 0.12, 0.14)
	cabin.material_override = cabin_mat
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.9, 1.6, 4.1)
	col.shape = shape
	col.position = Vector3(0.0, 0.8, 0.0)
	body.add_child(mesh)
	body.add_child(cabin)
	body.add_child(col)
	return body

# ----------------------------------
# Заправки
# ----------------------------------

func get_gas_station(segment: Vector2i):
	if gas_stations.has(segment):
		return gas_stations[segment]
	return null

func _generate_gas_station(
	root: Node3D,
	chunk: Vector2i,
	rng: RandomNumberGenerator
) -> void:
	var key := Vector2i(chunk.x, chunk.y)
	var station = GasStationScene.instantiate()
	station.setup(key, spacing, road_width, rng)
	root.add_child(station)
	root.set_meta("gas_station_key", key)
	gas_stations[key] = station

# ----------------------------------
# Resources
# ----------------------------------

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