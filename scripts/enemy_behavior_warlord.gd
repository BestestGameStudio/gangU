class_name EnemyBehaviorWarlord
extends RefCounted
## #177: Mustache Warlord boss behavior - slotted through the #99 behavior
## seam (resources/enemies/mustache_warlord.tres), so the boss is a plain
## Enemy (same HP / damage / died() contract) with its own brain.
##
## Loop: CHASE (walk + contact swipe) -> every ATTACK_INTERVAL pick an attack
## by range, WIND UP (telegraph + glowing sprite, the player's dodge window)
## -> ATTACK -> RECOVER -> CHASE.
##   LUNGE  (mid range)  - aims a line, locks it, then dashes along it.
##   SPIN   (close)      - ground ring, then a spinning blade storm that
##                         drifts after the player and ticks damage.
##   VOLLEY (far)        - cone telegraph, then a fan of green orbs fired as
##                         real Projectiles (scenes/projectile.tscn) wearing
##                         the sheet's orb art (WarlordOrbVisual).
## Enraged at <= 50% HP: shorter gaps, wider double volleys, faster lunges.
## The same attack never runs three times in a row (range picks a fallback).
##
## Timings and damage are PLACEHOLDER tuning (balance is human-open).

enum State { CHASE, WINDUP, LUNGE, SPIN, VOLLEY, RECOVER }
enum Attack { LUNGE, SPIN, VOLLEY }

const ORB_SPELL: Spell = preload("res://resources/spells/warlord_orb.tres")
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/projectile.tscn")
const CombatEffects = preload("res://scripts/combat_effects.gd")

const FIRST_ATTACK_DELAY: float = 1.2
const ATTACK_INTERVAL: float = 1.9
const ENRAGED_INTERVAL: float = 1.1
const RECOVER_TIME: float = 0.45

const SPIN_RANGE: float = 130.0 ## closer than this -> SPIN
const VOLLEY_RANGE: float = 270.0 ## farther than this -> VOLLEY

const WINDUP_TIME: Dictionary = {Attack.LUNGE: 0.6, Attack.SPIN: 0.5, Attack.VOLLEY: 0.65}
const WINDUP_ANIM: Dictionary = {Attack.LUNGE: &"windup_lunge", Attack.SPIN: &"windup_spin", Attack.VOLLEY: &"windup_ranged"}
const LUNGE_LOCK_AT: float = 0.6 ## fraction of the wind-up after which aim locks

const LUNGE_SPEED: float = 560.0
const LUNGE_SPEED_ENRAGED: float = 700.0
const LUNGE_TIME: float = 0.32
const LUNGE_LENGTH: float = 190.0 ## telegraph length (~ speed * time)
const LUNGE_HIT_RANGE: float = 58.0
const LUNGE_DAMAGE: int = 18

const SPIN_TIME: float = 0.95
const SPIN_RADIUS: float = 72.0
const SPIN_TICK: float = 0.5
const SPIN_DAMAGE: int = 12
const SPIN_DRIFT: float = 0.7 ## fraction of walk speed while spinning

const VOLLEY_SHOTS: int = 5
const VOLLEY_SHOTS_ENRAGED: int = 7
const VOLLEY_SPREAD_DEG: float = 50.0
const VOLLEY_SPREAD_ENRAGED_DEG: float = 70.0
const VOLLEY_FIRE_AT: float = 0.2 ## into the "ranged" anim (orb leaves the hand)
const VOLLEY_SECOND_WAVE_AT: float = 0.45 ## enraged only
const VOLLEY_TIME: float = 0.6
const MUZZLE_OFFSET: float = 34.0

var state: int = State.CHASE
var attack: int = Attack.LUNGE
var _t: float = 0.0
var _attack_timer: float = FIRST_ATTACK_DELAY
var _contact_timer: float = 0.0
var _dir: Vector2 = Vector2.RIGHT
var _hits: int = 0
var _tick_t: float = 0.0
var _waves_fired: int = 0
var _history: Array[int] = []
var _entered: bool = false

