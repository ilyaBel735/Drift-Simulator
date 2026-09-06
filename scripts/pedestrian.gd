class_name Pedestrian
extends CharacterBody3D

enum State { IDLE, WALK, WAIT, CROSS }

@export var walk_speed := 2.0
@export var cross_speed := 4.0
@export var cross_chance := 0.35
@export var max_wait_time := 18.0
@export var red_delay_time := 0.6

var city: CityGenerator

var spacing := 48.0
var road_width := 12.0

var current_block := Vector2i.ZERO
var current_corner := 0
var walk_direction := 1

var state := State.IDLE
var target_point := Vector3.ZERO
var target_corner := -1

var crossing_intersection := Vector2i.ZERO
var crossing_target_block := Vector2i.ZERO
var crossing_target_corner := 0
var crossing_target_point := Vector3.ZERO

var idle_time := 0.0
var wait_time := 0.0
var red_delay := 0.0


func _ready() -> void:
    motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
    add_to_group("pedestrian")


func setup(
    city_ref: CityGenerator,
    block: Vector2i,
    corner: int,
    position_value: Vector3
) -> void:
    city = city_ref
    spacing = city.spacing
    road_width = city.road_width

    current_block = block
    current_corner = corner

    global_position = position_value

    walk_direction = 1 if randf() < 0.5 else -1

    state = State.IDLE
    idle_time = randf_range(0.3, 1.5)
    target_point = global_position


func _physics_process(delta: float) -> void:
    match state:
        State.IDLE:
            velocity = Vector3.ZERO
            idle_time -= delta

            if idle_time <= 0.0:
                _choose_action_at_corner()

        State.WALK, State.CROSS:
            _move_to_target(delta)

        State.WAIT:
            velocity = Vector3.ZERO
            move_and_slide()

            wait_time += delta

            if wait_time > max_wait_time:
                red_delay = 0.0
                _choose_action_at_corner()
                return

            if not is_instance_valid(city):
                _choose_action_at_corner()
                return

            if not city.chunks.has(crossing_target_block):
                red_delay = 0.0
                _choose_action_at_corner()
                return

            if _crossing_signal_allows():
                red_delay += delta

                if red_delay >= red_delay_time:
                    target_point = crossing_target_point
                    state = State.CROSS
            else:
                red_delay = 0.0


func _move_to_target(_delta: float) -> void:
    var to_target := target_point - global_position
    to_target.y = 0.0

    var dist := to_target.length()

    if dist < 0.35:
        _on_target_reached()
        return

    var speed := cross_speed if state == State.CROSS else walk_speed

    velocity = to_target.normalized() * speed
    velocity.y = 0.0

    move_and_slide()

    global_position.y = 0.0


func _on_target_reached() -> void:
    if state == State.WALK:
        if target_corner >= 0:
            current_corner = target_corner

        state = State.IDLE
        idle_time = randf_range(0.4, 2.0)

    elif state == State.CROSS:
        current_block = crossing_target_block
        current_corner = crossing_target_corner

        state = State.IDLE
        idle_time = randf_range(0.5, 2.5)


func _choose_action_at_corner() -> void:
    if randf() < cross_chance and _try_prepare_crossing():
        return

    # Иногда пешеход разворачивается.
    if randf() < 0.15:
        walk_direction = -walk_direction

    target_corner = posmod(current_corner + walk_direction, 4)
    target_point = _corner_point(current_block, target_corner)

    state = State.WALK


func _try_prepare_crossing() -> bool:
    if not is_instance_valid(city):
        return false

    var options := _get_crossing_options()
    options.shuffle()

    for opt in options:
        var target_block: Vector2i = opt["target_block"]
        var target_corner_value: int = opt["target_corner"]

        if not _is_crossing_road_available(target_block):
            continue

        if city.chunks.has(target_block):
            crossing_intersection = _corner_intersection(current_block, current_corner)
            crossing_target_block = target_block
            crossing_target_corner = target_corner_value
            crossing_target_point = _corner_point(target_block, target_corner_value)

            state = State.WAIT
            wait_time = 0.0
            red_delay = 0.0

            return true

    return false

func _is_crossing_road_available(target_block: Vector2i) -> bool:
    if city == null:
        return true

    # Переход вверх.
    if target_block.y == current_block.y - 1:
        return city.has_horizontal_road(current_block.x, current_block.y)

    # Переход вниз.
    if target_block.y == current_block.y + 1:
        return city.has_horizontal_road(current_block.x, current_block.y + 1)

    # Переход влево.
    if target_block.x == current_block.x - 1:
        return city.has_vertical_road(current_block.x, current_block.y)

    # Переход вправо.
    if target_block.x == current_block.x + 1:
        return city.has_vertical_road(current_block.x + 1, current_block.y)

    return false


func _get_crossing_options() -> Array:
    var options := []

    match current_corner:
        0:
            # Верхняя дорога
            options.append({
                "target_block": Vector2i(current_block.x, current_block.y - 1),
                "target_corner": 3,
            })

            # Левая дорога
            options.append({
                "target_block": Vector2i(current_block.x - 1, current_block.y),
                "target_corner": 1,
            })

        1:
            # Верхняя дорога
            options.append({
                "target_block": Vector2i(current_block.x, current_block.y - 1),
                "target_corner": 2,
            })

            # Правая дорога
            options.append({
                "target_block": Vector2i(current_block.x + 1, current_block.y),
                "target_corner": 0,
            })

        2:
            # Нижняя дорога
            options.append({
                "target_block": Vector2i(current_block.x, current_block.y + 1),
                "target_corner": 1,
            })

            # Правая дорога
            options.append({
                "target_block": Vector2i(current_block.x + 1, current_block.y),
                "target_corner": 3,
            })

        3:
            # Нижняя дорога
            options.append({
                "target_block": Vector2i(current_block.x, current_block.y + 1),
                "target_corner": 0,
            })

            # Левая дорога
            options.append({
                "target_block": Vector2i(current_block.x - 1, current_block.y),
                "target_corner": 2,
            })

    return options


func _corner_intersection(block: Vector2i, corner: int) -> Vector2i:
    match corner:
        0:
            return block
        1:
            return Vector2i(block.x + 1, block.y)
        2:
            return Vector2i(block.x + 1, block.y + 1)
        _:
            return Vector2i(block.x, block.y + 1)


func _corner_point(block: Vector2i, corner: int) -> Vector3:
    var center := Vector3(
        (block.x + 0.5) * spacing,
        0.0,
        (block.y + 0.5) * spacing
    )

    var h := _walk_half()

    match corner:
        0:
            return center + Vector3(-h, 0.0, -h)
        1:
            return center + Vector3(h, 0.0, -h)
        2:
            return center + Vector3(h, 0.0, h)
        _:
            return center + Vector3(-h, 0.0, h)


func _walk_half() -> float:
    return maxf(2.0, spacing * 0.5 - road_width * 0.5 - 1.5)

func _crossing_signal_allows() -> bool:
    if is_instance_valid(city) and city.has_method("has_traffic_lights_at"):
        if not city.has_traffic_lights_at(crossing_intersection):
            return true

    return TrafficRules.are_all_red(crossing_intersection)