class_name EnemyBehaviorBeast
extends BossBehavior
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
	first_attack_delay = FIRST_ATTACK_DELAY
	attack_interval = ATTACK_INTERVAL
	enraged_interval = ENRAGED_INTERVAL
	recover_time = RECOVER_TIME
	stun_time = STUN_TIME
	has_stun_phase = true
	arrival_color = BEAST_GREEN
	windup_times = WINDUP_TIME
	windup_anims = WINDUP_ANIM
	ring_data = RingData.new()
	ring_data.radius = SCREAM_RADIUS
	ring_data.enraged_radius = SCREAM_RADIUS_ENRAGED
	ring_data.damage = SCREAM_DAMAGE
	ring_data.display_time = SCREAM_TIME
	ring_data.color = BEAST_GREEN
	lunge_data = LungeData.new()
	lunge_data.speed = LUNGE_SPEED
	lunge_data.enraged_speed = LUNGE_SPEED_ENRAGED
	lunge_data.duration = LUNGE_TIME
	lunge_data.hit_range = LUNGE_HIT_RANGE
	lunge_data.damage = LUNGE_DAMAGE
	var lunge := _present(Attack.LUNGE, State.LUNGE, &"bite", TelegraphShape.LINE)
	lunge.length = LUNGE_LENGTH
	lunge.width = LUNGE_HIT_RANGE * 0.6
	var scream := _present(Attack.SCREAM, State.SCREAM, &"aoe", TelegraphShape.RING)
	scream.phase_ring = true
	scream.clear_on_start = false


## Enraged chain: the second lunge's "wind-up" is just the re-aim pause.
func _windup_duration() -> float:
	if attack == Attack.LUNGE and _lunges > 0:
		return LUNGE_CHAIN_PAUSE
	return WINDUP_TIME[attack]

func _windup_reset(_which: int) -> void:
	_lunges = 0

func _step(enemy: Enemy, player: Player, to_player: Vector2, delta: float, tele: BossTelegraph) -> void:
	match state:
		State.CHASE:
			_chase(enemy, player, to_player, delta, tele)
		State.WINDUP:
			_windup(enemy, to_player, tele)
		State.LUNGE:
			_lunge(enemy, player, to_player, tele)
		State.SCREAM:
			_scream(enemy, player, to_player, tele)

func _attack_begin_reset() -> void:
	_hits = 0

func _attack_begin_count() -> void:
	if attack == Attack.LUNGE:
		_lunges += 1
	elif attack == Attack.SCREAM:
		_screams = 0

# --- CHASE -------------------------------------------------------------------

func _pick_attack(dist: float) -> int:
	var pick: int = Attack.SCREAM if dist < SCREAM_RANGE else Attack.LUNGE
	var fallback: int = Attack.LUNGE if pick == Attack.SCREAM else Attack.SCREAM
	return _history_pick(pick, fallback)

# --- ATTACKS -----------------------------------------------------------------

func _lunge(enemy: Enemy, player: Player, to_player: Vector2, tele: BossTelegraph) -> void:
	var enraged: bool = is_enraged(enemy)
	_lunge_step(enemy, player, to_player.length())
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
		_ring_release(enemy, player, to_player, _scream_radius(enemy), tele)
	if _t >= SCREAM_TIME:
		if tele != null:
			tele.clear()
		_enter_recover(enemy)

func _scream_radius(enemy: Enemy) -> float:
	return _ring_radius(enemy)

# --- transitions ---------------------------------------------------------------

## Phase change (once): drop whatever was happening and reel, stunned.
## The Beast also drops its wind-up glow (unlike the Head).
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