func physics_step(enemy: Enemy, player: Player, delta: float) -> void:
	var tele := enemy.get_node_or_null("Telegraph") as BossTelegraph
	if not _entered:
		_entered = true
		# Arrival pop - visual only, same effect family as hits/deaths.
		CombatEffects.death_burst(enemy.get_parent(), enemy.global_position, Enemy.SPRITE_BURST_COLOR)
	if player == null or not is_instance_valid(player) or player.hp <= 0:
		if state != State.CHASE:
			_enter_chase(enemy, tele)
		enemy.velocity = Vector2.ZERO
		enemy.terrain_move_and_slide()
		return
	_t += delta
	var to_player: Vector2 = player.global_position - enemy.global_position
	var dist: float = to_player.length()
	match state:
		State.CHASE:
			_chase(enemy, player, to_player, delta, tele)
		State.WINDUP:
			_windup(enemy, to_player, tele)
		State.LUNGE:
			_lunge(enemy, player, dist, tele)
		State.SPIN:
			_spin(enemy, player, to_player, delta, tele)
		State.VOLLEY:
			_volley(enemy, to_player, tele)
		State.RECOVER:
			enemy.velocity = Vector2.ZERO
			if _t >= RECOVER_TIME:
				_enter_chase(enemy, tele)
	enemy.terrain_move_and_slide()

func is_enraged(enemy: Enemy) -> bool:
	return enemy.hp * 2 <= enemy.max_hp

# --- CHASE -----------------------------------------------------------------

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

func _pick_attack(dist: float) -> int:
	var pick: int = Attack.LUNGE
	var fallback: int = Attack.VOLLEY
	if dist < SPIN_RANGE:
		pick = Attack.SPIN
		fallback = Attack.LUNGE
	elif dist > VOLLEY_RANGE:
		pick = Attack.VOLLEY
		fallback = Attack.LUNGE
	if _history.size() >= 2 and _history[-1] == pick and _history[-2] == pick:
		pick = fallback
	_history.append(pick)
	if _history.size() > 4:
		_history.pop_front()
	return pick

# --- WIND-UP (telegraph) ---------------------------------------------------

func _start_windup(enemy: Enemy, which: int, to_player: Vector2, tele: BossTelegraph) -> void:
	attack = which
	state = State.WINDUP
	_t = 0.0
	_dir = to_player.normalized() if to_player.length_squared() > 0.0 else Vector2.RIGHT
	enemy.velocity = Vector2.ZERO
	_face(enemy, _dir.x)
	enemy.play_action(WINDUP_ANIM[which], true)
	if enemy.sprite != null:
		enemy.sprite.set_glow(true)
	if tele != null:
		var dur: float = WINDUP_TIME[which]
		match which:
			Attack.LUNGE:
				tele.show_line(_dir, LUNGE_LENGTH, LUNGE_HIT_RANGE * 0.6, dur)
			Attack.SPIN:
				tele.show_ring(SPIN_RADIUS, dur)
			Attack.VOLLEY:
				tele.show_cone(_dir, 220.0, deg_to_rad(_volley_spread(enemy)), dur)

func _windup(enemy: Enemy, to_player: Vector2, tele: BossTelegraph) -> void:
	enemy.velocity = Vector2.ZERO
	var dur: float = WINDUP_TIME[attack]
	# Track the player early in the wind-up, then lock: the locked tail is
	# the dodge window.
	if _t < dur * LUNGE_LOCK_AT and to_player.length_squared() > 0.0:
		_dir = to_player.normalized()
		_face(enemy, _dir.x)
		if tele != null:
			tele.set_direction(_dir)
	if _t < dur:
		return
	if enemy.sprite != null:
		enemy.sprite.set_glow(false)
	_t = 0.0
	_hits = 0
	_tick_t = 0.0
	_waves_fired = 0
	match attack:
		Attack.LUNGE:
			state = State.LUNGE
			enemy.play_action(&"lunge", true)
			if tele != null:
				tele.clear()
		Attack.SPIN:
			state = State.SPIN
			enemy.play_action(&"spin", true)
			if tele != null:
				tele.show_ring(SPIN_RADIUS, SPIN_TIME, true)
		Attack.VOLLEY:
			state = State.VOLLEY
			enemy.play_action(&"ranged", true)
			if tele != null:
				tele.clear()

# --- ATTACKS ---------------------------------------------------------------

