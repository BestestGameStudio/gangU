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
## #210/#289: supplied sprite art replaces the code-drawn Dart/Visual for spells
## with a mapped animation. Visuals only: radius, movement, hits, despawn and
## the visual_override hook are untouched; unmapped spells look as before.
const PROJECTILE_SPRITES: SpriteFrames = preload("res://resources/sprites/spell_upgrades_frames.tres")
## Each spell (base or upgrade result) flies its own sheet row (#289): a
## one-shot "<anim>_start" spawn-in, then the looping "<anim>" flight.
const SPELL_SPRITE_ANIMS: Dictionary = {
	"Fire Ball": &"fire_ball",
	"Fire Ball Split": &"fire_ball_split",
	"Fire Ball Split Heavy": &"fire_ball_split_heavy",
	"Fire Ball Split Wide": &"fire_ball_split_wide",
	"Fire Ball Beam": &"fire_ball_beam",
	"Fire Ball Beam Heavy": &"fire_ball_beam_heavy",
	"Fire Ball Beam Homing": &"fire_ball_beam_homing",
	"Fire Ball Beam Long": &"fire_ball_beam_long",
	"Fire Ball Beam Piercing": &"fire_ball_beam_piercing",
	"Mana Shot": &"mana_shot",
	"Mana Volley": &"mana_volley",
	"Mana Lance": &"mana_lance",
	"Placeholder Bolt": &"placeholder_bolt",
	"Bolt Flurry": &"bolt_flurry",
	"Heavy Bolt": &"bolt_heavy",
	"Spirit Punch": &"spirit_punch",
}
## Cell art is 64 px wide at scale 1; radius / 10 draws each projectile a little
## larger than its hit circle so it reads clearly. Clamped (art only, never the
## hitbox) so the smallest shots stay visible and the largest stay in proportion.
const SPRITE_RADIUS_DIVISOR: float = 10.0
const SPRITE_SCALE_MIN: float = 0.7
const SPRITE_SCALE_MAX: float = 1.4
## The art's head sits right of the cell centre; shift it back (cell px) so the
## bright head, not the tail, is at the hit point.
const SPRITE_HEAD_OFFSET: Vector2 = Vector2(-12.0, 0.0)

var direction: Vector2 = Vector2.RIGHT
var source: Node2D ## The caster's owner; never hit by its own projectile.
var _attacker_modifiers: DamageModifiers
var _attacker_rng: RandomNumberGenerator
var _traveled: float = 0.0
var _hit_bodies: Array[Node2D] = [] ## #37 piercing: one hit per body per projectile
## #216: the source's TerrainMap (Player/Enemy `terrain`), read at setup.
## Null (hub, hand-built areas, harness fixtures) skips terrain hits entirely.
var _terrain: TerrainMap = null

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
var _sprite_base: Vector2 = Vector2.ONE

## #263: glow halo + fading trail (opt-in per spell, visuals only).
const GLOW_RADIUS_MULT: float = 2.2 ## halo radius vs. the sprite's visual radius
const GLOW_ALPHA: float = 0.35
const GLOW_PULSE_AMP: float = 0.2 ## +/-20% halo pulse
const SPRITE_PULSE_AMP: float = 0.1 ## +/-10% sprite pulse
var _glow: Polygon2D = null
var _trail: Line2D = null

func setup(p_spell: Spell, p_direction: Vector2, p_source: Node2D) -> void:
	spell = p_spell
	direction = p_direction.normalized()
	source = p_source
	if p_source != null:
		_terrain = p_source.get(&"terrain") as TerrainMap
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
		_wire_glow_and_trail()

## #263: visual radius in pixels - the hit radius times the spell's
## visual_scale. Collision keeps using spell.radius.
func visual_radius() -> float:
	return spell.radius * maxf(spell.visual_scale, 0.0)

## #289: halo and trail colour; the rest of the game keeps projectile_color.
func _effect_color() -> Color:
	return spell.glow_tint if spell.glow_tint.a > 0.0 else spell.projectile_color

