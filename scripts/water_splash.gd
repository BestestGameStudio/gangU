class_name WaterSplash
extends Node2D
## #331 Water Ball splash branch: a lobbed water ball. It flies from `from` to
## `target` along an arc (drawn height only - nothing is hit in flight), then
## lands and deals the spell's damage once to every living enemy within
## spell.splash_radius of the landing point. Heavy Rain (WaterRain) drops the
## same node straight down from the sky.
##
## Damage goes through DamageCalc with the source's modifiers (plus matching
## owned relics) and RNG, like a Projectile hit, so crits, damage numbers and
## hit flashes all apply.
##
## Freeze contract (#305 / #323 The World): a lob or drop whose ground point
## is inside a FreezeBubble is claimed by it (set_frozen, reference-counted
## so overlapping bubbles hold and release independently). While held the
## flight clock, position, sprite animation and landing ring all stop; on
## release it resumes where it was. Being a plain Node2D (no overlap
## signals) it asks every bubble to claim it each physics step - claim() is
## once per pair and refuses while releasing, so this never doubles a claim.

signal landed(position: Vector2, hits: int)

const SPRITES: SpriteFrames = preload("res://resources/sprites/spell_upgrades_frames.tres")
const RING_TIME := 0.35
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.28)

var spell: Spell
var source: Node2D
var from := Vector2.ZERO
var target := Vector2.ZERO
## Peak height of the arc in px (visual only).
var height := 70.0
## Seconds in the air; set from distance / projectile_speed when <= 0.
var flight_time := 0.0

var _t := 0.0
var _landed := false
var _ring_t := 0.0
var _ball: AnimatedSprite2D
var _freeze_count := 0

## Freeze contract: balanced claims from FreezeBubble.
func set_frozen(frozen: bool) -> void:
	var was := _freeze_count
	_freeze_count = maxi(_freeze_count + (1 if frozen else -1), 0)
	if _ball == null or not is_instance_valid(_ball):
		return
	if _freeze_count > 0 and was == 0:
		# pause() alone does not hold an AnimatedSprite2D; stop its processing.
		_ball.pause()
		_ball.process_mode = Node.PROCESS_MODE_DISABLED
	elif _freeze_count == 0 and was > 0:
		_ball.process_mode = Node.PROCESS_MODE_INHERIT
		_ball.play()

func is_frozen() -> bool:
	return _freeze_count > 0

func freeze_count() -> int:
	return _freeze_count

## Ask every live bubble to claim me (shared with WaterRain).
static func claim_by_bubbles(node: Node2D) -> void:
	for bubble in node.get_tree().get_nodes_in_group(&"freeze_bubbles"):
		bubble.claim(node)

## Spawn a lob under `parent`. A zero-length lob (`from == target`) is a drop
## from the sky that still takes `flight_time` seconds to fall.
static func spawn(parent: Node, p_spell: Spell, p_source: Node2D, p_from: Vector2, p_target: Vector2, p_height: float = 70.0, p_flight_time: float = 0.0) -> WaterSplash:
	var s := WaterSplash.new()
	s.spell = p_spell
	s.source = p_source
	s.from = p_from
	s.target = p_target
	s.height = p_height
	s.flight_time = p_flight_time
	parent.add_child(s)
	s.global_position = p_from
	return s

func _ready() -> void:
	if flight_time <= 0.0:
		flight_time = maxf(from.distance_to(target) / maxf(spell.projectile_speed, 1.0), 0.15)
	z_index = 1
	_ball = AnimatedSprite2D.new()
	_ball.name = "Ball"
	_ball.sprite_frames = SPRITES
	_ball.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ball.offset = Projectile.SPRITE_HEAD_OFFSET
	var sz := clampf(spell.radius / Projectile.SPRITE_RADIUS_DIVISOR, Projectile.SPRITE_SCALE_MIN, Projectile.SPRITE_SCALE_MAX)
	_ball.scale = Vector2(sz, sz)
	add_child(_ball)
	_ball.play(&"water_ball")
	_update_ball()

