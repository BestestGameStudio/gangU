class_name EnemyBehaviorFishy
extends EnemyBehavior
## #464: the Fishy. A tanky support enemy with a fishing rod. It keeps its
## distance, winds up a straight-line cast toward the player and, if the hook
## lands, reels the player in while the line deals damage over time. While
## the player is hooked the Fishy rallies nearby allies (Enemy.rally): the
## Mustache Warriors leave cover and group up on the reeled-in player.
##
## Issue rules (real-human-123, #464):
## - the rod has very long range but only travels in a straight line
##   (aim locks before the cast; the hook never steers);
## - a hooked player is reeled in toward the Fishy;
## - the line deals continuous damage while the player is hooked;
## - the cast is cancelled when the hook hits terrain (the projectile rule:
##   TerrainTypes "blocks_projectiles" cells plus TerrainMap canopy circles);
## - Fishy is much tankier than normal enemies but below a boss (definition).
##
## Counterplay (implementation choice, open for review): the wind-up shows the
## lane (BossTelegraph line) and the aim locks AIM_LOCK_AT into it; a dash or
## i-frames make the hook miss; dashing while hooked snaps the line; the line
## also snaps when terrain comes between the Fishy and the player, when the
## reel stalls against terrain, or after HOOK_MAX_TIME.
##
## All numbers below are PLACEHOLDER balance.

enum State { APPROACH, WINDUP, CAST, HOOKED, RECOVER }

const HOOK_RANGE := 560.0 ## "very long range" (Mustache cover search is 384)
const HOOK_SPEED := 950.0 ## px/s, straight line
const HOOK_HIT_RADIUS := 22.0 ## player catch radius around the line tip
const WINDUP_TIME := 0.6
const AIM_LOCK_AT := 0.35 ## aim tracks the player until here, then locks
const REEL_SPEED := 380.0 ## px/s; beats the 320 px/s walk, so walking away only slows it
const REEL_STOP := 46.0 ## reeled in: the line lets go at this distance
const HOOK_MAX_TIME := 2.4
const TICK_INTERVAL := 0.25
const TICK_DAMAGE := 3 ## per tick while hooked (12 dps before modifiers)
const STALL_TIME := 0.3 ## reel blocked by terrain this long: the line snaps
const RETRACT_SPEED := 1400.0
const RECOVER_TIME := 0.45
const CAST_COOLDOWN := 2.4
const KEEP_AWAY := 150.0 ## backs off when the player is closer than this
const ENGAGE_FRACTION := 0.85 ## walks closer until within this share of HOOK_RANGE
const ALLY_RADIUS := 520.0 ## who hears the rally
const RALLY_TIME := 2.5
const RALLY_INTERVAL := 0.5
## Rod tip relative to the body (art faces right; mirrored when flipped).
const ROD_TIP := Vector2(16, -22)

## #513: authored behavior tuning; constants remain compatibility defaults.
@export var hook_range: float = HOOK_RANGE
@export var hook_speed: float = HOOK_SPEED
@export var hook_hit_radius: float = HOOK_HIT_RADIUS
@export var windup_time: float = WINDUP_TIME
@export var aim_lock_at: float = AIM_LOCK_AT
@export var reel_speed: float = REEL_SPEED
@export var reel_stop: float = REEL_STOP
@export var hook_max_time: float = HOOK_MAX_TIME
@export var tick_interval: float = TICK_INTERVAL
@export var tick_damage: int = TICK_DAMAGE
@export var stall_time: float = STALL_TIME
@export var retract_speed: float = RETRACT_SPEED
@export var recover_time: float = RECOVER_TIME
@export var cast_cooldown: float = CAST_COOLDOWN
@export var keep_away: float = KEEP_AWAY
@export var engage_fraction: float = ENGAGE_FRACTION
@export var ally_radius: float = ALLY_RADIUS
@export var rally_time: float = RALLY_TIME
@export var rally_interval: float = RALLY_INTERVAL
@export var rod_tip_offset: Vector2 = ROD_TIP

