class_name BossBehavior
extends RefCounted
## #513 PART1: shared base for the boss behaviors (#173 Head, #174 Beast,
## #177 Warlord), extracted from three near-identical copies. Holds the
## State/Attack enums, the physics_step prologue (arrival pop, one-time
## phase stun, dead/absent player guard, RECOVER), is_enraged, the
## anti-repeat attack history, the wind-up skeleton and the shared
## transitions. Each subclass keeps its own attack data, constants, timing
## and attack logic; behavior is unchanged. Contact damage stays in each
## subclass's _chase (the DamageCalc/OnHit reroute is NOT part of PART1).

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

func _init() -> void:
	_attack_timer = _first_attack_delay()

## Shared prologue of every boss step; the per-boss states run via _step.
func physics_step(enemy: Enemy, player: Player, delta: float) -> void:
	var tele := enemy.get_node_or_null("Telegraph") as BossTelegraph
	if not _entered:
		_entered = true
		# Arrival pop - visual only, same effect family as hits/deaths.
		CombatEffects.death_burst(enemy.get_parent(), enemy.global_position, _arrival_color())
	if not phase_two and is_enraged(enemy) and _has_stun_phase():
		_enter_stun(enemy, tele)
	if state == State.STUN:
		enemy.velocity = Vector2.ZERO
		_t += delta
		if _t >= _stun_time():
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
		if _t >= _recover_time():
			_enter_chase(enemy, tele)
	else:
		_step(enemy, player, to_player, delta, tele)
	enemy.terrain_move_and_slide()

func is_enraged(enemy: Enemy) -> bool:
	return enemy.hp * 2 <= enemy.max_hp

# --- per-boss hooks ----------------------------------------------------------

## The per-boss state machine (CHASE / WINDUP / the attacks).
func _step(_enemy: Enemy, _player: Player, _to_player: Vector2, _delta: float, _tele: BossTelegraph) -> void:
	pass

func _arrival_color() -> Color:
	return Enemy.SPRITE_BURST_COLOR

## Head/Beast stun once at the phase change; Warlord does not.
func _has_stun_phase() -> bool:
	return false

func _first_attack_delay() -> float:
	return 1.0

func _attack_interval() -> float:
	return 1.8

func _enraged_interval() -> float:
	return 1.0

func _recover_time() -> float:
	return 0.5

func _stun_time() -> float:
	return 1.6

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

func _windup_time(_which: int) -> float:
	return 0.0

func _windup_anim(_which: int) -> StringName:
	return &""

func _show_windup_telegraph(_enemy: Enemy, _which: int, _dur: float, _tele: BossTelegraph) -> void:
	pass

## Counter reset + transition into the attack state once the wind-up ends.
func _finish_windup(_enemy: Enemy, _tele: BossTelegraph) -> void:
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
	_attack_timer = _enraged_interval() if is_enraged(enemy) else _attack_interval()
	enemy.clear_action()
	if tele != null:
		tele.clear()

func _face(enemy: Enemy, dir_x: float) -> void:
	if enemy.sprite != null:
		enemy.sprite.face(dir_x)