func _physics_process(delta: float) -> void:
	claim_by_bubbles(self)
	if _freeze_count > 0:
		return
	if _landed:
		_ring_t += delta
		queue_redraw()
		if _ring_t >= RING_TIME:
			queue_free()
		return
	_t += delta
	if _t >= flight_time:
		_land()
		return
	global_position = from.lerp(target, _t / flight_time)
	_update_ball()
	queue_redraw()

## Arc: the ball rides `height * sin(pi * t)` above the ground point and
## points along its screen-space motion. A drop from the sky falls from
## `height` straight down.
func _update_ball() -> void:
	var k := clampf(_t / flight_time, 0.0, 1.0)
	var lift: float
	var vel: Vector2
	if from.is_equal_approx(target):
		lift = height * (1.0 - k)
		vel = Vector2.DOWN
	else:
		lift = height * sin(PI * k)
		vel = (target - from) / flight_time + Vector2(0.0, -height * PI * cos(PI * k) / flight_time)
	_ball.position = Vector2(0.0, -lift)
	_ball.rotation = vel.angle()

func _land() -> void:
	_landed = true
	global_position = target
	_ball.queue_free()
	var hits := 0
	for e in get_tree().get_nodes_in_group(&"enemies"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		var hp: Variant = e.get(&"hp")
		if hp == null or int(hp) <= 0:
			continue
		if (e as Node2D).global_position.distance_to(target) <= spell.splash_radius:
			deal_damage(e, spell, source)
			hits += 1
	landed.emit(target, hits)
	queue_redraw()

func _draw() -> void:
	if _landed:
		# Expanding splash ring + soft puddle that fade out.
		var k := clampf(_ring_t / RING_TIME, 0.0, 1.0)
		var c := spell.projectile_color
		draw_circle(Vector2.ZERO, spell.splash_radius * (0.6 + 0.4 * k), Color(c.r, c.g, c.b, 0.3 * (1.0 - k)))
		draw_arc(Vector2.ZERO, spell.splash_radius * (0.5 + 0.5 * k), 0.0, TAU, 40, Color(0.85, 0.95, 1.0, 1.0 - k), 3.0)
		for i in 8:
			var a := TAU * float(i) / 8.0 + 0.3
			var p := Vector2(cos(a), sin(a)) * spell.splash_radius * (0.3 + 0.8 * k)
			draw_circle(p + Vector2(0.0, -20.0 * sin(PI * k)), 3.0 * (1.0 - k) + 1.0, Color(0.6, 0.85, 1.0, 1.0 - k))
		return
	# Ground shadow + landing marker under the arc.
	var to_target := target - global_position
	draw_circle(to_target, spell.splash_radius, Color(0.3, 0.6, 1.0, 0.12))
	draw_arc(to_target, spell.splash_radius, 0.0, TAU, 40, Color(0.5, 0.8, 1.0, 0.45), 1.5)
	draw_circle(Vector2.ZERO, maxf(spell.radius * 0.8, 4.0), SHADOW_COLOR)

## Shared Water Ball damage dispatch (#331): one DamageCalc roll with the
## source's modifiers against `body`, routed like a Projectile hit.
## #390: `delivery` labels the shared OnHit report (Water Shield passes contact).
static func deal_damage(body: Node, p_spell: Spell, p_source: Node, delivery: StringName = OnHit.DELIVERY_SPLASH) -> void:
	if body == null or not body.has_method(&"apply_damage"):
		return
	# Same attacker composition as Projectile.setup: the source's modifiers
	# plus tag-matched owned-relic modifiers in a fresh copy (never mutates
	# the source's collection, so repeated hits cannot accumulate).
	var mods := Projectile.attacker_modifiers_for(p_source, p_spell)
	var rng: RandomNumberGenerator = null
	if p_source != null and is_instance_valid(p_source):
		rng = p_source.get(&"damage_rng") as RandomNumberGenerator
	if rng == null:
		rng = RandomNumberGenerator.new()
	var result := DamageCalc.compute(p_spell.damage, mods, body.get(&"damage_modifiers") as DamageModifiers, rng)
	var was_alive := OnHit.is_alive(body)
	if body is Enemy:
		body.apply_damage(result.amount, result.crit_tier)
	else:
		body.apply_damage(result.amount)
	OnHit.report(p_source, p_spell, body, result, delivery, was_alive)
