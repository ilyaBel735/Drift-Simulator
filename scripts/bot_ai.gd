extends Node3D

@export var car: Vehicle
@export var ray_front_left: RayCast3D
@export var ray_front_right: RayCast3D
@export var ray_left: RayCast3D
@export var ray_right: RayCast3D

@export var danger_distance: float = 2.0   # дистанция для торможения
@export var side_distance: float = 1.5     # дистанция для уклонения

func _physics_process(_delta: float) -> void:

	var dist_fl = get_dist(ray_front_left)
	var dist_fr = get_dist(ray_front_right)
	var dist_l  = get_dist(ray_left)
	var dist_r  = get_dist(ray_right)

	var throttle: float = 1.0  #Газ
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
			return 999.0   # очень большое число, если препятствия нет
