extends Area2D
class_name Projectile
## Spawned by SpellCaster (#3). Travels in a straight line toward the aim
## point; despawns at max range or on hitting a physics body.
## #5 consumes: hit bodies that implement apply_damage(damage) get spell.damage.

var spell: Spell
var direction: Vector2 = Vector2.RIGHT
var source: Node2D ## The caster's owner; never hit by its own projectile.
var _traveled: float = 0.0
var _hit_bodies: Array[Node2D] = [] ## #37 piercing: one hit per body per projectile

## #37 homing (peer-lead tuning under the Colin-side grant, not owner numbers):
const HOMING_RANGE: float = 400.0 ## steer only toward enemies within this range
const HOMING_TURN_RATE: float = 6.0 ## max turn in rad/s

func setup(p_spell: Spell, p_direction: Vector2, p_source: Node2D) -> void:
	spell = p_spell
	direction = p_direction.normalized()
	source = p_source
	rotation = direction.angle()

func _ready() -> void:
	$CollisionShape2D.shape = $CollisionShape2D.shape.duplicate() # per-spell radius must not leak across instances (#4 gate)
	$CollisionShape2D.shape.radius = spell.radius
	$Visual.color = spell.projectile_color
	var _vis_scale := spell.radius / 4.0 # Visual polygon is authored at radius 4
	$Visual.scale = Vector2(_vis_scale, _vis_scale)
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	# #37: a HOMING-tagged spell steers BEFORE moving - toward the nearest
	# living enemy within HOMING_RANGE, retargeted every frame, capped at
	# HOMING_TURN_RATE rad/s. No target in range: flies straight. Speed,
	# range, damage and cooldown are untouched.
	if spell.tags.has(SpellTags.HOMING):
		_steer(delta)
	var step: float = spell.projectile_speed * delta
	position += direction * step
	_traveled += step
	if _traveled >= spell.range:
		queue_free()

func _steer(delta: float) -> void:
	var best: Node2D = null
	var best_d2: float = HOMING_RANGE * HOMING_RANGE
	for e in get_tree().get_nodes_in_group(&"enemies"):
		if not is_instance_valid(e):
			continue
		if e.hp <= 0: # living enemies only
			continue
		if _hit_bodies.has(e):
			# #37: a body already pierced this projectile is spent - steering
			# back to it can never damage it again (once-per-body guard), so
			# homing+piercing continues to the next target instead of orbiting.
			continue
		var d2: float = global_position.distance_squared_to(e.global_position)
		if d2 <= best_d2:
			best_d2 = d2
			best = e
	if best == null:
		return
	var want: float = (best.global_position - global_position).angle()
	var diff: float = wrapf(want - direction.angle(), -PI, PI)
	var max_turn: float = HOMING_TURN_RATE * delta
	direction = direction.rotated(clampf(diff, -max_turn, max_turn))
	rotation = direction.angle()

func _on_body_entered(body: Node2D) -> void:
	if body == source:
		return
	if _hit_bodies.has(body):
		return # #37: piercing re-contact never double-hits the same body
	if body.has_method(&"apply_damage"):
		body.apply_damage(spell.damage)
		_hit_bodies.append(body)
		# #37: a PIERCING-tagged spell damages, then CONTINUES past the body.
		# Untagged spells keep the original despawn-on-hit, and range expiry
		# is unchanged for both.
		if spell.tags.has(SpellTags.PIERCING):
			return
	queue_free()
