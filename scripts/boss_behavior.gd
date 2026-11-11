class_name BossBehavior
extends EnemyBehavior
## #513 PART1: shared base for the boss behaviors (#173 Head, #174 Beast,
## #177 Warlord), extracted from three near-identical copies. Holds the
## State/Attack enums, the physics_step prologue (arrival pop, one-time
## phase stun, dead/absent player guard, RECOVER), is_enraged, the
## anti-repeat attack history, the wind-up skeleton and the shared
## transitions. Each subclass keeps its own attack data, constants, timing
## and attack logic; behavior is unchanged. Contact damage stays in the shared
## _chase (the DamageCalc/OnHit reroute is NOT part of PART1).

enum State { CHASE, WINDUP, LUNGE, SPIN, VOLLEY, PULSE, SCREAM, RECOVER, STUN }
enum Attack { LUNGE, SPIN, VOLLEY, PULSE, SCREAM }

const CombatEffects = preload("res://scripts/combat_effects.gd")

## Fraction of the wind-up after which the aim locks (the dodge window).
const AIM_LOCK_AT: float = 0.6

var state: int = State.CHASE
var attack: int = Attack.LUNGE
## True once the <= 50% HP phase change (stun) has happened.
var phase_two: bool = false
var _t: float = 0.0
var _attack_timer: float = 0.0
var _dir: Vector2 = Vector2.RIGHT
var _history: Array[int] = []
var _entered: bool = false
var _contact_timer: float = 0.0

## Per-boss tuning, set by the subclass in _configure() (called from _init).
var first_attack_delay: float = 1.0
var attack_interval: float = 1.8
var enraged_interval: float = 1.0
var recover_time: float = 0.5
var stun_time: float = 1.6
## Head/Beast stun once at the phase change; Warlord does not.
var has_stun_phase: bool = false
var arrival_color: Color = Enemy.SPRITE_BURST_COLOR
var clear_glow_on_stun: bool = false
var windup_times: Dictionary = {}
var windup_anims: Dictionary = {}

func _init() -> void:
	_configure()
	_attack_timer = first_attack_delay

## Per-boss: load authored tuning and configure attacks.
func _configure() -> void:
	pass

## Copy mutable dictionaries so authored data cannot acquire per-enemy state.
func _apply_tuning(tuning: BossTuning) -> void:
	first_attack_delay = tuning.first_attack_delay
	attack_interval = tuning.attack_interval
	enraged_interval = tuning.enraged_interval
	recover_time = tuning.recover_time
	stun_time = tuning.stun_time
	has_stun_phase = tuning.has_stun_phase
	arrival_color = tuning.arrival_color
	clear_glow_on_stun = tuning.clear_glow_on_stun
	windup_times = tuning.windup_times.duplicate(true)
	windup_anims = tuning.windup_anims.duplicate(true)

## Shared prologue of every boss step; the per-boss states run via _step.
func physics_step(enemy: Enemy, player: Player, delta: float) -> void:
	var tele := enemy.get_node_or_null("Telegraph") as BossTelegraph
	if not _entered:
		_entered = true
		# Arrival pop - visual only, same effect family as hits/deaths.
		CombatEffects.death_burst(enemy.get_parent(), enemy.global_position, arrival_color)
	if not phase_two and is_enraged(enemy) and has_stun_phase:
		_enter_stun(enemy, tele)
	if state == State.STUN:
		enemy.velocity = Vector2.ZERO
		_t += delta
		if _t >= stun_time:
			_enter_chase(enemy, tele)
		enemy.terrain_move_and_slide()
		return
	if player == null or not is_instance_valid(player) or player.hp <= 0:
		if state != State.CHASE:
			_enter_chase(enemy, tele)
		enemy.velocity = Vector2.ZERO
		enemy.terrain_move_and_slide()
		return
	_t += delta
	var to_player: Vector2 = player.global_position - enemy.global_position
	if state == State.RECOVER:
		enemy.velocity = Vector2.ZERO
		if _t >= recover_time:
			_enter_chase(enemy, tele)
	else:
		_step(enemy, player, to_player, delta, tele)
	enemy.terrain_move_and_slide()

