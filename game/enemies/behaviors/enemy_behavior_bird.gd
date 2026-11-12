class_name EnemyBehaviorBird
extends EnemyBehavior
## #478 (Daniel, 2026-11-09): the overworld's day-time dive-bomber, the
## wolves' day counterpart. "Birds circle off screen, shadow is displayed
## on the ground. It telegraphs a radius on the ground directly on the
## player (short time to react) then dive bombs onto the ground. Player is
## stunned when hit (0.5s). Bird is stunned when it lands (1s). If they
## are hit while stunned in the landing period the stun is extended to
## 4s. After that it takes off again and will repeat the dive sequence at
## a random interval (3-10s)."
## Answers: "one bird day only", "moderate damage", "high HP, extended
## stun bird cant move, players can kill on ground", "will attack players
## when they're in open space".
##
## Per-enemy instance (the Enemy instantiates its own behavior from the
## definition slot, #99). The owning OverworldBird node drives day/night
## through the typed Enemy.context (BirdContext):
##   manager OverworldBird - bookkeeping + absorb callback
##   leave   bool          - nightfall: fly off and despawn
##
## Flight model: the Enemy body stays on the GROUND plane (its position is
## the shadow); altitude is purely visual (Sprite raised, shadow faded).
## While airborne (CIRCLE/TELEGRAPH/DIVE/TAKEOFF/LEAVE) the bird's
## CollisionShape2D is disabled - shots pass under it and it cannot be
## hit; it flies over trees/terrain (no terrain clamp). On landing the
## shape re-enables: the stun window is the punish window ("players can
## kill it on the ground").
##
## "Open space": the bird only starts a dive when the player is NOT under
## cover - cover = the terrain's low-cover test (a tree cell or a cell
## under an overworld-tree canopy circle, the #443 rule). With no terrain
## the player counts as open.

## --- Daniel's numbers ---------------------------------------------------
## Player stun on a dive hit ("Player is stunned when hit (0.5s)").
const PLAYER_STUN := 0.5
## Landing stun ("Bird is stunned when it lands (1s)").
const LAND_STUN := 1.0
## Hit while stunned: "the stun is extended to 4s" (from that hit).
const EXTENDED_STUN := 4.0
## Re-dive interval after takeoff ("random interval (3-10s)").
const REDIVE_MIN := 3.0
const REDIVE_MAX := 10.0

## --- Implementer defaults (unspecified; tuned for readability) ----------
## Telegraph: the locked ground ring shows this long before impact
## ("short time to react").
const TELEGRAPH_TIME := 0.7
## Radius of the telegraphed impact zone; the hit lands if the player is
## still inside at impact.
const DIVE_RADIUS := 64.0
## Dive descent time (shadow to ground).
const DIVE_TIME := 0.30
## Takeoff climb time.
const TAKEOFF_TIME := 0.6
## Circle: shadow orbit radius/speed around the player.
const CIRCLE_RADIUS := 210.0
const CIRCLE_RATE := 1.15
## First dive comes a little sooner than the 3-10s re-dive band so the
## bird announces itself quickly after sunrise.
const FIRST_DIVE_MIN := 1.5
const FIRST_DIVE_MAX := 3.0
## Visual altitude while circling (px the sprite rides above the ground).
## Larger than half the 648px viewport, so the bird itself is off screen
## while its shadow circles - "birds circle off screen, shadow is
## displayed on the ground".
const ALT_MAX := 480.0
## Leave (nightfall): climb to this before despawn.
const ALT_GONE := 760.0

enum State { CIRCLE, TELEGRAPH, DIVE, STUNNED, TAKEOFF, LEAVE }

var state: int = CIRCLE
var _timer: float = 0.0
var _redive_t: float = 0.0
var _angle: float = 0.0
var _altitude: float = ALT_MAX
var _locked: Vector2 = Vector2.ZERO
var _stunned_hp: int = -1
var _airborne: bool = false
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.randomize()
	_redive_t = _rng.randf_range(FIRST_DIVE_MIN, FIRST_DIVE_MAX)
	_angle = _rng.randf() * TAU

