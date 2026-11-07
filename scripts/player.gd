extends CharacterBody2D
class_name Player
## gangU player controller (#2).
## WASD movement + cursor aim. Manual aim only, no aim assist.
## Consumes shared input actions from project.godot:
## move_up/move_down/move_left/move_right (WASD).

@export var speed: float = 320.0

@onready var aim_indicator: Node2D = $AimIndicator
@onready var body: Polygon2D = $Body

func _physics_process(_delta: float) -> void:
	var input_dir := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	velocity = input_dir * speed
	move_and_slide()

func _process(_delta: float) -> void:
	# Face the mouse cursor; manual aim only.
	var aim_dir := global_position.direction_to(get_global_mouse_position())
	if aim_dir.length_squared() > 0.0:
		rotation = aim_dir.angle()
