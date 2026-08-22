class_name TrafficLight
extends Node3D

var intersection := Vector2i.ZERO
var direction := Vector2i(1, 0)

var red_lamp: MeshInstance3D
var yellow_lamp: MeshInstance3D
var green_lamp: MeshInstance3D

var update_timer := 0.0


func setup(
    intersection_value: Vector2i,
    direction_value: Vector2i,
    meshes: Dictionary,
    materials: Dictionary
) -> void:
    intersection = intersection_value
    direction = direction_value

    _build(meshes, materials)

    # Поворачиваем светофор лицом к приближающимся машинам.
    rotation.y = atan2(float(direction.x), float(direction.y))

    update_timer = randf_range(0.0, 0.1)
    _update_lamps()


func _process(delta: float) -> void:
    update_timer += delta

    if update_timer < 0.1:
        return

    update_timer = 0.0
    _update_lamps()


func _update_lamps() -> void:
    if red_lamp == null or yellow_lamp == null or green_lamp == null:
        return

    var state := TrafficRules.get_state(intersection, direction)

    red_lamp.visible = state == TrafficRules.LightState.RED
    yellow_lamp.visible = state == TrafficRules.LightState.YELLOW
    green_lamp.visible = state == TrafficRules.LightState.GREEN


func _build(meshes: Dictionary, materials: Dictionary) -> void:
    var pole_mesh := meshes.get("pole") as Mesh
    var lamp_mesh := meshes.get("lamp") as Mesh

    var pole_mat := materials.get("pole") as Material
    var red_mat := materials.get("red") as Material
    var yellow_mat := materials.get("yellow") as Material
    var green_mat := materials.get("green") as Material

    if pole_mesh == null or lamp_mesh == null:
        return

    var pole := MeshInstance3D.new()
    pole.mesh = pole_mesh
    pole.material_override = pole_mat
    pole.position = Vector3(0.0, 1.5, 0.0)
    add_child(pole)

    red_lamp = MeshInstance3D.new()
    red_lamp.mesh = lamp_mesh
    red_lamp.material_override = red_mat
    red_lamp.position = Vector3(0.0, 2.55, -0.18)
    add_child(red_lamp)

    yellow_lamp = MeshInstance3D.new()
    yellow_lamp.mesh = lamp_mesh
    yellow_lamp.material_override = yellow_mat
    yellow_lamp.position = Vector3(0.0, 2.3, -0.18)
    add_child(yellow_lamp)

    green_lamp = MeshInstance3D.new()
    green_lamp.mesh = lamp_mesh
    green_lamp.material_override = green_mat
    green_lamp.position = Vector3(0.0, 2.05, -0.18)
    add_child(green_lamp)