func _wire_glow_and_trail() -> void:
	if spell.trail_length > 0:
		_trail = Line2D.new()
		_trail.name = "Trail"
		_trail.top_level = true # points live in world space behind the shot
		_trail.width = visual_radius() * 1.4
		var curve := Curve.new()
		curve.add_point(Vector2(0.0, 0.15))
		curve.add_point(Vector2(1.0, 1.0))
		_trail.width_curve = curve
		var grad := Gradient.new()
		var c := _effect_color()
		grad.set_color(0, Color(c.r, c.g, c.b, 0.0))
		grad.set_color(1, Color(c.r, c.g, c.b, 0.7))
		if spell.trail_head_fade > 0.0:
			# #289: fade out towards the head instead of ending at full strength.
			grad.add_point(1.0 - spell.trail_head_fade, Color(c.r, c.g, c.b, 0.7))
			grad.set_color(grad.get_point_count() - 1, Color(c.r, c.g, c.b, 0.0))
		_trail.gradient = grad
		_trail.joint_mode = Line2D.LINE_JOINT_ROUND
		_trail.end_cap_mode = Line2D.LINE_CAP_ROUND
		var add_mat := CanvasItemMaterial.new()
		add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_trail.material = add_mat
		_trail.z_index = -1
		add_child(_trail)
	if spell.glow:
		_glow = Polygon2D.new()
		_glow.name = "Glow"
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		var r := visual_radius() * GLOW_RADIUS_MULT
		var c := _effect_color()
		pts.append(Vector2.ZERO)
		cols.append(Color(c.r, c.g, c.b, GLOW_ALPHA))
		for i in 25:
			var a := TAU * float(i) / 24.0
			pts.append(Vector2(cos(a), sin(a)) * r)
			cols.append(Color(c.r, c.g, c.b, 0.0))
		# Triangle fan from the centre so the halo fades out to the rim.
		var polys: Array = []
		for i in 24:
			polys.append(PackedInt32Array([0, i + 1, i + 2]))
		_glow.polygon = pts
		_glow.vertex_colors = cols
		_glow.polygons = polys
		var add_mat2 := CanvasItemMaterial.new()
		add_mat2.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_glow.material = add_mat2
		_glow.z_index = -1
		add_child(_glow)
		move_child(_glow, 0)

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
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var sz: float = clampf(spell.radius / SPRITE_RADIUS_DIVISOR, SPRITE_SCALE_MIN, SPRITE_SCALE_MAX)
	_sprite.scale = Vector2(sz, sz)
	_sprite_base = _sprite.scale
	_sprite.offset = SPRITE_HEAD_OFFSET
	add_child(_sprite)
	_sprite.animation_finished.connect(_sprite.play.bind(anim), CONNECT_ONE_SHOT)
	_sprite.play(StringName("%s_start" % anim))
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
	# #216 review: bodies and destroyable terrain crossed in this one segment
	# resolve in the order the projectile reaches them, so a nearer block
	# absorbs a non-piercing shot before a farther body (and vice versa).
	_sweep_segment(from, direction * step)
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
	_update_feel()

## #263: sprite/halo pulse and trail follow (visual only).
func _update_feel() -> void:
	if _sprite != null and spell.glow:
		_sprite.scale = _sprite_base * (1.0 + SPRITE_PULSE_AMP * sin(_vis_t * PULSE_RATE))
	if _glow != null:
		var g: float = 1.0 + GLOW_PULSE_AMP * sin(_vis_t * PULSE_RATE * 1.3)
		_glow.scale = Vector2(g, g)
	if _trail != null:
		_trail.add_point(global_position)
		while _trail.get_point_count() > spell.trail_length:
			_trail.remove_point(0)

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
	if is_queued_for_deletion():
		return # #216 review: a shot already spent (e.g. on a block) hits nothing more
	if body == source:
		return
	if _hit_bodies.has(body):
		return # #37: piercing re-contact never double-hits the same body
	if body.has_method(&"apply_damage"):
		var result := DamageCalc.compute(spell.damage, _attacker_modifiers, body.get(&"damage_modifiers") as DamageModifiers, _attacker_rng)
		# #214: bodies with a source gate (destroyable containers) receive the
		# projectile for caller-identity checks; every other receiver keeps the
		# legacy call unchanged (window ACK 2026-11-08: additive branch only,
		# source exclusion / hit bookkeeping / RNG / signals / pierce preserved).
		if body.has_method(&"apply_damage_from"):
			body.apply_damage_from(result.amount, self)
		else:
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

