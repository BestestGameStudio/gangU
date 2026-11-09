class_name WaterShield
extends Node2D
## #331 Water Ball bubble branch ("water BALL!"): water surrounding the
## player. Parented to the player so it follows every move.
##  - Specialization: deals spell.damage to each enemy touching it, at most
##    once per spell.shield_tick per enemy, and absorbs up to
##    spell.shield_charges hostile projectiles; the last absorbed shot pops it.
##  - Mastery: when it ends (time out or popped) it pushes every enemy within
##    spell.shield_push_radius away from the player (Enemy.knockback).
##  - Signature (Big Ball): bigger, longer, more charges (resource numbers);
##    shrink() is called for each Water Ball fired from inside it.
## A hostile shot is any Projectile whose source is not the player side
## (a live Player or Summon); freed sources count as hostile.

signal absorbed(projectile: Node, charges_left: int)
signal ended(popped: bool)

## An enemy touches the shield when its centre is within radius + this.
const CONTACT_PAD := 10.0
const FADE_TIME := 0.25
## Big Ball shrinking never goes below this fraction of the cast radius.
const MIN_RADIUS_FRACTION := 0.4

var spell: Spell
var owner_body: Node2D
var radius := 0.0
var charges := 0

var _base_radius := 0.0
var _elapsed := 0.0
var _hit_clock: Dictionary = {} # Enemy -> seconds until it can be hit again
var _ending := false
var _end_t := 0.0
var _flash := 0.0

static func spawn(p_owner: Node2D, p_spell: Spell) -> WaterShield:
	var s := WaterShield.new()
	s.spell = p_spell
	s.owner_body = p_owner
	s.name = "WaterShield"
	p_owner.add_child(s)
	return s

func _ready() -> void:
	add_to_group(&"water_shields")
	radius = spell.shield_radius
	_base_radius = radius
	charges = spell.shield_charges
	z_index = 1

func is_active() -> bool:
	return not _ending

## Seconds of shield time left (0 once ending).
func time_left() -> float:
	return 0.0 if _ending else maxf(spell.shield_duration - _elapsed, 0.0)

## Big Ball: each Water Ball fired from inside costs some coverage.
func shrink() -> void:
	radius = maxf(radius * (1.0 - spell.shield_shrink), _base_radius * MIN_RADIUS_FRACTION)
	queue_redraw()

func _physics_process(delta: float) -> void:
	_flash = maxf(_flash - delta, 0.0)
	if _ending:
		_end_t += delta
		queue_redraw()
		if _end_t >= FADE_TIME:
			queue_free()
		return
	_elapsed += delta
	_damage_contacts(delta)
	_absorb_projectiles()
	queue_redraw()
	if not _ending and _elapsed >= spell.shield_duration:
		end_shield(false)

func _damage_contacts(delta: float) -> void:
	for e in _hit_clock.keys():
		_hit_clock[e] -= delta
		if not is_instance_valid(e) or _hit_clock[e] <= 0.0:
			_hit_clock.erase(e)
	var reach := radius + CONTACT_PAD
	for e in get_tree().get_nodes_in_group(&"enemies"):
		if not is_instance_valid(e) or not (e is Node2D) or _hit_clock.has(e):
			continue
		var hp: Variant = e.get(&"hp")
		if hp == null or int(hp) <= 0:
			continue
		if (e as Node2D).global_position.distance_to(global_position) <= reach:
			_hit_clock[e] = spell.shield_tick
			WaterSplash.deal_damage(e, spell, owner_body)

func _absorb_projectiles() -> void:
	for p in get_tree().get_nodes_in_group(&"projectiles"):
		if charges <= 0:
			return
		if not is_instance_valid(p) or p.is_queued_for_deletion() or not is_hostile(p):
			continue
		if (p as Node2D).global_position.distance_to(global_position) > radius:
			continue
		p.queue_free()
		charges -= 1
		_flash = 0.15
		absorbed.emit(p, charges)
		if charges <= 0:
			end_shield(true)

## A shot from anything that is not a live Player or Summon.
func is_hostile(p: Node) -> bool:
	var src: Variant = p.get(&"source")
	if src == null or not is_instance_valid(src):
		return true
	return not (src is Player or src is Summon)

func end_shield(popped: bool) -> void:
	if _ending:
		return
	_ending = true
	if spell.shield_push_radius > 0.0 and spell.shield_push_force > 0.0:
		for e in get_tree().get_nodes_in_group(&"enemies"):
			if not is_instance_valid(e) or not e.has_method(&"knockback"):
				continue
			var off: Vector2 = (e as Node2D).global_position - global_position
			if off.length() > spell.shield_push_radius:
				continue
			var dir := off.normalized() if off.length_squared() > 0.0 else Vector2.RIGHT
			e.knockback(dir * spell.shield_push_force)
	ended.emit(popped)

func _draw() -> void:
	var fade := 1.0
	var r := radius
	if _ending:
		var k := clampf(_end_t / FADE_TIME, 0.0, 1.0)
		fade = 1.0 - k
		if spell.shield_push_radius > 0.0:
			# Mastery burst: the water rushes out to the push radius.
			r = lerpf(radius, spell.shield_push_radius, k)
	var c := spell.projectile_color
	var wob := sin(_elapsed * 6.0) * 2.0
	var fill := Color(c.r, c.g, c.b, (0.28 + _flash) * fade)
	draw_circle(Vector2.ZERO, r + wob, fill)
	draw_circle(Vector2.ZERO, (r + wob) * 0.7, Color(0.7, 0.9, 1.0, 0.08 * fade))
	draw_arc(Vector2.ZERO, r + wob, 0.0, TAU, 56, Color(0.75, 0.92, 1.0, 0.85 * fade), 3.0)
	# Ripple ring moving outwards.
	var ripple := fmod(_elapsed * 0.8, 1.0)
	draw_arc(Vector2.ZERO, r * (0.35 + 0.6 * ripple), 0.0, TAU, 40, Color(0.85, 0.95, 1.0, 0.35 * (1.0 - ripple) * fade), 1.5)
	# Glint.
	draw_circle(Vector2(-r * 0.4, -r * 0.45), maxf(r * 0.1, 2.0), Color(1, 1, 1, 0.55 * fade))
	# Remaining absorb charges as pips along the top.
	if not _ending:
		for i in charges:
			var a := -PI * 0.5 + (float(i) - (charges - 1) * 0.5) * 0.28
			draw_circle(Vector2(cos(a), sin(a)) * (r + 8.0), 3.0, Color(0.85, 0.95, 1.0, 0.95))
