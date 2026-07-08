extends Node3D

@export var car: Vehicle
@export var ray_front_left: RayCast3D
@export var ray_front_right: RayCast3D
@export var ray_left: RayCast3D
@export var ray_right: RayCast3D
@export var navigation_agent: NavigationAgent3D;

@export var danger_distance: float = 2.0 # дистанция для торможения
@export var side_distance: float = 1.5 # дистанция для уклонения

enum State {IDLE, WAITING_TO_GO, GO}
var state = State.IDLE

func _physics_process(_delta: float) -> void:
	step(_delta)
	return
	var dist_fl = get_dist(ray_front_left)
	var dist_fr = get_dist(ray_front_right)
	var dist_l = get_dist(ray_left)
	var dist_r = get_dist(ray_right)

	var throttle: float = 1.0 # Газ
	var brake: float = 0.0
	var steer: float = 0.0
	var handbrake: float = 0.0

	if dist_l < danger_distance or dist_fl < danger_distance:
		steer = -1.0
	elif dist_r < danger_distance or dist_fr < danger_distance:
		steer = 1.0

	if dist_fr < danger_distance and dist_fl < danger_distance:
		throttle = 0.0
		brake = 1.0
		handbrake = 1.0
		# steer = -steer

	car.throttle_input = throttle
	car.brake_input = brake
	car.steering_input = steer
	car.handbrake_force = handbrake

	if car.current_gear == -1:
		car.brake_input = throttle
		car.throttle_input = brake

func get_dist(ray: RayCast3D) -> float:
		if ray.is_colliding():
			var hit_point = ray.get_collision_point()
			return ray.global_position.distance_to(hit_point)
		else:
			return 999.0 # очень большое число, если препятствия нет


func step(delta: float) -> void:
	match state:
		State.IDLE:
			_on_idle()
		State.WAITING_TO_GO:
			_on_waiting_to_go()
		State.GO:
			_on_go()


func _on_idle() -> void:
	state = State.WAITING_TO_GO


func _on_waiting_to_go() -> void:
	# генерируем новую цель
	print("Waiting to go")
	var new_target_position = get_new_target_position()
	navigation_agent.target_position = new_target_position
	state = State.GO

func get_new_target_position() -> Vector3:
	# случайная позиция рядом с изначальной позицией
	var max_distance = 10.0
	var new_target_position = car.global_position + Vector3(randf_range(-max_distance, max_distance), 0, randf_range(-max_distance, max_distance))
	print("New target position ", new_target_position)
	return new_target_position


func _on_go() -> void:
	# перемещаемся к цели
	var current_position = car.global_position
	var target_position = navigation_agent.get_next_path_position()
	move(target_position, current_position)

	print("Going to target position ", target_position)
	if car.global_position.distance_to(target_position) < 1.0:
		state = State.WAITING_TO_GO

func move(target_position: Vector3, current_position: Vector3) -> void:
	# перемещаемся к цели
	# 1. определяем направление к цели, и направляем колеса в нужную сторону
	var direction = (target_position - current_position).normalized()
	car.steering_input = direction.x
	# 2. вычисляем расстояние до цели
	var distance = current_position.distance_to(target_position)
	# 3. в зависимости от расстояния, определяем, нажимать на газ, либо на тормоз
	# ДОДЕЛАТЬ!
	if distance < 1.0:
		car.throttle_input = 0.0
		car.brake_input = 1.0
	else:
		car.throttle_input = 1.0
