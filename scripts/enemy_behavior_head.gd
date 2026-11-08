class_name EnemyBehaviorHead
extends RefCounted
## #173: the Head boss behavior (boss of the DungeonC arena), slotted through
## the #99 behavior seam (resources/enemies/head_boss.tres), so the boss is a
## plain Enemy (same HP / damage / died() contract) with its own brain.
## Modelled on EnemyBehaviorWarlord (#177); animations come from the #173
## sheet (resources/sprites/head_boss_frames.tres).
##
## Loop: CHASE (float after the player + contact bite) -> every
## ATTACK_INTERVAL pick an attack by range, WIND UP (telegraph + glowing
## sprite, the player's dodge window) -> ATTACK -> RECOVER -> CHASE.
##   VOLLEY (far)   - "windup_projectile" (eyes ignite) + cone telegraph that
##                    tracks then locks; "projectile" (the scream) fires a fan
##                    of crimson bolts as real Projectiles (scenes/projectile.tscn
##                    + resources/spells/head_bolt.tres).
##   PULSE  (close) - "windup_aoe" + filling ring telegraph; "aoe" releases a
##                    shockwave ring (drawn in-engine by the telegraph: the
##                    sheet's ring art overlaps its neighbours, so only the
##                    heads were cut) that hits once inside PULSE_RADIUS.
## Phase change at <= 50% HP: the Head is STUNNED once ("stun" anim, halo
## spinning) for STUN_TIME - a free damage window - then enraged: shorter
## gaps, a second staggered volley wave, and a second, wider pulse.
## The same attack never runs three times in a row (range picks a fallback).
##
## Timings and damage are PLACEHOLDER tuning (balance is human-open).

enum State { CHASE, WINDUP, VOLLEY, PULSE, RECOVER, STUN }
enum Attack { VOLLEY, PULSE }

const BOLT_SPELL: Spell = preload("res://resources/spells/head_bolt.tres")
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/projectile.tscn")
const CombatEffects = preload("res://scripts/combat_effects.gd")

## The Head's crimson (eyes / aura on the sheet), for its own FX.
const HEAD_RED: Color = Color(1.0, 0.22, 0.32)

# PLACEHOLDER tuning below (balance is human-open).
const FIRST_ATTACK_DELAY: float = 1.0
const ATTACK_INTERVAL: float = 1.8
const ENRAGED_INTERVAL: float = 1.0
const RECOVER_TIME: float = 0.5
const STUN_TIME: float = 1.6

const PULSE_RANGE: float = 150.0 ## closer than this -> PULSE, else VOLLEY

const WINDUP_TIME: Dictionary = {Attack.VOLLEY: 0.7, Attack.PULSE: 0.75}
const WINDUP_ANIM: Dictionary = {Attack.VOLLEY: &"windup_projectile", Attack.PULSE: &"windup_aoe"}
const AIM_LOCK_AT: float = 0.6 ## fraction of the wind-up after which aim locks

const VOLLEY_SHOTS: int = 5
const VOLLEY_SHOTS_ENRAGED: int = 7
const VOLLEY_SPREAD_DEG: float = 48.0
const VOLLEY_SPREAD_ENRAGED_DEG: float = 66.0
const VOLLEY_FIRE_AT: float = 0.12 ## into the "projectile" anim (mouth opens)
const VOLLEY_SECOND_WAVE_AT: float = 0.4 ## enraged only
const VOLLEY_TIME: float = 0.55
const VOLLEY_CONE_LENGTH: float = 230.0
const MUZZLE_OFFSET: float = 30.0

const PULSE_RADIUS: float = 120.0
const PULSE_RADIUS_ENRAGED: float = 175.0 ## the enraged second ring
const PULSE_DAMAGE: int = 16
const PULSE_TIME: float = 0.5
const PULSE_SECOND_AT: float = 0.3 ## enraged only, into the pulse
const PULSE_TIME_ENRAGED: float = 0.75

var state: int = State.CHASE
var attack: int = Attack.VOLLEY
## True once the <= 50% HP phase change (stun) has happened.
var phase_two: bool = false
var _t: float = 0.0
var _attack_timer: float = FIRST_ATTACK_DELAY
var _contact_timer: float = 0.0
var _dir: Vector2 = Vector2.RIGHT
var _waves_fired: int = 0
var _pulses: int = 0
var _history: Array[int] = []
var _entered: bool = false

