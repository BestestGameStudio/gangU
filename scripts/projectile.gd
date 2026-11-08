extends Area2D
class_name Projectile
## Spawned by SpellCaster (#3). Travels in a straight line toward the aim
## point; despawns at max range or on hitting a physics body.
## #5 consumes: hit bodies that implement apply_damage(damage) get spell.damage
## after DamageCalc applies the caster's and the body's modifiers.

signal hit_resolved(body: Node2D, result: DamageResult)

## #177: emitted when this projectile damages a body (visual hooks only,
## e.g. the Warlord orb's impact pop). Hit logic is unchanged.
signal hit(body: Node2D)

var spell: Spell
## #177: optional per-instance visual override (e.g. the Warlord orb art).
## Assign before add_child: it replaces the code-drawn Dart/Visual for THIS
## projectile only. Radius, movement, hits and despawn are untouched, and
## projectiles without an override look exactly as before.
var visual_override: Node2D
## #210: supplied sprite art replaces the code-drawn Dart/Visual for spells
## with a mapped animation. Visuals only: radius, movement, hits, despawn and
## the visual_override hook are untouched; unmapped spells look as before.
const PROJECTILE_SPRITES: SpriteFrames = preload("res://resources/sprites/spell_projectiles_frames.tres")
## Cell art is authored ~4x the in-world size at scale 4; radius/16 lands each
## sprite in the same visual footprint as the radius-scaled code-drawn dart.
const SPELL_SPRITE_ANIMS: Dictionary = {
	"Fire Ball": &"flame",
	"Mana Shot": &"mana",
	"Placeholder Bolt": &"bolt",
}

var direction: Vector2 = Vector2.RIGHT
var source: Node2D ## The caster's owner; never hit by its own projectile.
var _attacker_modifiers: DamageModifiers
var _attacker_rng: RandomNumberGenerator
var _traveled: float = 0.0
var _hit_bodies: Array[Node2D] = [] ## #37 piercing: one hit per body per projectile

## #37 homing (peer-lead tuning under the Colin-side grant, not owner numbers):
const HOMING_RANGE: float = 400.0 ## steer only toward enemies within this range
const HOMING_TURN_RATE: float = 6.0 ## max turn in rad/s

## #109: visual feel (code-drawn, flat geometric - style direction).
const SPIN_RATE: float = 12.0 ## rad/s diamond spin
const PULSE_RATE: float = 10.0 ## rad/s scale pulse
const PULSE_AMP: float = 0.15 ## +/-15% scale pulse

var _vis_t: float = 0.0
var _vis_base: Vector2 = Vector2.ONE
var _sprite: AnimatedSprite2D = null

func setup(p_spell: Spell, p_direction: Vector2, p_source: Node2D) -> void:
	spell = p_spell
	direction = p_direction.normalized()
	source = p_source
	if p_source != null:
		_attacker_modifiers = p_source.get(&"damage_modifiers") as DamageModifiers
		_attacker_rng = p_source.get(&"damage_rng") as RandomNumberGenerator
	# #131 (C4): owned relics contribute their tag-matched passive modifiers
	# through a COMPOSED COPY - the source's own collection is never mutated,
	# so repeated casts cannot accumulate relic entries. No owned_relics node,
	# or no matching relic, leaves the attacker modifiers exactly as before.
	var relics: OwnedRelics = null
	if p_source is Player and p_source.is_inside_tree():
		relics = p_source.get_tree().get_first_node_in_group("owned_relics") as OwnedRelics
	if relics != null:
		var relic_mods := relics.modifiers_for(spell)
		if not relic_mods.is_empty():
			var merged := DamageModifiers.new()
			if _attacker_modifiers != null:
				for m in _attacker_modifiers.items():
					merged.add(m)
			for m in relic_mods:
				merged.add(m)
			_attacker_modifiers = merged
	rotation = direction.angle()

