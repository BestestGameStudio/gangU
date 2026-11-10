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

var _pulses: int = 0

## The Head's pre-#513 initial attack was VOLLEY (Warlord/Beast: LUNGE);
## restore it for exact initial-state parity. Never read before the first
## _start_windup overwrites it.
func _init() -> void:
	super()
	attack = Attack.VOLLEY

# --- BossBehavior hooks ------------------------------------------------------

func _configure() -> void:
	first_attack_delay = FIRST_ATTACK_DELAY
	attack_interval = ATTACK_INTERVAL
	enraged_interval = ENRAGED_INTERVAL
	recover_time = RECOVER_TIME
	stun_time = STUN_TIME
	has_stun_phase = true
	arrival_color = HEAD_RED
	windup_times = WINDUP_TIME
	windup_anims = WINDUP_ANIM
	volley_data = VolleyData.new()
	volley_data.spell = BOLT_SPELL
	volley_data.scene = PROJECTILE_SCENE
	volley_data.shots = VOLLEY_SHOTS
	volley_data.enraged_shots = VOLLEY_SHOTS_ENRAGED
	volley_data.spread = VOLLEY_SPREAD_DEG
	volley_data.enraged_spread = VOLLEY_SPREAD_ENRAGED_DEG
	volley_data.fire_at = VOLLEY_FIRE_AT
	volley_data.second_wave_at = VOLLEY_SECOND_WAVE_AT
	volley_data.duration = VOLLEY_TIME
	volley_data.muzzle_offset = MUZZLE_OFFSET

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
	_volley_step(enemy, to_player)

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

## The wind-up ring shows the outermost ring the pulse will reach.
func _pulse_radius(enemy: Enemy) -> float:
	return PULSE_RADIUS_ENRAGED if is_enraged(enemy) else PULSE_RADIUS
