class_name PlayerCar
extends CharacterBody3D

@export var max_forward_speed := 32.0
@export var max_reverse_speed := 12.0
@export var engine_force := 55.0
@export var reverse_force := 25.0
@export var brake_force := 70.0
@export var drag := 0.35
@export var turn_rate := 2.4
@export var normal_grip := 32.0
@export var drift_grip := 6.0
@export var handbrake_drag := 1.8


func _ready() -> void:
    motion_mode = CharacterBody3D.MOTION_MODE_FLOATING

    var cam := get_node_or_null("Camera3D") as Camera3D
    if cam:
        cam.make_current()


func _physics_process(delta: float) -> void:
    var throttle := 0.0
    if Input.is_key_pressed(KEY_W) or Input.is_action_pressed("ui_up"):
        throttle += 1.0
    if Input.is_key_pressed(KEY_S) or Input.is_action_pressed("ui_down"):
        throttle -= 1.0

    var steer := 0.0
    if Input.is_key_pressed(KEY_A) or Input.is_action_pressed("ui_left"):
        steer += 1.0
    if Input.is_key_pressed(KEY_D) or Input.is_action_pressed("ui_right"):
        steer -= 1.0

    var handbrake := Input.is_key_pressed(KEY_SPACE) or Input.is_action_pressed("ui_accept")

    velocity.y = 0.0

    var forward := -global_transform.basis.z
    var old_forward_speed := velocity.dot(forward)

    var direction := 0.0
    if absf(old_forward_speed) > 0.2:
        direction = signf(old_forward_speed)

    var active_turn_rate := turn_rate
    if handbrake:
        active_turn_rate *= 1.5

    var speed_amount := clampf(absf(old_forward_speed) / 6.0, 0.0, 1.0)
    var high_speed_factor := 1.0 - clampf(absf(old_forward_speed) / max_forward_speed, 0.0, 0.45)

    if direction != 0.0:
        rotate_y(steer * active_turn_rate * speed_amount * high_speed_factor * direction * delta)

    forward = -global_transform.basis.z
    var right := global_transform.basis.x

    if throttle > 0.0:
        velocity += forward * engine_force * throttle * delta
    elif throttle < 0.0:
        if old_forward_speed > 1.0:
            velocity -= forward * brake_force * absf(throttle) * delta
        else:
            velocity += forward * reverse_force * throttle * delta

    var forward_speed := velocity.dot(forward)
    var lateral_speed := velocity.dot(right)

    forward_speed *= maxf(0.0, 1.0 - drag * delta)
    if handbrake:
        forward_speed *= maxf(0.0, 1.0 - handbrake_drag * delta)

    forward_speed = clampf(forward_speed, -max_reverse_speed, max_forward_speed)

    var grip := drift_grip if handbrake else normal_grip
    lateral_speed = move_toward(lateral_speed, 0.0, grip * delta)

    velocity = forward * forward_speed + right * lateral_speed

    var max_total := max_forward_speed * 1.25
    if velocity.length() > max_total:
        velocity = velocity.normalized() * max_total

    velocity.y = 0.0
    move_and_slide()

    global_position.y = 0.0