func _lunge(enemy: Enemy, player: Player, dist: float, _tele: BossTelegraph) -> void:
	var spd: float = LUNGE_SPEED_ENRAGED if is_enraged(enemy) else LUNGE_SPEED
	enemy.velocity = _dir * spd
	if _hits == 0 and dist <= LUNGE_HIT_RANGE:
		_hits = 1
		player.apply_damage(LUNGE_DAMAGE)
		CombatEffects.hit_spark(enemy.get_parent(), player.global_position)
	if _t >= LUNGE_TIME:
		_enter_recover(enemy)

func _spin(enemy: Enemy, player: Player, to_player: Vector2, delta: float, tele: BossTelegraph) -> void:
	enemy.velocity = to_player.normalized() * enemy.speed * SPIN_DRIFT if to_player.length() > 8.0 else Vector2.ZERO
	_tick_t -= delta
	if _tick_t <= 0.0 and to_player.length() <= SPIN_RADIUS:
		_tick_t = SPIN_TICK
		_hits += 1
		player.apply_damage(SPIN_DAMAGE)
		CombatEffects.hit_spark(enemy.get_parent(), player.global_position)
	if _t >= SPIN_TIME:
		if tele != null:
			tele.clear()
		_enter_recover(enemy)

func _volley(enemy: Enemy, to_player: Vector2, _tele: BossTelegraph) -> void:
	enemy.velocity = Vector2.ZERO
	if _waves_fired == 0 and _t >= VOLLEY_FIRE_AT:
		_fire_wave(enemy, _dir, 0.0)
	elif _waves_fired == 1 and is_enraged(enemy) and _t >= VOLLEY_SECOND_WAVE_AT:
		# Second wave re-aims and staggers half a gap so it fills the holes.
		if to_player.length_squared() > 0.0:
			_dir = to_player.normalized()
		var shots: int = _volley_shots(enemy)
		var half_gap: float = deg_to_rad(_volley_spread(enemy)) / float(maxi(shots - 1, 1)) * 0.5
		_fire_wave(enemy, _dir, half_gap)
	if _t >= VOLLEY_TIME:
		_enter_recover(enemy)

func _fire_wave(enemy: Enemy, aim: Vector2, rot: float) -> void:
	_waves_fired += 1
	var shots: int = _volley_shots(enemy)
	var spread: float = _volley_spread(enemy)
	var dirs: Array[Vector2] = SpellFanout.directions(aim.rotated(rot), shots, spread)
	var area: Node = enemy.get_parent()
	var origin: Vector2 = enemy.global_position + aim * MUZZLE_OFFSET
	for d in dirs:
		var p: Projectile = PROJECTILE_SCENE.instantiate()
		p.setup(ORB_SPELL, d, enemy)
		p.position = origin
		# Sheet orb art + impact pop, for these projectiles only.
		p.visual_override = WarlordOrbVisual.new()
		p.hit.connect(func(_body: Node2D) -> void:
			if is_instance_valid(p) and is_instance_valid(area):
				WarlordOrbVisual.spawn_pop(area, p.global_position))
		# D14: never add to the tree synchronously from a physics step.
		area.call_deferred("add_child", p)
	CombatEffects.muzzle(area, origin, aim.angle(), ORB_SPELL.projectile_color)

func _volley_shots(enemy: Enemy) -> int:
	return VOLLEY_SHOTS_ENRAGED if is_enraged(enemy) else VOLLEY_SHOTS

func _volley_spread(enemy: Enemy) -> float:
	return VOLLEY_SPREAD_ENRAGED_DEG if is_enraged(enemy) else VOLLEY_SPREAD_DEG

# --- transitions -----------------------------------------------------------

func _enter_recover(enemy: Enemy) -> void:
	state = State.RECOVER
	_t = 0.0
	enemy.velocity = Vector2.ZERO
	enemy.clear_action()

func _enter_chase(enemy: Enemy, tele: BossTelegraph) -> void:
	state = State.CHASE
	_t = 0.0
	_attack_timer = ENRAGED_INTERVAL if is_enraged(enemy) else ATTACK_INTERVAL
	enemy.clear_action()
	if tele != null:
		tele.clear()

func _face(enemy: Enemy, dir_x: float) -> void:
	if enemy.sprite != null:
		enemy.sprite.face(dir_x)
