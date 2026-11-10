class_name StoneHammer
extends Node2D
## #370 Stone Hammer: one overhead swing. The hammer rises over the caster's
## head and crashes down on `target` after spell.hammer_windup seconds, then
## deals the spell's damage once to every living enemy within the strike
## radius. Code-drawn (no sprite art yet): a stone head on a wooden handle,
## a landing marker during the wind-up and a dust ring + cracks on impact.
##
## Upgrades read off the spell (see spell.gd, #370 block) and the caster's
## StoneHammerState:
##  - Crush: kills raise the run-long crit bonus; the Mastery scales the
##    strike radius and the drawn hammer with the crit chance.
##  - Rhythm: hit/miss feeds the combo (cooldown, rising tone); the Mastery
##    jump makes the caster invulnerable during the wind-up and adds a
##    shockwave; the Signature's dice roll spawns a HammerDice.
##
## Damage goes through DamageCalc with the source's modifiers (plus owned
## relics and the Crush bonus crit), like a Projectile hit, so crits, damage
## numbers and hit flashes all apply.

signal struck(position: Vector2, hits: int, kills: int)

## An enemy is hit when its centre is within radius + this (body size).
const HIT_PAD := 10.0
const IMPACT_TIME := 0.45
## Hammer head lift above the caster at the top of the swing (px, scaled).
const OVERHEAD := 70.0
const JUMP_HEIGHT := 26.0
const HEAD_SIZE := Vector2(30.0, 18.0)
const STONE := Color(0.58, 0.55, 0.5)
const STONE_DARK := Color(0.27, 0.25, 0.23)
const HANDLE := Color(0.5, 0.33, 0.18)
const DUST := Color(0.72, 0.62, 0.45)

var spell: Spell
var source: Node2D
var caster: SpellCaster
var target := Vector2.ZERO
## Crush Mastery size multiplier, fixed when the swing starts.
var size_scale := 1.0
var radius := 0.0
var hits := 0
var kills := 0

var _t := 0.0
var _landed := false
var _impact_t := 0.0
var _jumping := false
## Current hop height of this swing (px), read by the shared jump offset.
var _lift := 0.0
## Instance id of the jumping Player, so the registry entry can be released
## even after the player itself has been freed.
var _jump_key := 0
var _drop_parent: Node = null

## Leap jumps can overlap: with a short Rhythm cooldown and the player's
## cooldown reduction, a held key starts the next swing before the previous
## one lands. Jump state is therefore shared per player, keyed by instance id:
##   { "hammers": Array[StoneHammer], "nodes": Array[CanvasItem],
##     "base": Array[Vector2] }
## The FIRST jump captures the visual nodes' resting positions and opens the
## invulnerability window; every jump drives the offset from the highest
## active lift; only the LAST jump to end restores the positions and closes
## the window.
static var _jumps: Dictionary = {}

static func spawn(parent: Node, p_spell: Spell, p_source: Node2D, p_caster: SpellCaster, p_target: Vector2) -> StoneHammer:
	var h := StoneHammer.new()
	h.spell = p_spell
	h.source = p_source
	h.caster = p_caster
	h.target = p_target
	if p_caster != null:
		h.size_scale = p_caster.hammer_state.size_scale(p_spell, p_source)
	parent.add_child(h)
	h.global_position = p_target
	return h

func _ready() -> void:
	add_to_group(&"stone_hammers")
	z_index = 2
	radius = spell.hammer_radius * size_scale
	if spell.hammer_jump and source is Player:
		_start_jump(source as Player)
	queue_redraw()

func _exit_tree() -> void:
	_end_jump()

func is_landed() -> bool:
	return _landed

func shockwave_radius() -> float:
	return spell.hammer_shockwave_radius * size_scale