func is_enraged(enemy: Enemy) -> bool:
	return enemy.hp * 2 <= enemy.max_hp

# --- per-boss hooks ----------------------------------------------------------

## The per-boss state machine (CHASE / WINDUP / the attacks).
var attack_steps: Dictionary = {}

func _step(enemy: Enemy, player: Player, to_player: Vector2, delta: float, tele: BossTelegraph) -> void:
	match state:
		State.CHASE:
			_chase(enemy, player, to_player, delta, tele)
		State.WINDUP:
			_windup(enemy, to_player, tele)
		_:
			if attack_steps.has(state):
				var step: Callable = attack_steps[state]
				step.call(enemy, player, to_player, delta, tele)

func _dispatch_volley(enemy: Enemy, _player: Player, to_player: Vector2, _delta: float, _tele: BossTelegraph) -> void:
	_volley_step(enemy, to_player)

# --- CHASE -------------------------------------------------------------------

## Float after the player, bite on contact, and start a wind-up when the
## attack timer runs out (the attack itself comes from _pick_attack).
func _chase(enemy: Enemy, player: Player, to_player: Vector2, delta: float, tele: BossTelegraph) -> void:
	var dist: float = to_player.length()
	enemy.velocity = to_player.normalized() * enemy.speed if dist > 8.0 else Vector2.ZERO
	_contact_timer = maxf(0.0, _contact_timer - delta)
	if dist <= enemy.contact_range and _contact_timer <= 0.0:
		player.apply_damage(enemy.contact_damage)
		_contact_timer = enemy.contact_cooldown
		_face(enemy, to_player.x)
		enemy.play_action(&"attack")
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_start_windup(enemy, _pick_attack(dist), to_player, tele)

## Per-boss: which attack to start at this distance.
func _pick_attack(dist: float) -> int:
	for rule in attack_ranges:
		if (dist > rule.threshold if rule.above else dist < rule.threshold):
			return _history_pick(rule.pick, rule.fallback)
	return _history_pick(default_attack, default_fallback)

# --- WIND-UP (telegraph) -----------------------------------------------------

func _start_windup(enemy: Enemy, which: int, to_player: Vector2, tele: BossTelegraph) -> void:
	attack = which
	state = State.WINDUP
	_t = 0.0
	_windup_reset(which)
	_dir = to_player.normalized() if to_player.length_squared() > 0.0 else Vector2.RIGHT
	enemy.velocity = Vector2.ZERO
	_face(enemy, _dir.x)
	enemy.play_action(_windup_anim(which), true)
	if enemy.sprite != null:
		enemy.sprite.set_glow(true)
	if tele != null:
		_show_windup_telegraph(enemy, which, _windup_time(which), tele)

func _windup(enemy: Enemy, to_player: Vector2, tele: BossTelegraph) -> void:
	enemy.velocity = Vector2.ZERO
	var dur: float = _windup_duration()
	# Track the player early in the wind-up, then lock: the locked tail is
	# the dodge window.
	if _t < dur * AIM_LOCK_AT and to_player.length_squared() > 0.0:
		_dir = to_player.normalized()
		_face(enemy, _dir.x)
		if tele != null:
			tele.set_direction(_dir)
	if _t < dur:
		return
	if enemy.sprite != null:
		enemy.sprite.set_glow(false)
	_t = 0.0
	_finish_windup(enemy, tele)

func _windup_reset(_which: int) -> void:
	pass

func _windup_duration() -> float:
	return _windup_time(attack)

func _windup_time(which: int) -> float:
	return windup_times[which]

func _windup_anim(which: int) -> StringName:
	return windup_anims[which]

func _show_windup_telegraph(enemy: Enemy, which: int, dur: float, tele: BossTelegraph) -> void:
	var p: BossAttack = presentations[which]
	match p.shape:
		TelegraphShape.LINE:
			tele.show_line(_dir, p.length, p.width, dur)
		TelegraphShape.RING:
			tele.show_ring(_ring_radius(enemy) if p.phase_ring else p.radius, dur)
		TelegraphShape.CONE:
			tele.show_cone(_dir, p.length, deg_to_rad(_volley_spread(enemy)), dur)