func _ready() -> void:
	$CollisionShape2D.shape = $CollisionShape2D.shape.duplicate() # per-spell radius must not leak across instances (#4 gate)
	$CollisionShape2D.shape.radius = spell.radius
	$Visual.color = spell.projectile_color
	# #96: direction-legible dart - same per-spell tint and radius scale as the
	# core. Points +X; the root's rotation already faces the flight direction.
	$Dart.color = spell.projectile_color
	$Dart.scale = Vector2(spell.radius / 4.0, spell.radius / 4.0)
	var _vis_scale := spell.radius / 4.0 # Visual polygon is authored at radius 4
	$Visual.scale = Vector2(_vis_scale, _vis_scale)
	body_entered.connect(_on_body_entered)
	_vis_base = $Visual.scale
	if visual_override != null:
		$Dart.visible = false
		$Visual.visible = false
		visual_override.name = "VisualOverride"
		add_child(visual_override)
	else:
		_wire_sprite()

## #210: hide the code-drawn visuals and fly the mapped supplied-art
## animation instead. The root already faces the flight direction and the art
## is authored pointing +X, so no extra rotation is needed.
func _wire_sprite() -> void:
	var anim: StringName = SPELL_SPRITE_ANIMS.get(spell.spell_name, &"")
	if anim == &"":
		return
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	_sprite.sprite_frames = PROJECTILE_SPRITES
	_sprite.animation = anim
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var sz: float = spell.radius / 16.0
	_sprite.scale = Vector2(sz, sz)
	add_child(_sprite)
	_sprite.play()
	$Dart.visible = false
	$Visual.visible = false

func _physics_process(delta: float) -> void:
	# #37: a HOMING-tagged spell steers BEFORE moving - toward the nearest
	# living enemy within HOMING_RANGE, retargeted every frame, capped at
	# HOMING_TURN_RATE rad/s. No target in range: flies straight. Speed,
	# range, damage and cooldown are untouched.
	if spell.tags.has(SpellTags.HOMING):
		_steer(delta)
	var step: float = spell.projectile_speed * delta
	# #109: swept hit detection - move first, then sweep the circle along the
	# whole path so a frame step larger than the hit envelope (low/janky fps
	# on the web export) can never tunnel through a body between frames.
	# Per-frame body_entered overlap remains as the ordinary path; the sweep
	# only catches what it would miss (once-per-body guard dedupes).
	# The step is clamped to the remaining range: the swept path never reaches
	# past the projectile's own expiry point, so the maximum hit envelope stays
	# range + shape radius instead of range + one frame step + shape radius.
	var remaining: float = spell.range - _traveled
	if step > remaining:
		step = remaining
	var from: Vector2 = global_position
	position += direction * step
	_sweep_hits(from, direction * step)
	if is_queued_for_deletion():
		return
	_traveled += step
	if _traveled >= spell.range:
		queue_free()
		return
	# #109: code-drawn cast feel - the diamond spins and pulses while flying.
	# (#210: kept running even while a supplied-art sprite hides the diamond,
	# so the feel state stays live if the visual is ever swapped back.)
	_vis_t += delta
	$Visual.rotation += SPIN_RATE * delta
	var pulse: float = 1.0 + PULSE_AMP * sin(_vis_t * PULSE_RATE)
	$Visual.scale = _vis_base * pulse

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
		var result := DamageCalc.compute(spell.damage, _attacker_modifiers, body.get(&"damage_modifiers") as DamageModifiers, _attacker_rng)
		body.apply_damage(result.amount)
		_hit_bodies.append(body)
		hit.emit(body)
		hit_resolved.emit(body, result)
		# #37: a PIERCING-tagged spell damages, then CONTINUES past the body.
		# Untagged spells keep the original despawn-on-hit, and range expiry
		# is unchanged for both.
		if spell.tags.has(SpellTags.PIERCING):
			return
	queue_free()

## #109: sweep the hit circle from `from` along `motion`; every body the path
## crosses takes the hit even if no single physics frame overlaps it.
func _sweep_hits(from: Vector2, motion: Vector2) -> void:
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = $CollisionShape2D.shape
	params.transform = Transform2D(direction.angle(), from)
	params.motion = motion
	params.collision_mask = collision_mask
	params.collide_with_bodies = true
	params.collide_with_areas = false
	var hits: Array[Dictionary] = get_world_2d().direct_space_state.intersect_shape(params, 8)
	for h in hits:
		var b: Node2D = h.get("collider")
		if b == null or b == source or _hit_bodies.has(b):
			continue
		_on_body_entered(b)
		if is_queued_for_deletion():
			return