## Rhythm Mastery: the caster hops (visual offset only - the body stays where
## it is, so movement and collisions are untouched) and is invulnerable
## until the hammer lands. Overlapping jumps share one window (see _jumps).
func _start_jump(player: Player) -> void:
	_jumping = true
	_lift = 0.0
	_jump_key = player.get_instance_id()
	var entry: Dictionary = _jumps.get(_jump_key, {})
	if entry.is_empty():
		var nodes: Array[CanvasItem] = []
		if player.sprite != null:
			nodes.append(player.sprite)
		else:
			for n in [player.body, player.nose_edge]:
				if n != null:
					nodes.append(n)
		var base: Array[Vector2] = []
		for n in nodes:
			base.append(n.position)
		entry = {"hammers": [], "nodes": nodes, "base": base}
		_jumps[_jump_key] = entry
	(entry["hammers"] as Array).append(self)
	player.set_invulnerable(true)

## Ends this swing's jump (landing, caster death, or the hammer leaving the
## tree). The window stays open while any other jump on the same player is
## still in the air.
func _end_jump() -> void:
	if not _jumping:
		return
	_jumping = false
	_lift = 0.0
	var entry: Dictionary = _jumps.get(_jump_key, {})
	if entry.is_empty():
		return
	var hammers: Array = entry["hammers"]
	hammers.erase(self)
	# Drop swings that vanished without ending (defensive; _exit_tree covers it).
	for h in hammers.duplicate():
		if not is_instance_valid(h) or not (h as StoneHammer)._jumping:
			hammers.erase(h)
	var player := instance_from_id(_jump_key) as Player
	if hammers.is_empty():
		_jumps.erase(_jump_key)
		if player != null:
			player.set_invulnerable(false)
		_apply_offset(entry, Vector2.ZERO)
	elif player != null:
		_apply_offset(entry, _shared_up(entry, player))

## Highest lift among the player's active jumps, as a screen-up offset.
static func _shared_up(entry: Dictionary, player: Node2D) -> Vector2:
	var lift := 0.0
	for h in entry["hammers"]:
		if is_instance_valid(h):
			lift = maxf(lift, (h as StoneHammer)._lift)
	# The player node turns toward the cursor; hop straight up on screen.
	return Vector2(0.0, -lift).rotated(-player.global_rotation)

static func _apply_offset(entry: Dictionary, up: Vector2) -> void:
	var nodes: Array = entry["nodes"]
	var base: Array = entry["base"]
	for i in nodes.size():
		if is_instance_valid(nodes[i]):
			(nodes[i] as CanvasItem).position = base[i] + up

func is_jumping() -> bool:
	return _jumping

## Number of Leap jumps currently in the air for `player` (all swings).
static func active_jumps(player: Node) -> int:
	if player == null:
		return 0
	var entry: Dictionary = _jumps.get(player.get_instance_id(), {})
	return 0 if entry.is_empty() else (entry["hammers"] as Array).size()

func _physics_process(delta: float) -> void:
	if _landed:
		_impact_t += delta
		queue_redraw()
		if _impact_t >= IMPACT_TIME:
			queue_free()
		return
	if not is_instance_valid(source) or int(source.get(&"hp")) <= 0:
		# The caster died (or left) mid-swing: no strike.
		_end_jump()
		queue_free()
		return
	_t += delta
	if _jumping:
		var k := clampf(_t / maxf(spell.hammer_windup, 0.01), 0.0, 1.0)
		# Up fast, hang, slam down with the hammer.
		_lift = JUMP_HEIGHT * sin(PI * minf(k * 1.15, 1.0))
		var entry: Dictionary = _jumps.get(_jump_key, {})
		if not entry.is_empty():
			_apply_offset(entry, _shared_up(entry, source))
	if _t >= spell.hammer_windup:
		_land()
	queue_redraw()

