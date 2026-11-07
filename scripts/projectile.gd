extends Area2D
class_name Projectile
## Spawned by SpellCaster (#3). Travels in a straight line toward the aim
## point; despawns at max range or on hitting a physics body.
## #5 consumes: hit bodies that implement apply_damage(damage) get spell.damage.

var spell: Spell
var direction: Vector2 = Vector2.RIGHT
var source: Node2D ## The caster's owner; never hit by its own projectile.
var _traveled: float = 0.0

func setup(p_spell: Spell, p_direction: Vector2, p_source: Node2D) -> void:
	spell = p_spell
	direction = p_direction.normalized()
	source = p_source
	rotation = direction.angle()

func _ready() -> void:
	$CollisionShape2D.shape.radius = spell.radius
	$Visual.color = spell.projectile_color
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	var step: float = spell.projectile_speed * delta
	position += direction * step
	_traveled += step
	if _traveled >= spell.range:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if body == source:
		return
	if body.has_method(&"apply_damage"):
		body.apply_damage(spell.damage)
	queue_free()