## #216 (wires #169): the flight path is sampled at most half a cell apart (no
## tunnelling through a cell on a big frame step). Returns [{t, cell}] for each destroyable cell the centre line enters, with
## t = the fraction of the segment at which it enters that cell.
func _terrain_events(from: Vector2, motion: Vector2) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if _terrain == null or not is_instance_valid(_terrain):
		return events
	var length := motion.length()
	var spacing := _terrain.cell_size * 0.5
	var samples := maxi(1, ceili(length / spacing))
	var seen: Dictionary = {}
	for i in range(1, samples + 1):
		var pt := from + motion * (float(i) / float(samples))
		var cell := _terrain.world_to_cell(pt)
		if seen.has(cell):
			continue
		seen[cell] = true
		if not TerrainTypes.is_destroyable(_terrain.tile_type_at_cell(cell)):
			continue
		events.append({"t": _cell_entry_t(from, motion, cell), "cell": cell})
	return events

## Fraction of the segment at which the centre line enters `cell` (0 if it
## starts inside). Computed in the map's local space; affine maps keep t.
func _cell_entry_t(from: Vector2, motion: Vector2, cell: Vector2i) -> float:
	var a := _terrain.to_local(from)
	var d := _terrain.to_local(from + motion) - a
	var cs := float(_terrain.cell_size)
	var lo := Vector2(cell) * cs
	var hi := lo + Vector2(cs, cs)
	var t_enter := 0.0
	for axis in 2:
		if absf(d[axis]) < 0.000001:
			continue
		var t1 := (lo[axis] - a[axis]) / d[axis]
		var t2 := (hi[axis] - a[axis]) / d[axis]
		t_enter = maxf(t_enter, minf(t1, t2))
	return clampf(t_enter, 0.0, 1.0)

## #109: sweep the hit circle from `from` along `motion`; every body the path
## crosses takes the hit even if no single physics frame overlaps it. Returns
## [{t, body}], t = the segment fraction of first contact with that body.
func _body_events(from: Vector2, motion: Vector2) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = $CollisionShape2D.shape
	params.transform = Transform2D(direction.angle(), from)
	params.motion = motion
	params.collision_mask = collision_mask
	params.collide_with_bodies = true
	params.collide_with_areas = false
	var space := get_world_2d().direct_space_state
	var hits: Array[Dictionary] = space.intersect_shape(params, 8)
	var rids: Array[RID] = []
	for h in hits:
		rids.append(h.get("rid"))
	# #216 re-review: cast_motion skips shapes already overlapped at the start
	# of the motion, so it never reports t=0 for them. Query the start pose
	# separately; any body touched there is first contact at t=0.
	var overlapping: Array[RID] = []
	if not hits.is_empty():
		params.motion = Vector2.ZERO
		for h in space.intersect_shape(params, 8):
			overlapping.append(h.get("rid"))
		params.motion = motion
	for idx in hits.size():
		var b: Node2D = hits[idx].get("collider")
		if b == null or b == source or _hit_bodies.has(b):
			continue
		if overlapping.has(rids[idx]):
			events.append({"t": 0.0, "body": b})
			continue
		# Contact time against this body alone: exclude every other hit.
		var others: Array[RID] = []
		for j in rids.size():
			if j != idx:
				others.append(rids[j])
		params.exclude = others
		var cast: PackedFloat32Array = space.cast_motion(params)
		var t: float = cast[1] if cast.size() == 2 else 0.0
		events.append({"t": t, "body": b})
	return events

## #216 review: one ordered pass over everything this segment crosses. Bodies
## go through _on_body_entered (source exclusion, damage dispatch, one-hit
## bookkeeping, pierce); destroyable cells through TerrainMap.destroy_cell, the
## single terrain-damage entry point (owner rule from #169: any hit destroys a
## destroyable tile). Either kind consumes a non-piercing shot; ties go to the
## body. Non-destroyable tiles never produce an event (pass-through as before).
func _sweep_segment(from: Vector2, motion: Vector2) -> void:
	var events: Array[Dictionary] = _body_events(from, motion)
	events.append_array(_terrain_events(from, motion))
	events.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if x.t != y.t:
			return x.t < y.t
		return x.has("body") and not y.has("body"))
	for e in events:
		if e.has("body"):
			var b: Node2D = e.body
			if not is_instance_valid(b) or _hit_bodies.has(b):
				continue
			_on_body_entered(b)
		elif _terrain.destroy_cell(e.cell):
			if not spell.tags.has(SpellTags.PIERCING):
				queue_free()
		if is_queued_for_deletion():
			return
