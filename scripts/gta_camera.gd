extends Node3D
class_name GTACamera
## Камера в стиле GTA San Andreas с переключением на вид от первого лица.
## Исправлено: дёрганье, уход под землю, жёсткая привязка в кокпите.

# === РЕЖИМЫ КАМЕРЫ ===
enum CameraMode { THIRD_PERSON, FIRST_PERSON }

# === ЦЕЛЬ ===
@export var target: Node3D = null
@export var target_offset := Vector3(0.0, 1.5, 0.0)

# === ДИСТАНЦИЯ (третье лицо) ===
@export_group("Distance")
@export var desired_distance := 8.5
@export var min_distance := 2.5
@export var max_distance := 16.0
@export var follow_smoothness := 8.0

# === ВРАЩЕНИЕ ===
@export_group("Rotation")
@export var initial_yaw := 0.0
@export var initial_pitch := -12.0
@export var min_pitch := -75.0
@export var max_pitch := 55.0
@export var mouse_sensitivity := 0.25
@export var keyboard_sensitivity := 120.0

# === АВТО-ПОВОРОТ ===
@export_group("Auto Rotate")
@export var auto_rotate_enabled := true
@export var auto_rotate_smoothness := 2.5
@export var auto_rotate_strength := 0.5
@export var min_speed_to_rotate := 5.0

# === КОЛЛИЗИИ ===
@export_group("Collision")
@export var enable_collision := true
@export_flags_3d_physics var collision_mask := 1
@export var collision_margin := 0.4
@export var collision_sphere_radius := 0.4

# === ЗАЩИТА ОТ УХОДА ПОД ЗЕМЛЮ ===
@export_group("Ground Protection")
@export var min_height_above_target := 0.8
@export var ground_ray_margin := 0.3
@export_flags_3d_physics var ground_mask := 1

# === ЭФФЕКТЫ ===
@export_group("Effects")
@export var dynamic_fov := true
@export var base_fov := 75.0
@export var max_fov := 85.0
@export var dynamic_distance := true
@export var max_distance_bonus := 2.5
@export var reference_speed := 35.0

# === ПЕРВОЕ ЛИЦО ===
@export_group("First Person")
## Позиция камеры внутри машины (относительно центра машины)
@export var cockpit_position := Vector3(0.0, 1.1, -0.3)
## Небольшой сдвиг назад (чтобы не видеть капот в упор)
@export var cockpit_look_offset := Vector3(0.0, 0.15, -1.0)
## FOV от первого лица
@export var first_person_fov := 80.0
## Разрешить вращение мышью в режиме первого лица
@export var first_person_look_enabled := true
## Максимальный угол обзора мышью (градусы)
@export var first_person_look_limit := 60.0
## Скорость обзора мышью
@export var first_person_look_speed := 0.6
## Плавность возврата обзора к центру
@export var first_person_look_return_speed := 4.0
## Плавность перехода между режимами
@export var transition_speed := 8.0

# === СОСТОЯНИЕ ===
var _yaw := 0.0
var _pitch := 0.0
var _current_distance := 0.0
var _smoothed_position := Vector3.ZERO
var _smoothed_look_target := Vector3.ZERO
var _smoothed_target_velocity := Vector3.ZERO
var _camera: Camera3D = null
var _is_first_frame := true

# Режимы
var _camera_mode := CameraMode.THIRD_PERSON
var _is_transitioning := false

# Обзор в первом лице
var _fp_look_yaw := 0.0
var _fp_look_pitch := 0.0


func _ready() -> void:
	_yaw = deg_to_rad(initial_yaw)
	_pitch = deg_to_rad(initial_pitch)
	_current_distance = desired_distance
	
	_camera = _find_or_create_camera()
	_camera.fov = base_fov
	_camera.near = 0.1
	_camera.far = 800.0
	_camera.make_current()
	
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# === ВАЖНО: камера обрабатывается ПОСЛЕ машины ===
	# Это гарантирует, что мы читаем позицию после физики
	set_physics_process_priority(100)
	
	if not is_instance_valid(target):
		await get_tree().process_frame
		target = _find_player()
		if not target:
			push_warning("GTACamera: target is null!")


func _find_or_create_camera() -> Camera3D:
	for child in get_children():
		if child is Camera3D:
			return child
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	add_child(cam)
	return cam


func _find_player() -> Node3D:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0]
	return null


