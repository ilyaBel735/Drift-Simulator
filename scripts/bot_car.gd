class_name BotCar
extends PathFollow3D

@export var speed := 12.0
@export var start_offset := 0.0


func _ready() -> void:
    rotation_mode = PathFollow3D.ROTATION_Y
    loop = true
    progress = start_offset


func _physics_process(delta: float) -> void:
    progress += speed * delta