var state: int = State.APPROACH
var hooked_player: Player = null
var hook_pos := Vector2.ZERO
var aim_dir := Vector2.RIGHT
## Why the last cast ended: &"miss", &"terrain", &"hooked", &"reeled",
## &"dash", &"blocked", &"timeout", &"stalled", &"dead". Read by tests.
var last_result: StringName = &""

var _t := 0.0
var _cooldown := 0.6
var _traveled := 0.0
var _tick_t := 0.0
var _rally_t := 0.0
var _stall_t := 0.0
var _contact_timer := 0.0
var _cast_origin := Vector2.ZERO
var _terrain_path := TerrainPath.new()
## Engagement (overworld variant): home post + whether the target is noticed.
var home := Vector2.INF
var engaged := false
var _last_hp := -1

## #513: authored post/notice variant, INF preserves dungeon behavior.
@export var notice_radius: float = INF
@export var leash_radius: float = INF

## Distance at which the Fishy notices the player. INF (dungeons): always.
func _notice_radius() -> float:
	return notice_radius

## Give-up distance from home. INF (dungeons): never.
func _leash_radius() -> float:
	return leash_radius

func physics_step(enemy: Enemy, player, delta: float) -> void:
	if home == Vector2.INF:
		home = enemy.global_position
	_cooldown = maxf(_cooldown - delta, 0.0)
	_contact_timer = maxf(_contact_timer - delta, 0.0)
	var target := player as Player
	var alive := target != null and is_instance_valid(target) and target.hp > 0
	_update_engaged(enemy, target, alive)
	match state:
		State.APPROACH:
			if not alive or not engaged:
				_go_home(enemy, delta)
			else:
				_approach(enemy, target, delta)
		State.WINDUP:
			_windup(enemy, target, alive, delta)
		State.CAST:
			_cast(enemy, target, alive, delta)
		State.HOOKED:
			_hooked(enemy, delta)
		State.RECOVER:
			_recover(enemy, delta)
	_sync_line(enemy)

func is_hooked() -> bool:
	return state == State.HOOKED

func rod_tip(enemy: Enemy) -> Vector2:
	var tip := rod_tip_offset
	if enemy.sprite != null and enemy.sprite.flip_h:
		tip.x = -tip.x
	return enemy.global_position + tip

# --- engagement -------------------------------------------------------------

func _update_engaged(enemy: Enemy, target: Player, alive: bool) -> void:
	if _last_hp >= 0 and enemy.hp < _last_hp:
		engaged = true # hit from afar: fight back
	_last_hp = enemy.hp
	if not alive:
		engaged = false
		return
	var d := enemy.global_position.distance_to(target.global_position)
	if d <= _notice_radius():
		engaged = true
	if state == State.APPROACH and home.distance_to(target.global_position) > _leash_radius():
		engaged = false

func _go_home(enemy: Enemy, delta: float) -> void:
	var to := home - enemy.global_position
	var want := Vector2.ZERO if to.length() <= 6.0 else to.normalized() * minf(enemy.speed, to.length() / maxf(delta, 0.0001))
	enemy.velocity = _terrain_path.steer(enemy.terrain, enemy.global_position, enemy.velocity, want, home, enemy.speed, delta, enemy.can_swim)
	enemy.move_and_slide()

# --- APPROACH ---------------------------------------------------------------

func _approach(enemy: Enemy, target: Player, delta: float) -> void:
	var to: Vector2 = target.global_position - enemy.global_position
	var d := to.length()
	var clear := _line_clear(enemy, enemy.global_position, target.global_position)
	var want := Vector2.ZERO
	if d > hook_range * engage_fraction or not clear:
		want = to.normalized() * enemy.speed
		enemy.velocity = _terrain_path.steer(enemy.terrain, enemy.global_position, enemy.velocity, want, target.global_position, enemy.speed, delta, enemy.can_swim)
	elif d < keep_away:
		want = -to.normalized() * enemy.speed * 0.8
		enemy.velocity = TerrainMotion.resolve(enemy.terrain, enemy.global_position, enemy.velocity, want, delta, enemy.can_swim)
	else:
		enemy.velocity = Vector2.ZERO
	enemy.move_and_slide()
	if enemy.velocity.length() < 1.0 and enemy.sprite != null:
		enemy.sprite.face(to.x)
	# Up close the rod doubles as a club (plain contact hit).
	if d <= enemy.contact_range and _contact_timer <= 0.0:
		enemy.deal_hit(target, enemy.contact_damage, OnHit.DELIVERY_CONTACT)
		_contact_timer = enemy.contact_cooldown
		enemy.play_action(&"attack")
	if _cooldown <= 0.0 and clear and d <= hook_range * 0.95:
		_begin_windup(enemy, target)