func _land() -> void:
	_landed = true
	_end_jump()
	var mods := caster.hammer_state.attacker_modifiers(spell, source) if caster != null else Projectile.attacker_modifiers_for(source, spell)
	var hit_list: Array[Node] = []
	for e in _living_enemies():
		if (e as Node2D).global_position.distance_to(target) <= radius + HIT_PAD:
			hit_list.append(e)
	for e in hit_list:
		if _drop_parent == null:
			_drop_parent = e.get_parent()
		_deal(e, spell.damage, mods)
		hits += 1
		if int(e.get(&"hp")) <= 0:
			kills += 1
	# Rhythm Mastery shockwave: area damage on everything the hammer missed.
	if spell.hammer_shockwave_radius > 0.0 and spell.hammer_shockwave_damage > 0.0:
		for e in _living_enemies():
			if hit_list.has(e):
				continue
			if (e as Node2D).global_position.distance_to(target) <= shockwave_radius() + HIT_PAD:
				_deal(e, spell.hammer_shockwave_damage, mods)
	# #420: barricades take any player-sourced damage. Slam radius only; not
	# counted as hits/kills, so the Rhythm/dice bookkeeping is unchanged.
	if Barricade.is_player_side(OnHit.live(source)):
		for b in get_tree().get_nodes_in_group(&"barricades"):
			if is_instance_valid(b) and (b as Node2D).global_position.distance_to(target) <= radius + HIT_PAD:
				_deal(b, spell.damage, mods)
	if caster != null and is_instance_valid(caster):
		var res: Dictionary = caster.hammer_state.register_strike(spell, hits, kills)
		if int(res["tone_step"]) > 0:
			play_tone(self, caster.hammer_state.last_tone_pitch)
		if int(res["dice_face"]) > 0 and is_instance_valid(source):
			var parent := _drop_parent if _drop_parent != null and is_instance_valid(_drop_parent) else get_parent()
			HammerDice.spawn(source, int(res["dice_face"]), res["dice_entry"], parent)
	CombatEffects.death_burst(get_parent(), target, DUST)
	struck.emit(target, hits, kills)
	queue_redraw()

func _living_enemies() -> Array[Node]:
	var out: Array[Node] = []
	for e in get_tree().get_nodes_in_group(&"enemies"):
		if not is_instance_valid(e) or not (e is Node2D) or e.is_queued_for_deletion():
			continue
		var hp: Variant = e.get(&"hp")
		if hp == null or int(hp) <= 0:
			continue
		out.append(e)
	return out

func _deal(body: Node, amount: float, mods: DamageModifiers) -> void:
	if not body.has_method(&"apply_damage"):
		return
	var rng: RandomNumberGenerator = null
	if is_instance_valid(source):
		rng = source.get(&"damage_rng") as RandomNumberGenerator
	if rng == null:
		rng = RandomNumberGenerator.new()
	var result := DamageCalc.compute(amount, mods, body.get(&"damage_modifiers") as DamageModifiers, rng)
	var receipt := OnHit.begin(body)
	if body is Enemy:
		body.apply_damage(result.amount, result.crit_tier)
	else:
		body.apply_damage(result.amount)
	OnHit.end(receipt, body)
	# #390: slam and Rhythm shockwave both report as melee hits of this spell.
	OnHit.report(source, spell, body, result, OnHit.DELIVERY_MELEE, receipt)

const CombatEffects = preload("res://scripts/combat_effects.gd")

# ---- Hit tone (Rhythm route) ----------------------------------------------

static var _tone_stream: AudioStreamWAV = null