func _unhandled_input(event: InputEvent) -> void:
	# Переключение режима (клавиша V)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_V:
			_toggle_camera_mode()
			return
	
	# Мышь
	if event is InputEventMouseMotion and DisplayServer.mouse_get_mode() == DisplayServer.MOUSE_MODE_CAPTURED:
		if _camera_mode == CameraMode.THIRD_PERSON:
			_yaw -= event.relative.x * mouse_sensitivity * 0.01745
			_pitch -= event.relative.y * mouse_sensitivity * 0.01745
			_pitch = clampf(_pitch, deg_to_rad(min_pitch), deg_to_rad(max_pitch))
		elif _camera_mode == CameraMode.FIRST_PERSON and first_person_look_enabled:
			_fp_look_yaw -= event.relative.x * mouse_sensitivity * first_person_look_speed * 0.01745
			_fp_look_pitch -= event.relative.y * mouse_sensitivity * first_person_look_speed * 0.01745
			var limit := deg_to_rad(first_person_look_limit)
			_fp_look_yaw = clampf(_fp_look_yaw, -limit, limit)
			_fp_look_pitch = clampf(_fp_look_pitch, -limit * 0.7, limit * 0.7)
	
	if event.is_action_pressed("ui_cancel"):
		if DisplayServer.mouse_get_mode() == DisplayServer.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _toggle_camera_mode() -> void:
	if _camera_mode == CameraMode.THIRD_PERSON:
		_camera_mode = CameraMode.FIRST_PERSON
	else:
		_camera_mode = CameraMode.THIRD_PERSON
		_fp_look_yaw = 0.0
		_fp_look_pitch = 0.0
	_is_transitioning = true


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	
	# === РЕЖИМ ПЕРВОГО ЛИЦА: ЖЁСТКАЯ ПРИВЯЗКА ===
	if _camera_mode == CameraMode.FIRST_PERSON:
		_process_first_person(delta)
		return
	
	# === РЕЖИМ ТРЕТЬЕГО ЛИЦА: как раньше ===
	_process_third_person(delta)


# ============================================================
# ПЕРВОЕ ЛИЦО - ЖЁСТКАЯ ПРИВЯЗКА К МАШИНЕ (БЕЗ СГЛАЖИВАНИЯ!)
# ============================================================
func _process_first_person(delta: float) -> void:
	# Сглаживание скорости для эффектов
	var raw_velocity := Vector3.ZERO
	if target is CharacterBody3D:
		raw_velocity = (target as CharacterBody3D).velocity
	_smoothed_target_velocity = _exp_smooth(_smoothed_target_velocity, raw_velocity, 10.0, delta)
	
	# FOV от скорости
	var speed_ratio := clampf(_smoothed_target_velocity.length() / reference_speed, 0.0, 1.0)
	speed_ratio = speed_ratio * speed_ratio
	if dynamic_fov:
		_camera.fov = lerpf(first_person_fov, first_person_fov + 5.0, speed_ratio)
	
	# === ЖЁСТКАЯ ПРИВЯЗКА К ТРАНСФОРМУ МАШИНЫ ===
	var car_transform := target.global_transform
	var cockpit_pos := car_transform * cockpit_position
	
	# === ОБЗОР МЫШЬЮ (сглаживаем только углы обзора, НЕ позицию) ===
	if first_person_look_enabled:
		# Плавный возврат обзора к центру при движении
		var speed_factor := clampf(_smoothed_target_velocity.length() / 20.0, 0.0, 1.0)
		var return_t := 1.0 - exp(-first_person_look_return_speed * speed_factor * delta)
		_fp_look_yaw = lerpf(_fp_look_yaw, 0.0, return_t)
		_fp_look_pitch = lerpf(_fp_look_pitch, 0.0, return_t)
	
	# === ПЛАВНЫЙ ПЕРЕХОД ИЗ ТРЕТЬЕГО ЛИЦА ===
	if _is_transitioning:
		var t := 1.0 - exp(-transition_speed * delta)
		_camera.global_position = _camera.global_position.lerp(cockpit_pos, t)
		if _camera.global_position.distance_to(cockpit_pos) < 0.05:
			_is_transitioning = false
	else:
		# ЖЁСТКАЯ привязка без сглаживания!
		_camera.global_position = cockpit_pos
	
	# === НАПРАВЛЕНИЕ ВЗГЛЯДА ===
	# Базовое направление машины (-Z это вперёд)
	var car_basis := car_transform.basis
	var forward := -car_basis.z
	var up := car_basis.y
	var right := car_basis.x
	
	# Применяем обзор мышью к направлению взгляда
	var look_dir := forward
	look_dir = look_dir.rotated(Vector3.UP, _fp_look_yaw)
	look_dir = look_dir.rotated(right, _fp_look_pitch)
	look_dir = look_dir.normalized()
	
	# Точка взгляда = позиция камеры + направление * дистанция
	var look_target := _camera.global_position + look_dir * 100.0 + car_basis * cockpit_look_offset
	
	_camera.look_at(look_target, up)
	
	# Сбрасываем сглаживание для возврата в третье лицо
	_smoothed_position = _camera.global_position
	_smoothed_look_target = look_target