func physics_step(enemy: Enemy, player, delta: float) -> void:
	_timer = maxf(0.0, _timer - delta)
	var alive: bool = player != null and is_instance_valid(player) and player.hp > 0

	# Nightfall order: a bird that can move leaves; a stunned bird cannot
	# move ("extended stun bird cant move") - it leaves when the stun ends.
	if _leaving(enemy) and state != LEAVE and state != STUNNED:
		_clear_telegraph(enemy)
		state = LEAVE

	match state:
		CIRCLE:
			_step_circle(enemy, player, alive, delta)
		TELEGRAPH:
			_step_telegraph(enemy, delta)
		DIVE:
			_step_dive(enemy, player, alive, delta)
		STUNNED:
			_step_stunned(enemy, delta)
		TAKEOFF:
			_step_takeoff(enemy, delta)
		LEAVE:
			_step_leave(enemy, player, delta)

	_apply_altitude(enemy, delta)

func _step_circle(enemy: Enemy, player, alive: bool, delta: float) -> void:
	_redive_t -= delta
	_altitude = ALT_MAX
	_ensure_airborne(enemy, true)
	if alive:
		_angle += CIRCLE_RATE * delta
		var target: Vector2 = player.global_position + Vector2.from_angle(_angle) * CIRCLE_RADIUS
		var to := target - enemy.global_position
		enemy.velocity = to / maxf(delta, 0.0001)
		var vmax: float = enemy.speed * 4.0
		if enemy.velocity.length() > vmax:
			enemy.velocity = enemy.velocity.normalized() * vmax
	else:
		enemy.velocity = Vector2.ZERO
	enemy.move_and_slide() # airborne: flies over terrain, no clamp
	if alive and _redive_t <= 0.0 and _in_open_space(enemy, player):
		state = TELEGRAPH
		_timer = TELEGRAPH_TIME
		_locked = player.global_position
		enemy.velocity = Vector2.ZERO
		enemy.move_and_slide()
		var tele := _telegraph(enemy)
		if tele != null:
			tele.show_ring(DIVE_RADIUS, TELEGRAPH_TIME)
		if enemy.sprite != null:
			enemy.sprite.set_glow(true)

func _step_telegraph(enemy: Enemy, delta: float) -> void:
	# Hover above the locked point while the ring fills; the ring stays put
	# and a moving player can still run out of it.
	var target := _locked + Vector2(0, -CIRCLE_RADIUS * 0.35)
	var to := target - enemy.global_position
	enemy.velocity = to / maxf(delta, 0.0001)
	var vmax: float = enemy.speed * 4.0
	if enemy.velocity.length() > vmax:
		enemy.velocity = enemy.velocity.normalized() * vmax
	enemy.move_and_slide()
	_track_telegraph(enemy)
	if _timer <= 0.0:
		state = DIVE
		_timer = DIVE_TIME
		enemy.play_action(&"dive", true)
		if enemy.sprite != null:
			enemy.sprite.set_glow(false)

func _step_dive(enemy: Enemy, player, alive: bool, delta: float) -> void:
	var f := 1.0 - clampf(_timer / DIVE_TIME, 0.0, 1.0)
	_altitude = lerpf(ALT_MAX, 0.0, f)
	var to := _locked - enemy.global_position
	enemy.velocity = to / maxf(delta, 0.0001)
	enemy.move_and_slide()
	if _timer > 0.0:
		return
	# Impact.
	enemy.global_position = _locked
	_altitude = 0.0
	enemy.velocity = Vector2.ZERO
	enemy.move_and_slide()
	_clear_telegraph(enemy)
	_ensure_airborne(enemy, false)
	enemy.play_action(&"landed", true)
	if alive and player.global_position.distance_to(_locked) <= DIVE_RADIUS:
		enemy.deal_hit(player, enemy.contact_damage, OnHit.DELIVERY_CONTACT)
		if player.has_method(&"apply_stun"):
			player.apply_stun(PLAYER_STUN)
	state = STUNNED
	_timer = LAND_STUN
	_stunned_hp = enemy.hp

func _step_stunned(enemy: Enemy, delta: float) -> void:
	# "extended stun bird cant move" - no drift, no takeoff until it ends.
	enemy.velocity = Vector2.ZERO
	enemy.move_and_slide()
	if enemy.hp < _stunned_hp:
		# Hit during the landing stun: "the stun is extended to 4s" (each
		# hit re-extends from that hit).
		_timer = EXTENDED_STUN
		_stunned_hp = enemy.hp
	if _timer <= 0.0:
		if _leaving(enemy):
			state = LEAVE
			enemy.clear_action()
			return
		state = TAKEOFF
		_timer = TAKEOFF_TIME
		enemy.clear_action()
		enemy.play_action(&"walk")

