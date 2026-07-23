extends Node3D

@export var car: Vehicle
@export var ray_front_left: RayCast3D
@export var ray_front_right: RayCast3D
@export var ray_left: RayCast3D
@export var ray_right: RayCast3D
@export var navigation_agent: NavigationAgent3D

@export var danger_distance: float = 2.0   # дистанция для торможения
@export var side_distance: float = 1.5     # дистанция для уклонения

enum State {IDLE, WAITING_TO_GO, GO}
var state = State.IDLE

func _ready():
	# Подключаем сигнал достижения цели
	navigation_agent.target_reached.connect(_on_target_reached)

func _physics_process(delta: float) -> void:
	# 1. Обновляем состояние и базовое управление (следование по маршруту)
	step(delta)
	
	# 2. Получаем данные с дальномеров
	var dist_fl = get_dist(ray_front_left)
	var dist_fr = get_dist(ray_front_right)
	var dist_l = get_dist(ray_left)
	var dist_r = get_dist(ray_right)

	# 3. Уклонение от препятствий (корректируем руль)
	if dist_l < side_distance or dist_fl < danger_distance:
		# препятствие слева или перед левым колесом – поворачиваем вправо
		car.steering_input = clamp(car.steering_input + 0.3, -1.0, 1.0)
	elif dist_r < side_distance or dist_fr < danger_distance:
		# препятствие справа – поворачиваем влево
		car.steering_input = clamp(car.steering_input - 0.3, -1.0, 1.0)

	# 4. Торможение и ручник при критическом сближении
	if dist_fr < danger_distance and dist_fl < danger_distance:
		car.throttle_input = 0.0
		car.brake_input = 1.0
		car.handbrake_force = 1.0
	elif dist_fr < danger_distance or dist_fl < danger_distance:
		# если опасность только с одной стороны – сбрасываем газ
		car.throttle_input = min(car.throttle_input, 0.5)

	# 5. Если машина вдруг оказалась на задней передаче (необязательно)
	if car.current_gear == -1:
		car.brake_input = car.throttle_input
		car.throttle_input = car.brake_input

func get_dist(ray: RayCast3D) -> float:
	if ray.is_colliding():
		var hit_point = ray.get_collision_point()
		return ray.global_position.distance_to(hit_point)
	return 999.0   # очень большое число, если препятствия нет


# ----- Управление состояниями -----

func step(_delta: float) -> void:
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
	print("Waiting to go – generating new target")
	var new_target_position = get_new_target_position()
	navigation_agent.target_position = new_target_position
	state = State.GO

func get_new_target_position() -> Vector3:
	# Генерирует случайную цель в радиусе 10 м от текущей позиции.
	# В идеале точка должна лежать на навигационной сетке – при необходимости
	# используйте NavigationServer3D.map_get_random_point().
	var max_distance = 10.0
	var random_offset = Vector3(
		randf_range(-max_distance, max_distance),
		0,
		randf_range(-max_distance, max_distance)
	)
	var new_target = car.global_position + random_offset
	new_target.y = 1.0   # фиксируем высоту (подберите под вашу сцену)
	print("New target position: ", new_target)
	return new_target

func _on_go() -> void:
	# Следуем по маршруту
	var current_position = car.global_position
	var target_position = navigation_agent.get_next_path_position()
	move(target_position, current_position)

func _on_target_reached() -> void:
	# Когда цель достигнута, переходим к генерации новой
	state = State.WAITING_TO_GO


# ----- Движение к цели -----

func move(target_position: Vector3, current_position: Vector3) -> void:
	var to_target = (target_position - current_position).normalized()
	
	# Определяем направление "вперёд" машины.
	# В Godot 4 ось -Z считается вперёд, но если ваша модель развёрнута, попробуйте:
	# var forward = car.global_transform.basis.z   (без минуса)
	var forward = -car.global_transform.basis.z

	# Угол между векторами (в радианах)
	var angle = forward.angle_to(to_target)
	
	# Определяем знак поворота (по оси Y)
	var cross = forward.cross(to_target)
	var sign = sign(cross.y)

	# Коэффициент усиления – уменьшен до 0.8 для плавности
	var steer_value = clamp(angle * 0.8, -1.0, 1.0) * sign
	car.steering_input = steer_value

	# Отладка – можно включить, чтобы увидеть значения
	# print("Angle: ", angle, " steer: ", steer_value)

	var distance = current_position.distance_to(target_position)
	if distance < 0.5:
		car.throttle_input = 0.0
		car.brake_input = 1.0
	else:
		car.throttle_input = 1.0
		car.brake_input = 0.0