func _begin_windup(enemy: Enemy, target: Player) -> void:
	state = State.WINDUP
	_t = 0.0
	enemy.velocity = Vector2.ZERO
	_aim_at(enemy, target)
	enemy.play_action(&"cast", true)
	var tele := _telegraph(enemy)
	if tele != null:
		tele.show_line(aim_dir, hook_range, 5.0, windup_time)

# --- WINDUP -----------------------------------------------------------------

func _windup(enemy: Enemy, target: Player, alive: bool, delta: float) -> void:
	_t += delta
	enemy.velocity = Vector2.ZERO
	if _t < aim_lock_at and alive:
		_aim_at(enemy, target)
		var tele := _telegraph(enemy)
		if tele != null:
			tele.set_direction(aim_dir)
	if _t >= windup_time:
		state = State.CAST
		_t = 0.0
		_traveled = 0.0
		_cast_origin = rod_tip(enemy)
		hook_pos = _cast_origin
		enemy.play_action(&"cast_hold", true)
		var tele := _telegraph(enemy)
		if tele != null:
			tele.clear()

# --- CAST -------------------------------------------------------------------

func _cast(enemy: Enemy, target: Player, alive: bool, delta: float) -> void:
	enemy.velocity = Vector2.ZERO
	var step := minf(hook_speed * delta, hook_range - _traveled)
	var from := hook_pos
	var motion := aim_dir * step
	# Terrain first: the hook stops where the line meets a blocker.
	var block_t := _terrain_block_t(enemy, from, motion)
	var reach := motion if block_t < 0.0 else motion * block_t
	if alive and not target.is_invulnerable() and not target.is_dashing():
		var p: Vector2 = target.global_position
		var closest := Geometry2D.get_closest_point_to_segment(p, from, from + reach)
		if closest.distance_to(p) <= hook_hit_radius:
			hook_pos = closest
			_begin_hooked(enemy, target)
			return
	hook_pos = from + reach
	_traveled += reach.length()
	if block_t >= 0.0:
		_end_cast(enemy, &"terrain")
	elif _traveled >= hook_range - 0.01:
		_end_cast(enemy, &"miss")

func _begin_hooked(enemy: Enemy, target: Player) -> void:
	state = State.HOOKED
	hooked_player = target
	last_result = &"hooked"
	_t = 0.0
	_tick_t = 0.0 # first bite lands at once
	_rally_t = 0.0
	_stall_t = 0.0
	enemy.play_action(&"reel", true)

# --- HOOKED -----------------------------------------------------------------

func _hooked(enemy: Enemy, delta: float) -> void:
	enemy.velocity = Vector2.ZERO
	var p := hooked_player
	if p == null or not is_instance_valid(p) or p.hp <= 0:
		_end_cast(enemy, &"dead")
		return
	if p.is_dashing():
		_end_cast(enemy, &"dash")
		return
	_t += delta
	var to: Vector2 = enemy.global_position - p.global_position
	var d := to.length()
	if d <= reel_stop:
		_end_cast(enemy, &"reeled")
		return
	if not _line_clear(enemy, enemy.global_position, p.global_position):
		_end_cast(enemy, &"blocked")
		return
	if _t >= hook_max_time:
		_end_cast(enemy, &"timeout")
		return
	_face(enemy, -to)
	var want := minf(reel_speed * delta, d - reel_stop)
	var moved: Vector2 = p.displace(to.normalized() * want)
	_stall_t = _stall_t + delta if moved.length() < want * 0.2 else 0.0
	hook_pos = p.global_position
	_tick_t -= delta
	if _tick_t <= 0.0:
		_tick_t = tick_interval
		enemy.deal_hit(p, tick_damage, OnHit.DELIVERY_MELEE)
	_rally_t -= delta
	if _rally_t <= 0.0:
		_rally_t = rally_interval
		rally_allies(enemy)
	if _stall_t >= stall_time:
		_end_cast(enemy, &"stalled")