func _step_takeoff(enemy: Enemy, delta: float) -> void:
	_ensure_airborne(enemy, true)
	var f := 1.0 - clampf(_timer / TAKEOFF_TIME, 0.0, 1.0)
	_altitude = lerpf(0.0, ALT_MAX, f)
	enemy.velocity = Vector2.ZERO
	enemy.move_and_slide()
	if _timer <= 0.0:
		state = CIRCLE
		_altitude = ALT_MAX
		_redive_t = _rng.randf_range(REDIVE_MIN, REDIVE_MAX)

func _step_leave(enemy: Enemy, player, delta: float) -> void:
	# Climb past circling altitude and drift away from the player, then
	# hand back to the manager (despawn, like wolves into their cave).
	_altitude = minf(_altitude + ALT_MAX * 1.6 * delta, ALT_GONE)
	var away := Vector2.from_angle(_angle)
	if player != null and is_instance_valid(player):
		var from_player: Vector2 = enemy.global_position - player.global_position
		if from_player.length() > 1.0:
			away = from_player.normalized()
	enemy.velocity = away * enemy.speed * 3.0
	enemy.move_and_slide()
	_ensure_airborne(enemy, true)
	if _altitude >= ALT_GONE:
		var mgr := _manager(enemy)
		if mgr != null and mgr.has_method("absorb_bird"):
			mgr.absorb_bird(enemy)
		else:
			enemy.queue_free()

## --- helpers -------------------------------------------------------------

## Raise/lower the sprite and fade the ground shadow with altitude. Purely
## visual: the body (and its collision, when enabled) stays on the ground.
func _apply_altitude(enemy: Enemy, _delta: float) -> void:
	if enemy.sprite != null:
		enemy.sprite.position = Vector2(0, -_altitude * 0.9)
		var s := 1.0 + _altitude / ALT_MAX * 0.35
		enemy.sprite.scale = Vector2(s, s)
	var shadow := enemy.get_node_or_null("Shadow") as Node2D
	if shadow != null:
		var f: float = clampf(1.0 - _altitude / ALT_MAX, 0.25, 1.0)
		shadow.modulate = Color(1, 1, 1, 0.32 * f + 0.18)
		shadow.scale = Vector2(f, f)

## Airborne = collision shape off (shots pass under, cannot be hit).
## Applied only on transitions (the scene starts grounded/enabled, and
## CIRCLE's first step lifts it).
func _ensure_airborne(enemy: Enemy, airborne: bool) -> void:
	if _airborne == airborne:
		return
	_airborne = airborne
	var shape := enemy.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape != null:
		shape.set_deferred("disabled", airborne)

func _telegraph(enemy: Enemy) -> BossTelegraph:
	return enemy.get_node_or_null("Telegraph") as BossTelegraph

func _track_telegraph(enemy: Enemy) -> void:
	var tele := _telegraph(enemy)
	if tele != null:
		tele.position = enemy.to_local(_locked)

func _clear_telegraph(enemy: Enemy) -> void:
	var tele := _telegraph(enemy)
	if tele != null:
		tele.clear()
	if enemy.sprite != null:
		enemy.sprite.set_glow(false)

## "Will attack players when they're in open space": under a tree canopy
## (the #443 low-cover rule) the bird holds its circle instead of diving.
func _in_open_space(enemy: Enemy, player) -> bool:
	if enemy.terrain == null:
		return true
	return not enemy.terrain.is_low_cover_cell(enemy.terrain.world_to_cell(player.global_position))

func _leaving(enemy: Enemy) -> bool:
	var c := enemy.context as BirdContext
	return c != null and c.leave

func _manager(enemy: Enemy) -> Object:
	var c := enemy.context as BirdContext
	if c == null:
		return null
	return c.manager if c.manager != null and is_instance_valid(c.manager) else null

## Harness introspection: state name for test assertions.
func state_name() -> String:
	return ["CIRCLE", "TELEGRAPH", "DIVE", "STUNNED", "TAKEOFF", "LEAVE"][state]

## Harness introspection: current visual altitude.
func altitude() -> float:
	return _altitude
