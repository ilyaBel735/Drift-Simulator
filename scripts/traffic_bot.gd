class_name TrafficBot
extends CharacterBody3D

enum Phase {APPROACH, CROSS}

@export var max_speed := 12.0
@export var acceleration := 9.0
@export var braking := 18.0
@export var obstacle_stop_distance := 7.0
@export var intersection_stop_offset := 2.0
@export var yellow_commit_distance := 12.0

var spacing := 48.0
var road_width := 12.0
var lane_offset := 3.0

var dir := Vector2i(1, 0)
var phase := Phase.APPROACH
var current_intersection := Vector2i.ZERO
var pending_intersection := Vector2i.ZERO
var points := []
var current_speed := 0.0

@onready var ray := get_node_or_null("RayCast3D") as RayCast3D


func _ready() -> void:
    motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
    add_to_group("traffic_bot")

    if ray:
        ray.exclude_parent = true
        ray.collision_mask = 7

    update_initial_orientation()


func setup(
    spacing_value: float,
    road_width_value: float,
    spawn_position: Vector3,
    direction: Vector2i,
    next_intersection: Vector2i
) -> void:
    spacing = spacing_value
    road_width = road_width_value
    lane_offset = road_width * 0.25

    dir = direction
    current_intersection = next_intersection
    pending_intersection = next_intersection
    phase = Phase.APPROACH

    global_position = spawn_position
    points = [_stop_line_point(current_intersection, dir)]
    current_speed = max_speed * 0.4

    if is_inside_tree():
        update_initial_orientation()


func update_initial_orientation() -> void:
    if points.size() > 0:
        var target: Vector3 = points[0]
        var look_dir := (target - global_position).normalized()

        if look_dir.length_squared() > 0.01:
            look_at(global_position + look_dir, Vector3.UP)


func _physics_process(delta: float) -> void:
    if points.is_empty():
        if phase == Phase.CROSS:
            _begin_approach_next()
        else:
            _stop(delta)
        return

    var target: Vector3 = points[0]
    var to_target := target - global_position
    to_target.y = 0.0

    var dist := to_target.length()

    # Машина у стоп-линии.
    if phase == Phase.APPROACH and dist < 1.2:
        if _obstacle_ahead():
            _stop(delta)
            return

        var state := TrafficRules.get_state(current_intersection, dir)

        if state == TrafficRules.LightState.GREEN:
            _enter_intersection()
        elif state == TrafficRules.LightState.YELLOW:
            # Если уже у стоп-линии, безопаснее завершить проезд.
            _enter_intersection()
        else:
            _stop(delta)

        return

    # Достижение промежуточной точки.
    if dist < 0.9:
        points.pop_front()

        if points.is_empty() and phase == Phase.CROSS:
            _begin_approach_next()

        return

    var desired_speed := _get_desired_speed(dist)

    if desired_speed <= 0.01:
        _stop(delta)
        return

    var move_dir := to_target.normalized()

    if desired_speed > current_speed:
        current_speed = move_toward(current_speed, desired_speed, acceleration * delta)
    else:
        current_speed = move_toward(current_speed, desired_speed, braking * delta)

    velocity = move_dir * current_speed
    velocity.y = 0.0

    move_and_slide()

    global_position.y = 0.0

    if current_speed > 0.1:
        _look_toward(velocity.normalized())


func _get_desired_speed(dist: float) -> float:
    var desired := max_speed

    if phase == Phase.APPROACH:
        var state := TrafficRules.get_state(current_intersection, dir)

        if state == TrafficRules.LightState.GREEN:
            desired = max_speed
        elif state == TrafficRules.LightState.YELLOW:
            if dist <= yellow_commit_distance:
                desired = max_speed
            else:
                desired = clampf((dist - 0.75) * 2.5, 0.0, max_speed)
        else:
            desired = clampf((dist - 0.75) * 2.5, 0.0, max_speed)
    else:
        desired = max_speed * 0.65

    if _obstacle_ahead():
        desired = 0.0

    return desired


func _stop(delta: float) -> void:
    current_speed = move_toward(current_speed, 0.0, braking * delta)
    velocity = Vector3.ZERO
    move_and_slide()


func _enter_intersection() -> void:
    if _obstacle_ahead():
        return

    pending_intersection = current_intersection

    var old_dir := dir
    var new_dir := _choose_next_dir(old_dir)

    dir = new_dir
    phase = Phase.CROSS
    points.clear()

    var center := _intersection_world(pending_intersection)

    # Если поворачиваем, добавляем центр перекрестка как промежуточную точку.
    if new_dir != old_dir:
        points.append(center)

    points.append(_exit_point(pending_intersection, new_dir))

    current_speed = max_speed * 0.3


func _begin_approach_next() -> void:
    current_intersection = pending_intersection + dir
    phase = Phase.APPROACH
    points = [_stop_line_point(current_intersection, dir)]


func _choose_next_dir(old: Vector2i) -> Vector2i:
    # Только прямо или направо.
    # Это упрощает ПДД и убирает сложные встречные левые повороты.
    var right := Vector2i(-old.y, old.x)

    var r := randf()
    if r < 0.65:
        return old

    return right


func _obstacle_ahead() -> bool:
    if ray == null or not ray.is_colliding():
        return false

    var collider := ray.get_collider()
    if collider == null:
        return false

    var dist := global_position.distance_to(ray.get_collision_point())
    if dist > obstacle_stop_distance:
        return false

    # Реагируем на игрока и других ботов.
    # Здания игнорируем, чтобы боты не останавливались из-за углов домов.
    if collider is PlayerCar or collider is TrafficBot or collider is Pedestrian:
        return true
        
    return false


func _intersection_world(intersection: Vector2i) -> Vector3:
    return Vector3(intersection.x * spacing, 0.0, intersection.y * spacing)


func _dir3(direction: Vector2i) -> Vector3:
    return Vector3(direction.x, 0.0, direction.y)


func _right_offset(direction: Vector2i) -> Vector3:
    # Правая сторона относительно направления движения.
    return Vector3(-direction.y, 0.0, direction.x) * lane_offset


func _stop_line_point(intersection: Vector2i, direction: Vector2i) -> Vector3:
    var stop_dist := road_width * 0.5 + intersection_stop_offset
    return _intersection_world(intersection) - _dir3(direction) * stop_dist + _right_offset(direction)


func _exit_point(intersection: Vector2i, direction: Vector2i) -> Vector3:
    var exit_dist := road_width * 0.5 + 1.0
    return _intersection_world(intersection) + _dir3(direction) * exit_dist + _right_offset(direction)


func _look_toward(direction: Vector3) -> void:
    if direction.length_squared() > 0.01:
        look_at(global_position + direction, Vector3.UP)