## Counter reset + transition into the attack state once the wind-up ends.
func _finish_windup(enemy: Enemy, tele: BossTelegraph) -> void:
	_attack_begin_reset()
	var p: BossAttack = presentations[attack]
	state = p.next_state
	_attack_begin_count()
	enemy.play_action(p.animation, true)
	if tele != null:
		if p.start_ring:
			tele.show_ring(p.radius, p.start_duration, true)
		elif p.clear_on_start:
			tele.clear()

func _attack_begin_reset() -> void:
	pass

func _attack_begin_count() -> void:
	pass

# --- anti-repeat picker ------------------------------------------------------

## The same attack never runs three times in a row (range picks a fallback).
func _history_pick(pick: int, fallback: int) -> int:
	if _history.size() >= 2 and _history[-1] == pick and _history[-2] == pick:
		pick = fallback
	_history.append(pick)
	if _history.size() > 4:
		_history.pop_front()
	return pick

# --- transitions ---------------------------------------------------------------

## Phase change (once): drop whatever was happening and reel, stunned.
func _enter_stun(enemy: Enemy, tele: BossTelegraph) -> void:
	phase_two = true
	state = State.STUN
	_t = 0.0
	enemy.velocity = Vector2.ZERO
	enemy.clear_action()
	if clear_glow_on_stun and enemy.sprite != null:
		enemy.sprite.set_glow(false)
	enemy.play_action(&"stun", true)
	if tele != null:
		tele.clear()

func _enter_recover(enemy: Enemy) -> void:
	state = State.RECOVER
	_t = 0.0
	enemy.velocity = Vector2.ZERO
	enemy.clear_action()

func _enter_chase(enemy: Enemy, tele: BossTelegraph) -> void:
	state = State.CHASE
	_t = 0.0
	_attack_timer = enraged_interval if is_enraged(enemy) else attack_interval
	enemy.clear_action()
	if tele != null:
		tele.clear()

func _face(enemy: Enemy, dir_x: float) -> void:
	if enemy.sprite != null:
		enemy.sprite.face(dir_x)

# --- shared volley attack ----------------------------------------------------

## Attack data is supplied by Head/Warlord from their unchanged constants.

var volley_data: BossVolleyData
var _waves_fired: int = 0

func _volley_step(enemy: Enemy, to_player: Vector2) -> void:
	enemy.velocity = Vector2.ZERO
	if _waves_fired == 0 and _t >= volley_data.fire_at:
		_fire_wave(enemy, _dir, 0.0)
	elif _waves_fired == 1 and is_enraged(enemy) and _t >= volley_data.second_wave_at:
		# The staggered second wave re-aims and fills the first wave's gaps.
		if to_player.length_squared() > 0.0:
			_dir = to_player.normalized()
		var shots: int = _volley_shots(enemy)
		var half_gap: float = deg_to_rad(_volley_spread(enemy)) / float(maxi(shots - 1, 1)) * 0.5
		_fire_wave(enemy, _dir, half_gap)
	if _t >= volley_data.duration:
		_enter_recover(enemy)

func _fire_wave(enemy: Enemy, aim: Vector2, rot: float) -> void:
	_waves_fired += 1
	var dirs: Array[Vector2] = SpellFanout.directions(aim.rotated(rot), _volley_shots(enemy), _volley_spread(enemy))
	var area: Node = enemy.get_parent()
	var origin: Vector2 = enemy.global_position + aim * volley_data.muzzle_offset
	for d in dirs:
		var p: Projectile = volley_data.scene.instantiate()
		p.setup(volley_data.spell, d, enemy)
		p.position = origin
		_decorate_volley_projectile(p, area)
		area.call_deferred("add_child", p)
	CombatEffects.muzzle(area, origin, aim.angle(), volley_data.spell.projectile_color)

## Warlord installs its sheet orb visual and impact pop; Head does nothing.
func _decorate_volley_projectile(_projectile: Projectile, _area: Node) -> void:
	pass