# ============================================================
# ТРЕТЬЕ ЛИЦО - как раньше
# ============================================================
func _process_third_person(delta: float) -> void:
	# Ввод вращения клавиатурой
	if Input.is_action_pressed("ui_left"):
		_yaw += deg_to_rad(keyboard_sensitivity) * delta
	if Input.is_action_pressed("ui_right"):
		_yaw -= deg_to_rad(keyboard_sensitivity) * delta
	if Input.is_action_pressed("ui_up"):
		_pitch -= deg_to_rad(keyboard_sensitivity * 0.6) * delta
	if Input.is_action_pressed("ui_down"):
		_pitch += deg_to_rad(keyboard_sensitivity * 0.6) * delta
	_pitch = clampf(_pitch, deg_to_rad(min_pitch), deg_to_rad(max_pitch))
	
	# Сглаживание скорости машины
	var raw_velocity := Vector3.ZERO
	if target is CharacterBody3D:
		raw_velocity = (target as CharacterBody3D).velocity
	_smoothed_target_velocity = _exp_smooth(_smoothed_target_velocity, raw_velocity, 10.0, delta)
	
	var target_pos := target.global_position + target_offset
	
	# Эффекты скорости
	var speed_ratio := clampf(_smoothed_target_velocity.length() / reference_speed, 0.0, 1.0)
	speed_ratio = speed_ratio * speed_ratio
	
	if dynamic_fov:
		_camera.fov = lerpf(base_fov, max_fov, speed_ratio)
	
	# Авто-поворот
	if auto_rotate_enabled and _smoothed_target_velocity.length() > min_speed_to_rotate:
		var velocity_forward := -_smoothed_target_velocity.normalized()
		var target_yaw := atan2(-velocity_forward.x, -velocity_forward.z)
		var delta_angle := wrapf(target_yaw - _yaw, -PI, PI)
		if abs(delta_angle) < PI * 0.85:
			var auto_t := 1.0 - exp(-auto_rotate_smoothness * delta)
			_yaw += delta_angle * auto_rotate_strength * auto_t
	
	var target_distance := desired_distance
	if dynamic_distance:
		target_distance += max_distance_bonus * speed_ratio
	_current_distance = _exp_smooth_f(_current_distance, target_distance, follow_smoothness * 0.5, delta)
	
	var desired_cam_pos := Vector3.ZERO
	desired_cam_pos.x = target_pos.x + _current_distance * cos(_pitch) * sin(_yaw)
	desired_cam_pos.y = target_pos.y + _current_distance * sin(-_pitch)
	desired_cam_pos.z = target_pos.z + _current_distance * cos(_pitch) * cos(_yaw)
	
	if enable_collision:
		desired_cam_pos = _apply_collision(target_pos, desired_cam_pos)
	desired_cam_pos = _enforce_ground_limit(desired_cam_pos, target_pos)
	
	# Плавное следование
	if _is_transitioning:
		var t := 1.0 - exp(-transition_speed * delta)
		_smoothed_position = _smoothed_position.lerp(desired_cam_pos, t)
		_smoothed_look_target = _smoothed_look_target.lerp(target_pos, t)
		if _smoothed_position.distance_to(desired_cam_pos) < 0.05:
			_is_transitioning = false
	else:
		if _is_first_frame:
			_smoothed_position = desired_cam_pos
			_smoothed_look_target = target_pos
			_is_first_frame = false
		else:
			_smoothed_position = _exp_smooth(_smoothed_position, desired_cam_pos, follow_smoothness, delta)
			_smoothed_look_target = _exp_smooth(_smoothed_look_target, target_pos, follow_smoothness * 1.5, delta)
	
	_camera.global_position = _smoothed_position
	_camera.look_at(_smoothed_look_target, Vector3.UP)


# === ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ===
func _exp_smooth(current: Vector3, target: Vector3, smoothness: float, delta: float) -> Vector3:
	return current.lerp(target, 1.0 - exp(-smoothness * delta))

func _exp_smooth_f(current: float, target: float, smoothness: float, delta: float) -> float:
	return lerpf(current, target, 1.0 - exp(-smoothness * delta))


func _apply_collision(from: Vector3, to: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	if not space:
		return to
	
	var shape := SphereShape3D.new()
	shape.radius = collision_sphere_radius
	
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), to)
	params.motion = from - to
	params.collision_mask = collision_mask
	if target and target is CollisionObject3D:
		params.exclude = [target.get_rid()]
	params.collide_with_bodies = true
	params.collide_with_areas = false
	
	var result := space.cast_motion(params)
	if result and result.size() >= 1:
		var safe_fraction := result[0]
		var safe_pos := from.lerp(to, maxf(safe_fraction, 0.0))
		var dir := (to - from).normalized()
		return safe_pos - dir * collision_margin
	
	return to


func _enforce_ground_limit(cam_pos: Vector3, target_pos: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	if not space:
		return cam_pos
	
	var min_y := target_pos.y + min_height_above_target
	if cam_pos.y < min_y:
		cam_pos.y = min_y
	
	var ray_from := cam_pos + Vector3.UP * 0.5
	var ray_to := cam_pos - Vector3.UP * 100.0
	
	var ray_params := PhysicsRayQueryParameters3D.create(ray_from, ray_to, ground_mask)
	if target and target is CollisionObject3D:
		ray_params.exclude = [target.get_rid()]
	ray_params.collide_with_bodies = true
	ray_params.collide_with_areas = false
	
	var ray_result := space.intersect_ray(ray_params)
	if ray_result and ray_result.size() > 0:
		var ground_y: float = ray_result.position.y
		var min_cam_y := ground_y + ground_ray_margin
		if cam_pos.y < min_cam_y:
			cam_pos.y = min_cam_y
	
	return cam_pos