func physics_step(enemy: Enemy, player: Player, delta: float) -> void:
	var tele := enemy.get_node_or_null("Telegraph") as BossTelegraph
	if not _entered:
		_entered = true
		# Arrival pop - visual only, same effect family as hits/deaths.
		CombatEffects.death_burst(enemy.get_parent(), enemy.global_position, HEAD_RED)
	if not phase_two and is_enraged(enemy):
		_enter_stun(enemy, tele)
	if state == State.STUN:
		enemy.velocity = Vector2.ZERO
		_t += delta
		if _t >= STUN_TIME:
			_enter_chase(enemy, tele)
		enemy.move_and_slide()
		return
	if player == null or not is_instance_valid(player) or player.hp <= 0:
		if state != State.CHASE:
			_enter_chase(enemy, tele)
		enemy.velocity = Vector2.ZERO
		enemy.move_and_slide()
		return
	_t += delta
	var to_player: Vector2 = player.global_position - enemy.global_position
	match state:
		State.CHASE:
			_chase(enemy, player, to_player, delta, tele)
		State.WINDUP:
			_windup(enemy, to_player, tele)
		State.VOLLEY:
			_volley(enemy, to_player)
		State.PULSE:
			_pulse(enemy, player, to_player, tele)
		State.RECOVER:
			enemy.velocity = Vector2.ZERO
			if _t >= RECOVER_TIME:
				_enter_chase(enemy, tele)
	enemy.move_and_slide()

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
	var pick: int = Attack.PULSE if dist < PULSE_RANGE else Attack.VOLLEY
	var fallback: int = Attack.VOLLEY if pick == Attack.PULSE else Attack.PULSE
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
			Attack.VOLLEY:
				tele.show_cone(_dir, VOLLEY_CONE_LENGTH, deg_to_rad(_volley_spread(enemy)), dur)
			Attack.PULSE:
				tele.show_ring(_pulse_radius(enemy), dur)

func _windup(enemy: Enemy, to_player: Vector2, tele: BossTelegraph) -> void:
	enemy.velocity = Vector2.ZERO
	var dur: float = WINDUP_TIME[attack]
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
	_waves_fired = 0
	_pulses = 0
	match attack:
		Attack.VOLLEY:
			state = State.VOLLEY
			enemy.play_action(&"projectile", true)
			if tele != null:
				tele.clear()
		Attack.PULSE:
			state = State.PULSE
			enemy.play_action(&"aoe", true)

# --- ATTACKS ---------------------------------------------------------------

func _volley(enemy: Enemy, to_player: Vector2) -> void:
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
	var dirs: Array[Vector2] = SpellFanout.directions(aim.rotated(rot), _volley_shots(enemy), _volley_spread(enemy))
	var area: Node = enemy.get_parent()
	var origin: Vector2 = enemy.global_position + aim * MUZZLE_OFFSET
	for d in dirs:
		var p: Projectile = PROJECTILE_SCENE.instantiate()
		p.setup(BOLT_SPELL, d, enemy)
		p.position = origin
		# D14: never add to the tree synchronously from a physics step.
		area.call_deferred("add_child", p)
	CombatEffects.muzzle(area, origin, aim.angle(), BOLT_SPELL.projectile_color)

## One shockwave per ring: the first at PULSE_RADIUS as the "aoe" anim
## starts, and (enraged) a second, wider one PULSE_SECOND_AT later. Each
## ring hits the player at most once.
func _pulse(enemy: Enemy, player: Player, to_player: Vector2, tele: BossTelegraph) -> void:
	enemy.velocity = Vector2.ZERO
	var enraged: bool = is_enraged(enemy)
	if _pulses == 0:
		_release_ring(enemy, player, to_player, PULSE_RADIUS, tele)
	elif _pulses == 1 and enraged and _t >= PULSE_SECOND_AT:
		enemy.play_action(&"aoe", true)
		_release_ring(enemy, player, to_player, PULSE_RADIUS_ENRAGED, tele)
	if _t >= (PULSE_TIME_ENRAGED if enraged else PULSE_TIME):
		if tele != null:
			tele.clear()
		_enter_recover(enemy)

func _release_ring(enemy: Enemy, player: Player, to_player: Vector2, radius: float, tele: BossTelegraph) -> void:
	_pulses += 1
	if tele != null:
		tele.show_ring(radius, PULSE_TIME, true)
	CombatEffects.death_burst(enemy.get_parent(), enemy.global_position, HEAD_RED)
	if to_player.length() <= radius:
		player.apply_damage(PULSE_DAMAGE)
		CombatEffects.hit_spark(enemy.get_parent(), player.global_position)

func _volley_shots(enemy: Enemy) -> int:
	return VOLLEY_SHOTS_ENRAGED if is_enraged(enemy) else VOLLEY_SHOTS

func _volley_spread(enemy: Enemy) -> float:
	return VOLLEY_SPREAD_ENRAGED_DEG if is_enraged(enemy) else VOLLEY_SPREAD_DEG

## The wind-up ring shows the outermost ring the pulse will reach.
func _pulse_radius(enemy: Enemy) -> float:
	return PULSE_RADIUS_ENRAGED if is_enraged(enemy) else PULSE_RADIUS

# --- transitions -----------------------------------------------------------

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
	_attack_timer = ENRAGED_INTERVAL if is_enraged(enemy) else ATTACK_INTERVAL
	enemy.clear_action()
	if tele != null:
		tele.clear()

func _face(enemy: Enemy, dir_x: float) -> void:
	if enemy.sprite != null:
		enemy.sprite.face(dir_x)
