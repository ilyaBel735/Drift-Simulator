class_name TrafficBot
extends CharacterBody3D

enum Phase { APPROACH, CROSS }
enum RefuelState { NONE, TO_QUEUE, WAIT_QUEUE, TO_PUMP, REFUELING, EXIT }

@export var max_speed := 12.0
@export var acceleration := 9.0
@export var braking := 18.0
@export var obstacle_stop_distance := 7.0
@export var intersection_stop_offset := 2.0
@export var yellow_commit_distance := 12.0

@export var fuel_max := 100.0
@export var fuel_use_per_second := 0.35
@export var refuel_threshold := 35.0
@export var refuel_chance := 0.75
@export var refuel_time_min := 4.0
@export var refuel_time_max := 8.0

var spacing := 48.0
var road_width := 12.0
var lane_offset := 3.0

var city: CityGenerator

var dir := Vector2i(1, 0)
var phase := Phase.APPROACH
var current_intersection := Vector2i.ZERO
var pending_intersection := Vector2i.ZERO
var points := []
var current_speed := 0.0

var fuel := 100.0

var refuel_state := RefuelState.NONE
var current_station: GasStation
var pump_index := -1
var refuel_target := Vector3.ZERO
var refuel_timer := 0.0

var saved_intersection := Vector2i.ZERO
var saved_dir := Vector2i(1, 0)

var tried_station_segment := Vector2i(999999, 999999)

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
	fuel = randf_range(50.0, fuel_max)

	if is_inside_tree():
		update_initial_orientation()


func update_initial_orientation() -> void:
	if points.size() > 0:
		var target: Vector3 = points[0]
		var look_dir := (target - global_position).normalized()

		if look_dir.length_squared() > 0.01:
			look_at(global_position + look_dir, Vector3.UP)


func _physics_process(delta: float) -> void:
	if fuel <= 0.0:
		queue_free()
		return

	if refuel_state != RefuelState.REFUELING:
		fuel = maxf(fuel - fuel_use_per_second * delta, 0.0)

	# Режим заправки имеет приоритет над обычным движением.
	if refuel_state != RefuelState.NONE:
		_process_refuel(delta)
		return

	_maybe_start_refuel()

	if refuel_state != RefuelState.NONE:
		_process_refuel(delta)
		return

	# Обычное движение по ПДД.
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

		var state := _get_light_state()

		if state == TrafficRules.LightState.GREEN:
			_enter_intersection()
		elif state == TrafficRules.LightState.YELLOW:
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


# ----------------------------------
# Traffic logic
# ----------------------------------

func _get_desired_speed(dist: float) -> float:
	var desired := max_speed

	if phase == Phase.APPROACH:
		var state := _get_light_state()

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


func _get_light_state() -> int:
	if city != null and city.has_method("has_traffic_lights_at"):
		if not city.has_traffic_lights_at(current_intersection):
			return TrafficRules.LightState.GREEN

	return TrafficRules.get_state(current_intersection, dir)


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

	if new_dir != old_dir:
		points.append(center)

	points.append(_exit_point(pending_intersection, new_dir))

	current_speed = max_speed * 0.3


func _begin_approach_next() -> void:
	current_intersection = pending_intersection + dir
	phase = Phase.APPROACH
	points = [_stop_line_point(current_intersection, dir)]


func _choose_next_dir(old: Vector2i) -> Vector2i:
	var right := Vector2i(-old.y, old.x)
	var left := Vector2i(old.y, -old.x)
	var back := -old

	var candidates := []

	if _can_go_dir(pending_intersection, old):
		candidates.append(old)

	if _can_go_dir(pending_intersection, right):
		candidates.append(right)

	if candidates.is_empty():
		if _can_go_dir(pending_intersection, left):
			candidates.append(left)

		if _can_go_dir(pending_intersection, back):
			candidates.append(back)

	if candidates.is_empty():
		return old

	if candidates.has(old) and randf() < 0.6:
		return old

	if candidates.has(right) and randf() < 0.6:
		return right

	return candidates[randi() % candidates.size()]


func _can_go_dir(intersection: Vector2i, direction: Vector2i) -> bool:
	if city == null:
		return true

	return city.has_road_segment(intersection, direction)


func _obstacle_ahead() -> bool:
	if ray == null or not ray.is_colliding():
		return false

	var collider := ray.get_collider()
	if collider == null:
		return false

	var dist := global_position.distance_to(ray.get_collision_point())
	if dist > obstacle_stop_distance:
		return false

	if collider is PlayerCar or collider is TrafficBot or collider is Pedestrian:
		return true

	return false


# ----------------------------------
# Refuel logic
# ----------------------------------

