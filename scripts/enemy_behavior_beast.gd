class_name EnemyBehaviorBeast
extends RefCounted
## #174: the Beast boss behavior, slotted through the #99 behavior seam
## (resources/enemies/beast_boss.tres), so the boss is a plain Enemy (same
## HP / damage / died() contract) with its own brain. Modelled on
## EnemyBehaviorHead (#173) and EnemyBehaviorWarlord (#177); animations come
## from the #174 sheet (resources/sprites/beast_boss_frames.tres).
##
## Loop: CHASE (stalk the player + contact bite) -> every ATTACK_INTERVAL
## pick an attack by range, WIND UP (telegraph + glowing sprite, the player's
## dodge window) -> ATTACK -> RECOVER -> CHASE.
##   LUNGE  (far)   - "windup_bite" + a line telegraph that tracks then locks;
##                    "bite" dashes along it and snaps once on contact.
##   SCREAM (close) - "windup_aoe" + filling ring telegraph; "aoe" releases a
##                    shockwave ring (drawn in-engine by the telegraph) that
##                    hits once inside SCREAM_RADIUS.
## Phase change at <= 50% HP: STUNNED once ("stun", star halo) for STUN_TIME
## - a free damage window - then enraged: shorter gaps, a faster lunge that
## chains into a second re-aimed lunge, and a wider scream.
## The same attack never runs three times in a row (range picks a fallback).
##
## Timings and damage are PLACEHOLDER tuning (balance is human-open).

enum State { CHASE, WINDUP, LUNGE, SCREAM, RECOVER, STUN }
enum Attack { LUNGE, SCREAM }

const CombatEffects = preload("res://scripts/combat_effects.gd")

## The Beast's acid green (eyes / FX on the sheet), for its own FX.
const BEAST_GREEN: Color = Color(0.72, 1.0, 0.26)

# PLACEHOLDER tuning below (balance is human-open).
const FIRST_ATTACK_DELAY: float = 1.0
const ATTACK_INTERVAL: float = 1.7
const ENRAGED_INTERVAL: float = 1.0
const RECOVER_TIME: float = 0.5
const STUN_TIME: float = 1.6

const SCREAM_RANGE: float = 140.0 ## closer than this -> SCREAM, else LUNGE

const WINDUP_TIME: Dictionary = {Attack.LUNGE: 0.65, Attack.SCREAM: 0.75}
const WINDUP_ANIM: Dictionary = {Attack.LUNGE: &"windup_bite", Attack.SCREAM: &"windup_aoe"}
const AIM_LOCK_AT: float = 0.6 ## fraction of the wind-up after which aim locks

const LUNGE_SPEED: float = 600.0
const LUNGE_SPEED_ENRAGED: float = 740.0
const LUNGE_TIME: float = 0.34
const LUNGE_LENGTH: float = 210.0 ## telegraph length (~ speed * time)
const LUNGE_HIT_RANGE: float = 60.0
const LUNGE_DAMAGE: int = 18
const LUNGE_CHAIN_PAUSE: float = 0.22 ## enraged: pause before the second lunge

const SCREAM_RADIUS: float = 125.0
const SCREAM_RADIUS_ENRAGED: float = 180.0
const SCREAM_DAMAGE: int = 15
const SCREAM_TIME: float = 0.55

var state: int = State.CHASE
var attack: int = Attack.LUNGE
## True once the <= 50% HP phase change (stun) has happened.
var phase_two: bool = false
var _t: float = 0.0
var _attack_timer: float = FIRST_ATTACK_DELAY
var _contact_timer: float = 0.0
var _dir: Vector2 = Vector2.RIGHT
var _hits: int = 0
var _lunges: int = 0
var _screams: int = 0
var _history: Array[int] = []
var _entered: bool = false