## Calls every other live enemy within ally_radius to group up on the target.
## Returns how many answered (tests).
func rally_allies(enemy: Enemy) -> int:
	var n := 0
	for node in enemy.get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e == null or e == enemy or e.hp <= 0 or e.is_in_group("boss"):
			continue
		if e.global_position.distance_to(enemy.global_position) > ally_radius:
			continue
		e.rally(rally_time)
		n += 1
	return n

# --- RECOVER ----------------------------------------------------------------

func _end_cast(enemy: Enemy, why: StringName) -> void:
	last_result = why
	hooked_player = null
	state = State.RECOVER
	_t = 0.0
	_cooldown = cast_cooldown
	enemy.clear_action()
	enemy.play_action(&"retract")
	var tele := _telegraph(enemy)
	if tele != null:
		tele.clear()

func _recover(enemy: Enemy, delta: float) -> void:
	_t += delta
	enemy.velocity = Vector2.ZERO
	hook_pos = hook_pos.move_toward(rod_tip(enemy), retract_speed * delta)
	if _t >= recover_time and hook_pos.distance_to(rod_tip(enemy)) < 1.0:
		state = State.APPROACH

# --- helpers ----------------------------------------------------------------

## Face the target, then aim the line from the rod tip so it runs straight
## through the player's centre.
func _aim_at(enemy: Enemy, target: Player) -> void:
	_face(enemy, target.global_position - enemy.global_position)
	var d := target.global_position - rod_tip(enemy)
	if d.length_squared() > 0.0:
		aim_dir = d.normalized()
	var tele := _telegraph(enemy)
	if tele != null:
		tele.position = rod_tip(enemy) - enemy.global_position

func _face(enemy: Enemy, dir: Vector2) -> void:
	if enemy.sprite != null:
		enemy.sprite.face(dir.x)

func _telegraph(enemy: Enemy) -> BossTelegraph:
	return enemy.get_node_or_null("Telegraph") as BossTelegraph

## Fraction (0..1) of `from` -> `from + motion` where the hook first meets
## terrain that blocks projectiles (cells, or canopy circles), -1 for none.
## The cast's start cell is ignored, like Projectile, so a Fishy hugging a
## wall still casts out of it.
func _terrain_block_t(enemy: Enemy, from: Vector2, motion: Vector2) -> float:
	var map := enemy.terrain
	if map == null or not is_instance_valid(map):
		return -1.0
	var best := map.projectile_block_t(from, motion)
	var start_cell := map.world_to_cell(_cast_origin)
	var step := maxf(float(map.cell_size) * 0.25, 1.0)
	var n := maxi(ceili(motion.length() / step), 1)
	for i in range(1, n + 1):
		var f := float(i) / float(n)
		if best >= 0.0 and f >= best:
			break
		var cell := map.world_to_cell(from + motion * f)
		if cell == start_cell:
			continue
		if map.type_properties(map.tile_type_at_cell(cell))["blocks_projectiles"]:
			return f
	return best

## True when no projectile-blocking terrain sits between a and b.
func _line_clear(enemy: Enemy, a: Vector2, b: Vector2) -> bool:
	var map := enemy.terrain
	if map == null or not is_instance_valid(map):
		return true
	var saved := _cast_origin
	_cast_origin = a
	var t := _terrain_block_t(enemy, a, b - a)
	_cast_origin = saved
	return t < 0.0

func _sync_line(enemy: Enemy) -> void:
	var line := enemy.get_node_or_null("FishingLine") as FishingLine
	if line == null:
		return
	var out := state == State.CAST or state == State.HOOKED or (state == State.RECOVER and hook_pos.distance_to(rod_tip(enemy)) > 1.0)
	line.set_line(out, rod_tip(enemy), hook_pos, state == State.HOOKED)
