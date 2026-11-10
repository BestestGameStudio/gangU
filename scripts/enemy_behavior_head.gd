class_name EnemyBehaviorHead
extends BossBehavior
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
## The shared loop skeleton lives in BossBehavior (#513 PART1); this file
## keeps the Head's attack data, timing and attack logic.
##
## Timings and damage are PLACEHOLDER tuning (balance is human-open).

const BOLT_SPELL: Spell = preload("res://resources/spells/head_bolt.tres")
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/projectile.tscn")

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

var _waves_fired: int = 0
var _pulses: int = 0

## The Head's pre-#513 initial attack was VOLLEY (Warlord/Beast: LUNGE);
## restore it for exact initial-state parity. Never read before the first
## _start_windup overwrites it.
func _init() -> void:
	super()
	attack = Attack.VOLLEY

# --- BossBehavior hooks ------------------------------------------------------

func _arrival_color() -> Color:
	return HEAD_RED

func _has_stun_phase() -> bool:
	return true

func _first_attack_delay() -> float:
	return FIRST_ATTACK_DELAY

func _attack_interval() -> float:
	return ATTACK_INTERVAL

func _enraged_interval() -> float:
	return ENRAGED_INTERVAL

func _recover_time() -> float:
	return RECOVER_TIME

func _stun_time() -> float:
	return STUN_TIME

func _windup_time(which: int) -> float:
	return WINDUP_TIME[which]

func _windup_anim(which: int) -> StringName:
	return WINDUP_ANIM[which]

func _step(enemy: Enemy, player: Player, to_player: Vector2, delta: float, tele: BossTelegraph) -> void:
	match state:
		State.CHASE:
			_chase(enemy, player, to_player, delta, tele)
		State.WINDUP:
			_windup(enemy, to_player, tele)
		State.VOLLEY:
			_volley(enemy, to_player)
		State.PULSE:
			_pulse(enemy, player, to_player, tele)

func _show_windup_telegraph(enemy: Enemy, which: int, dur: float, tele: BossTelegraph) -> void:
	match which:
		Attack.VOLLEY:
			tele.show_cone(_dir, VOLLEY_CONE_LENGTH, deg_to_rad(_volley_spread(enemy)), dur)
		Attack.PULSE:
			tele.show_ring(_pulse_radius(enemy), dur)

func _finish_windup(enemy: Enemy, tele: BossTelegraph) -> void:
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

# --- CHASE -------------------------------------------------------------------

func _pick_attack(dist: float) -> int:
	var pick: int = Attack.PULSE if dist < PULSE_RANGE else Attack.VOLLEY
	var fallback: int = Attack.VOLLEY if pick == Attack.PULSE else Attack.PULSE
	return _history_pick(pick, fallback)

# --- ATTACKS -----------------------------------------------------------------

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
