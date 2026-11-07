extends CharacterBody2D
class_name Player
## gangU player controller (#2).
## WASD movement + cursor aim. Manual aim only, no aim assist.
## Consumes shared input actions from project.godot:
## move_up/move_down/move_left/move_right (WASD).

signal died()
signal health_changed(current: int, max_hp: int)

@export var speed: float = 320.0
@export var max_hp: int = 100

var hp: int

@onready var aim_indicator: Node2D = $AimIndicator
@onready var body: Polygon2D = $Body

func _ready() -> void:
	hp = max_hp

## #5 contract: single damage entry point. Clamps HP at 0 and emits
## health_changed ONLY from inside here, so HP can never change silently.
func apply_damage(amount: int) -> void:
	if hp <= 0:
		return
	hp = clampi(hp - amount, 0, max_hp)
	health_changed.emit(hp, max_hp)
	if hp == 0:
		died.emit()


## #12 contract: single heal entry point. Clamps at max_hp and emits
## health_changed ONLY from inside here, mirroring apply_damage, so HP can
## never change silently. Works from hp == 0 (revive path); died() has already
## fired by then and the HUD recovers via health_changed.
func heal(amount: int) -> void:
	hp = clampi(hp + amount, 0, max_hp)
	health_changed.emit(hp, max_hp)

func _physics_process(_delta: float) -> void:
	if hp <= 0:
		velocity = Vector2.ZERO
		return
	var input_dir := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	velocity = input_dir * speed
	move_and_slide()

func _process(_delta: float) -> void:
	# Face the mouse cursor; manual aim only.
	var aim_dir := global_position.direction_to(get_global_mouse_position())
	if aim_dir.length_squared() > 0.0:
		rotation = aim_dir.angle()