func _maybe_start_refuel() -> void:
	if refuel_state != RefuelState.NONE:
		return

	if city == null or fuel > refuel_threshold:
		return

	if phase != Phase.APPROACH:
		return

	# Пока заправки поддерживаем только на горизонтальных дорогах.
	if dir.y != 0:
		return

	if not city.has_method("get_gas_station"):
		return

	var segment := _current_segment_key()

	if segment == tried_station_segment:
		return

	tried_station_segment = segment

	var station = city.call("get_gas_station", segment) as GasStation

	if station == null or not is_instance_valid(station):
		return

	var entrance := station.get_entrance_global()
	var dist := global_position.distance_to(entrance)

	if dist < 8.0 or dist > 70.0:
		return

	if randf() > refuel_chance:
		return

	saved_intersection = current_intersection
	saved_dir = dir

	current_station = station
	pump_index = -1
	refuel_state = RefuelState.TO_QUEUE


func _current_segment_key() -> Vector2i:
	if dir.x > 0:
		return Vector2i(current_intersection.x - 1, current_intersection.y)

	if dir.x < 0:
		return Vector2i(current_intersection.x, current_intersection.y)

	if dir.y > 0:
		return Vector2i(current_intersection.x, current_intersection.y - 1)

	return Vector2i(current_intersection.x, current_intersection.y)


func _process_refuel(delta: float) -> void:
	if not is_instance_valid(current_station):
		_cancel_refuel()
		return

	match refuel_state:
		RefuelState.TO_QUEUE, RefuelState.WAIT_QUEUE:
			var result := current_station.request(self, dir)

			if result.get("skip", false):
				_cancel_refuel()
				return

			if result.get("assigned", false):
				pump_index = int(result.get("spot", -1))
				refuel_target = result.get("point", global_position)
				refuel_state = RefuelState.TO_PUMP
			else:
				refuel_target = result.get("point", global_position)
				refuel_state = RefuelState.WAIT_QUEUE

			_move_to_refuel_target(delta, 4.5)

		RefuelState.TO_PUMP:
			_move_to_refuel_target(delta, 4.5)

			if _refuel_target_reached():
				refuel_state = RefuelState.REFUELING
				refuel_timer = randf_range(refuel_time_min, refuel_time_max)
				velocity = Vector3.ZERO

		RefuelState.REFUELING:
			velocity = Vector3.ZERO
			move_and_slide()

			refuel_timer -= delta

			if refuel_timer <= 0.0:
				fuel = fuel_max

				if is_instance_valid(current_station):
					current_station.release_spot(pump_index)

				pump_index = -1
				refuel_target = current_station.get_exit_point(saved_dir)
				refuel_state = RefuelState.EXIT

		RefuelState.EXIT:
			_move_to_refuel_target(delta, 5.0)

			if _refuel_target_reached():
				_finish_refuel()


func _move_to_refuel_target(delta: float, speed_limit: float) -> void:
	var to_target := refuel_target - global_position
	to_target.y = 0.0

	var dist := to_target.length()

	if dist < 0.8:
		current_speed = move_toward(current_speed, 0.0, braking * delta)
		velocity = Vector3.ZERO
		move_and_slide()
		return

	var desired := speed_limit

	if _obstacle_ahead():
		desired = 0.0

	if desired > current_speed:
		current_speed = move_toward(current_speed, desired, acceleration * delta)
	else:
		current_speed = move_toward(current_speed, desired, braking * delta)

	velocity = to_target.normalized() * current_speed
	velocity.y = 0.0

	move_and_slide()

	global_position.y = 0.0

	if current_speed > 0.1:
		_look_toward(velocity.normalized())


func _refuel_target_reached() -> bool:
	var to_target := refuel_target - global_position
	to_target.y = 0.0

	return to_target.length() < 1.2


func _cancel_refuel() -> void:
	if is_instance_valid(current_station):
		if pump_index >= 0:
			current_station.release_spot(pump_index)

		current_station.remove_from_queue(self)

	current_station = null
	pump_index = -1
	refuel_state = RefuelState.NONE

	_resume_normal_route()


func _finish_refuel() -> void:
	if is_instance_valid(current_station):
		current_station.remove_from_queue(self)

	current_station = null
	pump_index = -1
	refuel_state = RefuelState.NONE

	_resume_normal_route()


func _resume_normal_route() -> void:
	dir = saved_dir
	current_intersection = saved_intersection
	phase = Phase.APPROACH
	points = [_stop_line_point(current_intersection, dir)]


# ----------------------------------
# Geometry helpers
# ----------------------------------

func _intersection_world(intersection: Vector2i) -> Vector3:
	return Vector3(intersection.x * spacing, 0.0, intersection.y * spacing)


func _dir3(direction: Vector2i) -> Vector3:
	return Vector3(direction.x, 0.0, direction.y)


func _right_offset(direction: Vector2i) -> Vector3:
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