## A short code-generated "tink": a decaying sine at 660 Hz. Pitch rises per
## combo step through pitch_scale.
static func tone_stream() -> AudioStreamWAV:
	if _tone_stream != null:
		return _tone_stream
	var rate := 22050
	var n := int(rate * 0.14)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := exp(-t * 28.0) * minf(t * 400.0, 1.0)
		var s := sin(TAU * 660.0 * t) * 0.8 + sin(TAU * 1320.0 * t) * 0.2
		data.encode_s16(i * 2, int(clampf(s * env, -1.0, 1.0) * 26000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	_tone_stream = w
	return w

static func play_tone(at: Node, pitch: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = "HammerTone"
	p.stream = tone_stream()
	p.pitch_scale = maxf(pitch, 0.05)
	p.volume_db = -6.0
	p.add_to_group(&"hammer_tones")
	at.get_tree().current_scene.add_child(p)
	p.play()
	# Self-cleanup does not rely on `finished` (no audio device in CI).
	at.get_tree().create_timer(0.6).timeout.connect(p.queue_free)
	return p

# ---- Drawing ---------------------------------------------------------------

func _draw() -> void:
	if _landed:
		_draw_impact()
		return
	var k := clampf(_t / maxf(spell.hammer_windup, 0.01), 0.0, 1.0)
	# Landing marker: ring + a fill that grows toward the slam.
	draw_circle(Vector2.ZERO, radius, Color(0.45, 0.35, 0.25, 0.10 + 0.15 * k))
	draw_circle(Vector2.ZERO, radius * k, Color(0.8, 0.6, 0.35, 0.18))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(0.85, 0.7, 0.5, 0.75), 2.0)
	if spell.hammer_shockwave_radius > 0.0:
		draw_arc(Vector2.ZERO, shockwave_radius(), 0.0, TAU, 48, Color(0.85, 0.7, 0.5, 0.25), 1.0)
	# Overhead swing: the head starts above the caster's hands and accelerates
	# down onto the target.
	var hand := Vector2.ZERO
	if is_instance_valid(source):
		hand = source.global_position - global_position + Vector2(0.0, -14.0)
	var e := k * k
	var head := hand.lerp(Vector2.ZERO, e) + Vector2(0.0, -OVERHEAD * size_scale * (1.0 - e))
	_draw_hammer(hand, head)

func _draw_hammer(hand: Vector2, head: Vector2) -> void:
	var axis := head - hand
	var ang := axis.angle() if axis.length() > 0.5 else -PI * 0.5
	draw_line(hand, head, HANDLE, 4.0 * sqrt(size_scale))
	var sz := HEAD_SIZE * size_scale
	draw_set_transform(head, ang + PI * 0.5, Vector2.ONE)
	var rect := Rect2(-sz * 0.5, sz)
	draw_rect(rect, STONE, true)
	draw_rect(Rect2(rect.position, Vector2(sz.x, sz.y * 0.3)), STONE.lightened(0.25), true)
	draw_rect(rect, STONE_DARK, false, 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_impact() -> void:
	var k := clampf(_impact_t / IMPACT_TIME, 0.0, 1.0)
	var a := 1.0 - k
	draw_circle(Vector2.ZERO, radius * (0.7 + 0.5 * k), Color(DUST.r, DUST.g, DUST.b, 0.35 * a))
	draw_arc(Vector2.ZERO, radius * (0.8 + 0.6 * k), 0.0, TAU, 40, Color(0.95, 0.85, 0.65, a), 3.0)
	for i in 7:
		var ang := TAU * float(i) / 7.0 + 0.4
		var d := Vector2(cos(ang), sin(ang))
		draw_line(d * radius * 0.15, d * radius * (0.6 + 0.2 * sin(i * 1.7)), Color(0.2, 0.17, 0.14, a), 2.0)
	if spell.hammer_shockwave_radius > 0.0:
		var r := shockwave_radius() * (0.4 + 0.6 * k)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 56, Color(1.0, 0.9, 0.7, 0.8 * a), 4.0 * a + 1.0)
	# The head rests in the crater while the dust settles.
	var sz := HEAD_SIZE * size_scale
	draw_rect(Rect2(-sz * 0.5, sz), Color(STONE.r, STONE.g, STONE.b, a), true)
	draw_rect(Rect2(-sz * 0.5, sz), Color(STONE_DARK.r, STONE_DARK.g, STONE_DARK.b, a), false, 2.0)
