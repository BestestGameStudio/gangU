class_name EnemyBehaviorWarlord
extends BossBehavior
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
## The shared loop skeleton lives in BossBehavior (#513 PART1); this file
## keeps the Warlord's attack data, timing and attack logic.
##
## Timings and damage are PLACEHOLDER tuning (balance is human-open).

const ORB_SPELL: Spell = preload("res://resources/spells/warlord_orb.tres")
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/projectile.tscn")

const FIRST_ATTACK_DELAY: float = 1.2
const ATTACK_INTERVAL: float = 1.9
const ENRAGED_INTERVAL: float = 1.1
const RECOVER_TIME: float = 0.45

const SPIN_RANGE: float = 130.0 ## closer than this -> SPIN
const VOLLEY_RANGE: float = 270.0 ## farther than this -> VOLLEY

const WINDUP_TIME: Dictionary = {Attack.LUNGE: 0.6, Attack.SPIN: 0.5, Attack.VOLLEY: 0.65}
const WINDUP_ANIM: Dictionary = {Attack.LUNGE: &"windup_lunge", Attack.SPIN: &"windup_spin", Attack.VOLLEY: &"windup_ranged"}

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

var _tick_t: float = 0.0

# --- BossBehavior hooks ------------------------------------------------------

func _configure() -> void:
	attack_steps = {State.LUNGE: _dispatch_lunge, State.SPIN: _dispatch_spin, State.VOLLEY: _dispatch_volley}
	first_attack_delay = FIRST_ATTACK_DELAY
	attack_interval = ATTACK_INTERVAL
	enraged_interval = ENRAGED_INTERVAL
	recover_time = RECOVER_TIME
	windup_times = WINDUP_TIME
	windup_anims = WINDUP_ANIM
	lunge_data = LungeData.new()
	lunge_data.speed = LUNGE_SPEED
	lunge_data.enraged_speed = LUNGE_SPEED_ENRAGED
	lunge_data.duration = LUNGE_TIME
	lunge_data.hit_range = LUNGE_HIT_RANGE
	lunge_data.damage = LUNGE_DAMAGE
	volley_data = VolleyData.new()
	volley_data.spell = ORB_SPELL
	volley_data.scene = PROJECTILE_SCENE
	volley_data.shots = VOLLEY_SHOTS
	volley_data.enraged_shots = VOLLEY_SHOTS_ENRAGED
	volley_data.spread = VOLLEY_SPREAD_DEG
	volley_data.enraged_spread = VOLLEY_SPREAD_ENRAGED_DEG
	volley_data.fire_at = VOLLEY_FIRE_AT
	volley_data.second_wave_at = VOLLEY_SECOND_WAVE_AT
	volley_data.duration = VOLLEY_TIME
	volley_data.muzzle_offset = MUZZLE_OFFSET

	var lunge := _present(Attack.LUNGE, State.LUNGE, &"lunge", TelegraphShape.LINE)
	lunge.length = LUNGE_LENGTH
	lunge.width = LUNGE_HIT_RANGE * 0.6
	var spin := _present(Attack.SPIN, State.SPIN, &"spin", TelegraphShape.RING)
	spin.radius = SPIN_RADIUS
	spin.start_ring = true
	spin.start_duration = SPIN_TIME
	var volley := _present(Attack.VOLLEY, State.VOLLEY, &"ranged", TelegraphShape.CONE)
	volley.length = 220.0


func _attack_begin_reset() -> void:
	_hits = 0
	_tick_t = 0.0
	_waves_fired = 0

# --- CHASE -------------------------------------------------------------------

func _pick_attack(dist: float) -> int:
	var pick: int = Attack.LUNGE
	var fallback: int = Attack.VOLLEY
	if dist < SPIN_RANGE:
		pick = Attack.SPIN
		fallback = Attack.LUNGE
	elif dist > VOLLEY_RANGE:
		pick = Attack.VOLLEY
		fallback = Attack.LUNGE
	return _history_pick(pick, fallback)

# --- ATTACKS -----------------------------------------------------------------

func _lunge(enemy: Enemy, player: Player, dist: float, _tele: BossTelegraph) -> void:
	_lunge_step(enemy, player, dist)
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
	_volley_step(enemy, to_player)

func _decorate_volley_projectile(p: Projectile, area: Node) -> void:
	p.visual_override = WarlordOrbVisual.new()
	p.hit.connect(func(_body: Node2D) -> void:
		if is_instance_valid(p) and is_instance_valid(area):
			WarlordOrbVisual.spawn_pop(area, p.global_position))

func _dispatch_lunge(enemy: Enemy, player: Player, to_player: Vector2, _delta: float, tele: BossTelegraph) -> void:
	_lunge(enemy, player, to_player.length(), tele)

func _dispatch_spin(enemy: Enemy, player: Player, to_player: Vector2, delta: float, tele: BossTelegraph) -> void:
	_spin(enemy, player, to_player, delta, tele)