func physics_step(enemy: Enemy, player: Player, delta: float) -> void:
	var tele := enemy.get_node_or_null("Telegraph") as BossTelegraph
	if not _entered:
		_entered = true
		# Arrival pop - visual only, same effect family as hits/deaths.
		CombatEffects.death_burst(enemy.get_parent(), enemy.global_position, BEAST_GREEN)
	if not phase_two and is_enraged(enemy):
		_enter_stun(enemy, tele)
	if state == State.STUN:
		enemy.velocity = Vector2.ZERO
		_t += delta
		if _t >= STUN_TIME:
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
	match state:
		State.CHASE:
			_chase(enemy, player, to_player, delta, tele)
		State.WINDUP:
			_windup(enemy, to_player, tele)
		State.LUNGE:
			_lunge(enemy, player, to_player, tele)
		State.SCREAM:
			_scream(enemy, player, to_player, tele)
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
	var pick: int = Attack.SCREAM if dist < SCREAM_RANGE else Attack.LUNGE
	var fallback: int = Attack.LUNGE if pick == Attack.SCREAM else Attack.SCREAM
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
	_lunges = 0
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
			Attack.SCREAM:
				tele.show_ring(_scream_radius(enemy), dur)

func _windup(enemy: Enemy, to_player: Vector2, tele: BossTelegraph) -> void:
	enemy.velocity = Vector2.ZERO
	var dur: float = WINDUP_TIME[attack]
	if attack == Attack.LUNGE and _lunges > 0:
		dur = LUNGE_CHAIN_PAUSE
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
	_hits = 0
	match attack:
		Attack.LUNGE:
			state = State.LUNGE
			_lunges += 1
			enemy.play_action(&"bite", true)
			if tele != null:
				tele.clear()
		Attack.SCREAM:
			state = State.SCREAM
			_screams = 0
			enemy.play_action(&"aoe", true)

# --- ATTACKS ---------------------------------------------------------------

func _lunge(enemy: Enemy, player: Player, to_player: Vector2, tele: BossTelegraph) -> void:
	var enraged: bool = is_enraged(enemy)
	enemy.velocity = _dir * (LUNGE_SPEED_ENRAGED if enraged else LUNGE_SPEED)
	if _hits == 0 and to_player.length() <= LUNGE_HIT_RANGE:
		_hits = 1
		player.apply_damage(LUNGE_DAMAGE)
		CombatEffects.hit_spark(enemy.get_parent(), player.global_position)
	if _t < LUNGE_TIME:
		return
	if enraged and _lunges < 2:
		# Chain: a short re-aimed pause, then a second lunge.
		state = State.WINDUP
		_t = 0.0
		enemy.velocity = Vector2.ZERO
		enemy.play_action(&"windup_bite", true)
		if enemy.sprite != null:
			enemy.sprite.set_glow(true)
		if tele != null:
			tele.show_line(_dir, LUNGE_LENGTH, LUNGE_HIT_RANGE * 0.6, LUNGE_CHAIN_PAUSE)
		return
	_enter_recover(enemy)

func _scream(enemy: Enemy, player: Player, to_player: Vector2, tele: BossTelegraph) -> void:
	enemy.velocity = Vector2.ZERO
	if _screams == 0:
		_screams = 1
		var radius: float = _scream_radius(enemy)
		if tele != null:
			tele.show_ring(radius, SCREAM_TIME, true)
		CombatEffects.death_burst(enemy.get_parent(), enemy.global_position, BEAST_GREEN)
		if to_player.length() <= radius:
			player.apply_damage(SCREAM_DAMAGE)
			CombatEffects.hit_spark(enemy.get_parent(), player.global_position)
	if _t >= SCREAM_TIME:
		if tele != null:
			tele.clear()
		_enter_recover(enemy)

func _scream_radius(enemy: Enemy) -> float:
	return SCREAM_RADIUS_ENRAGED if is_enraged(enemy) else SCREAM_RADIUS

# --- transitions -----------------------------------------------------------

## Phase change (once): drop whatever was happening and reel, stunned.
func _enter_stun(enemy: Enemy, tele: BossTelegraph) -> void:
	phase_two = true
	state = State.STUN
	_t = 0.0
	enemy.velocity = Vector2.ZERO
	enemy.clear_action()
	if enemy.sprite != null:
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
	_attack_timer = ENRAGED_INTERVAL if is_enraged(enemy) else ATTACK_INTERVAL
	enemy.clear_action()
	if tele != null:
		tele.clear()

func _face(enemy: Enemy, dir_x: float) -> void:
	if enemy.sprite != null:
		enemy.sprite.face(dir_x)
