extends Area2D
## TEST HARNESS ONLY (#5 evidence) - stands in for the #3/#4 spell projectiles
## until the #3 spell spawn hook lands. Contract for real projectiles: carry a
## damage value, call apply_damage(damage) on bodies they hit, then despawn.
## Not part of the production spell system; replaced by #3/#4 work.

@export var damage: int = 10
@export var speed: float = 500.0
@export var max_range: float = 400.0

var direction: Vector2 = Vector2.RIGHT
var _traveled: float = 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	var step: float = speed * delta
	position += direction * step
	_traveled += step
	if _traveled >= max_range:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if body is Player:
		return
	if body.has_method("apply_damage"):
		body.apply_damage(damage)
		queue_free()
