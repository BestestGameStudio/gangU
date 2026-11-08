extends Area2D
## #173: boss bolt - the reference sheet's red slash (boss_head.png VFX
## element) flying straight, damaging the player on contact. Enemy-side
## mirror of projectile.gd's contract (straight line, max-range despawn,
## never hits its source); spells are player-side data (D8), so speed,
## damage and range are plain setup() values here.

var direction: Vector2 = Vector2.RIGHT
var speed: float = 260.0
var damage: int = 10
var max_range: float = 720.0
var source: Node2D
var _traveled: float = 0.0

func setup(p_direction: Vector2, p_speed: float, p_damage: int, p_range: float, p_source: Node2D) -> void:
	direction = p_direction.normalized()
	speed = p_speed
	damage = p_damage
	max_range = p_range
	source = p_source

func _ready() -> void:
	# The slash art points up-right in its cell; align it to the flight dir.
	rotation = direction.angle() + PI / 4.0
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	var step := speed * delta
	global_position += direction * step
	_traveled += step
	if _traveled >= max_range:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if body == source:
		return
	if body.has_method("apply_damage"):
		body.apply_damage(damage)
		queue_free()
