class_name EnemyBehaviorBeast
extends BossBehavior
## #174: the Beast boss behavior, slotted through the #99 behavior seam
## (data/enemies/beast_boss.tres), so the boss is a plain Enemy (same
## HP / damage / died() contract) with its own brain. Modelled on
## EnemyBehaviorHead (#173) and EnemyBehaviorWarlord (#177); animations come
## from the #174 sheet (data/sprites/beast_boss_frames.tres).
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
## The shared loop skeleton lives in BossBehavior (#513 PART1); this file
## keeps the Beast's attack data, timing and attack logic.
##
## Timings and damage are PLACEHOLDER tuning (balance is human-open).

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

var _lunges: int = 0
var _screams: int = 0

# --- BossBehavior hooks ------------------------------------------------------

func _configure() -> void:
	default_attack = Attack.LUNGE
	default_fallback = Attack.SCREAM
	_range(SCREAM_RANGE, false, Attack.SCREAM, Attack.LUNGE)
	attack_steps = {State.LUNGE: _dispatch_lunge, State.SCREAM: _dispatch_scream}
	_apply_tuning(load("res://data/boss_attacks/beast_tuning.tres"))
	ring_data = load("res://data/boss_attacks/beast_ring.tres")
	lunge_data = load("res://data/boss_attacks/beast_lunge.tres")
	presentations = {
		Attack.LUNGE: load("res://data/boss_attacks/beast_lunge_presentation.tres"),
		Attack.SCREAM: load("res://data/boss_attacks/beast_scream_presentation.tres"),
	}


## Enraged chain: second lunge uses the original short re-aim pause.

func _windup_duration() -> float:
	if attack == Attack.LUNGE and _lunges > 0:
		return LUNGE_CHAIN_PAUSE
	return WINDUP_TIME[attack]

func _windup_reset(_which: int) -> void:
	_lunges = 0

func _attack_begin_reset() -> void:
	_hits = 0

func _attack_begin_count() -> void:
	if attack == Attack.LUNGE:
		_lunges += 1
	elif attack == Attack.SCREAM:
		_screams = 0

# --- CHASE -------------------------------------------------------------------


# --- ATTACKS -----------------------------------------------------------------

func _lunge(enemy: Enemy, player: Player, to_player: Vector2, tele: BossTelegraph) -> void:
	_lunge_sequence(enemy, player, to_player.length(), tele, _lunges)

func _scream(enemy: Enemy, player: Player, to_player: Vector2, tele: BossTelegraph) -> void:
	_ring_sequence(enemy, player, to_player, tele, &"_screams")

func _scream_radius(enemy: Enemy) -> float:
	return _ring_radius(enemy)

func _dispatch_lunge(enemy: Enemy, player: Player, to_player: Vector2, _delta: float, tele: BossTelegraph) -> void:
	_lunge(enemy, player, to_player, tele)

func _dispatch_scream(enemy: Enemy, player: Player, to_player: Vector2, _delta: float, tele: BossTelegraph) -> void:
	_scream(enemy, player, to_player, tele)