func _volley_shots(enemy: Enemy) -> int:
	return volley_data.enraged_shots if is_enraged(enemy) else volley_data.shots

func _volley_spread(enemy: Enemy) -> float:
	return volley_data.enraged_spread if is_enraged(enemy) else volley_data.spread

# --- shared lunge attack -----------------------------------------------------


var lunge_data: BossLungeData
var _hits: int = 0

## Movement/contact are shared; the caller keeps its end/chain transition.
func _lunge_step(enemy: Enemy, player: Player, dist: float) -> void:
	enemy.velocity = _dir * (lunge_data.enraged_speed if is_enraged(enemy) else lunge_data.speed)
	if _hits == 0 and dist <= lunge_data.hit_range:
		_hits = 1
		player.apply_damage(lunge_data.damage)
		CombatEffects.hit_spark(enemy.get_parent(), player.global_position)

## Beast's first enraged lunge chains; Warlord always recovers.
## Do movement/contact first, including the frame that ends the lunge.
func _lunge_sequence(enemy: Enemy, player: Player, dist: float, tele: BossTelegraph, completed: int = 0) -> void:
	_lunge_step(enemy, player, dist)
	if _t < lunge_data.duration:
		return
	if lunge_data.enraged_chain and is_enraged(enemy) and completed < 2:
		state = State.WINDUP
		_t = 0.0
		enemy.velocity = Vector2.ZERO
		enemy.play_action(lunge_data.chain_animation, true)
		if enemy.sprite != null:
			enemy.sprite.set_glow(true)
		if tele != null:
			tele.show_line(_dir, lunge_data.chain_length, lunge_data.hit_range * 0.6, lunge_data.chain_pause)
		return
	_enter_recover(enemy)

# --- shared ring attack ------------------------------------------------------


var ring_data: BossRingData

func _ring_radius(enemy: Enemy) -> float:
	return ring_data.enraged_radius if is_enraged(enemy) else ring_data.radius

## Owners retain ring count, stagger/phase timing and recover transitions.
func _ring_release(enemy: Enemy, player: Player, to_player: Vector2, radius: float, tele: BossTelegraph) -> void:
	if tele != null:
		tele.show_ring(radius, ring_data.display_time, true)
	CombatEffects.death_burst(enemy.get_parent(), enemy.global_position, ring_data.color)
	if to_player.length() <= radius:
		player.apply_damage(ring_data.damage)
		CombatEffects.hit_spark(enemy.get_parent(), player.global_position)

## Counter property names retain the original per-boss reset/test contract.
## Increment before release, including when the current frame also recovers.
func _ring_sequence(enemy: Enemy, player: Player, to_player: Vector2, tele: BossTelegraph, counter: StringName) -> void:
	enemy.velocity = Vector2.ZERO
	var enraged: bool = is_enraged(enemy)
	var count: int = get(counter)
	if count == 0:
		set(counter, 1)
		_ring_release(enemy, player, to_player, _ring_radius(enemy) if ring_data.phase_first_radius else ring_data.radius, tele)
	elif count == 1 and enraged and ring_data.enraged_second_ring and _t >= ring_data.second_at:
		enemy.play_action(ring_data.second_animation, true)
		set(counter, 2)
		_ring_release(enemy, player, to_player, ring_data.enraged_radius, tele)
	if _t >= (ring_data.enraged_duration if enraged else ring_data.duration):
		if tele != null:
			tele.clear()
		_enter_recover(enemy)

# --- data-driven attack presentation -----------------------------------------
enum TelegraphShape { LINE, RING, CONE }

var presentations: Dictionary = {}

# --- ordered distance-based attack selection ---------------------------------
class AttackRange extends RefCounted:
	var threshold: float
	var above: bool
	var pick: int
	var fallback: int

var attack_ranges: Array[AttackRange] = []
var default_attack: int = Attack.LUNGE
var default_fallback: int = Attack.VOLLEY

func _range(threshold: float, above: bool, pick: int, fallback: int) -> void:
	var rule := AttackRange.new()
	rule.threshold = threshold
	rule.above = above
	rule.pick = pick
	rule.fallback = fallback
	attack_ranges.append(rule)
