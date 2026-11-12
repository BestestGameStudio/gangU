class_name EnemyBehaviorIdleChase
extends EnemyBehavior
## #631 (Daniel, WhatsApp 2026-11-12): the red mustache man behavior, an
## explicit two-state machine in the wolf/bird/fishy style.
##
##   IDLE  - every idle_pick interval pick a random cover spot (next to a
##           blocking obstacle - a tree - or inside tall grass) within
##           wander_radius and stroll to it; rest on arrival until the next
##           pick. If no cover spot is found nearby, stand in place.
##   CHASE - enter when the player comes within chase_enter_range (about a
##           screen wide); pathfind to the player through the #391
##           TerrainPath seam and deal contact damage on the #99 contract.
##           Return to IDLE when the player gets past chase_exit_range
##           (hysteresis, so the boundary does not flicker).
##
## Per-enemy instance state (spot, timers, contact cooldown) lives here; the
## Enemy duplicates the prototype in _ready, so nothing is shared.
## Player-only targeting: this class does not join the
## EnemyBehaviorChaseContact summon-taunt seam (#209).

enum State { IDLE, CHASE, SEARCH, ALERT }

## Seconds between cover-spot picks while idling (random in the range).
@export var idle_pick_min: float = 3.0
@export var idle_pick_max: float = 6.0
## How far a wander target may be from the enemy.
@export var wander_radius: float = 600.0
## Enter CHASE when the player is closer than this (about a screen wide).
@export var chase_enter_range: float = 1280.0
## Leave CHASE when the player is farther than this.
@export var chase_exit_range: float = 1536.0
## Fraction of enemy.speed used while strolling to a cover spot.
@export var stroll_fraction: float = 0.45
## Random candidate points tried per pick.
@export var pick_attempts: int = 12
## Arrival tolerance at a picked spot.
@export var arrive_epsilon: float = 10.0
## Seconds spent searching around the last seen position.
@export var search_duration: float = 4.0
## Wander radius around the last seen position while searching.
@export var search_radius: float = 200.0
## #639 (Daniel, WhatsApp 2026-11-12: "in search mode if one red MM finds
## the player alert nearby MMs"): a red that enters CHASE on spotting the
## player alerts other red mustaches within this range (about a screen).
@export var alert_radius: float = 1280.0
## An alerted red heads for a point this far from the alert spot, on its own
## bearing from it, so converging reds arrive from different sides (flank).
@export var flank_ring: float = 160.0

var _travel_timer: float = 0.0
var _last_seen := Vector2.INF
var _search_timer: float = 0.0
var _chasing_last_seen: bool = false
var _lost_travel_timer: float = 0.0

var _alert_target := Vector2.INF
var _alert_travel_timer: float = 0.0
var _alert_handled: int = 0
static var _alert_seq: int = 0

var _state: int = State.IDLE
var _pick_timer: float = 0.0
var _spot := Vector2.INF
var _contact_timer: float = 0.0
var _terrain_path := TerrainPath.new()
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.randomize()

func physics_step(enemy: Enemy, player, delta: float) -> void:
	_contact_timer = maxf(0.0, _contact_timer - delta)
	match _state:
		State.IDLE:
			_idle_step(enemy, player, delta)
		State.CHASE:
			_chase_step(enemy, player, delta)
		State.SEARCH:
			_search_step(enemy, player, delta)
		State.ALERT:
			_alert_step(enemy, player, delta)

func _idle_step(enemy: Enemy, player, delta: float) -> void:
	if _player_nearby(enemy, player, chase_enter_range):
		_enter_chase(enemy, player)
		return
	if _spot != Vector2.INF:
		# Stroll to the picked spot; rest on arrival until the next pick.
		var to_spot: Vector2 = _spot - enemy.global_position
		if to_spot.length() <= arrive_epsilon:
			_spot = Vector2.INF
			enemy.velocity = Vector2.ZERO
			enemy.move_and_slide()
			return
		# Bounded travel: a spot can be walkable yet unreachable (water,
		# disconnected walls), and TerrainPath yields zero movement when no
		# route exists. Give up and repick instead of stalling until CHASE.
		_travel_timer -= delta
		if _travel_timer <= 0.0:
			_spot = Vector2.INF
			_pick_timer = _rng.randf_range(idle_pick_min, idle_pick_max)
			enemy.velocity = Vector2.ZERO
			enemy.move_and_slide()
			return
		var spd: float = enemy.speed * stroll_fraction
		var desired: Vector2 = to_spot.normalized() * spd
		enemy.velocity = _terrain_path.steer(enemy.terrain, enemy.global_position, enemy.velocity, desired, _spot, spd, delta, enemy.can_swim)
		enemy.move_and_slide()
		return
	enemy.velocity = Vector2.ZERO
	enemy.move_and_slide()
	_pick_timer -= delta
	if _pick_timer <= 0.0:
		_pick_timer = _rng.randf_range(idle_pick_min, idle_pick_max)
		var spot: Variant = _pick_cover_spot(enemy)
		if spot != null:
			_spot = spot
			# Travel budget: straight-line time at stroll speed, doubled,
			# plus a second of slack for detours.
			var spd: float = enemy.speed * stroll_fraction
			_travel_timer = enemy.global_position.distance_to(_spot) / maxf(spd, 1.0) * 2.0 + 1.0

func _chase_step(enemy: Enemy, player, delta: float) -> void:
	# #633 (Daniel): _resolve_target returns null for a live player hidden
	# from sight (#461 tall grass); recover it from the enemy so losing
	# sight runs the last-seen search below instead of dropping to IDLE.
	if (player == null or not is_instance_valid(player)) and enemy._player != null and is_instance_valid(enemy._player):
		player = enemy._player
	if player == null or not is_instance_valid(player) or player.hp <= 0:
		_state = State.IDLE
		_last_seen = Vector2.INF
		_chasing_last_seen = false
		enemy.velocity = Vector2.ZERO
		enemy.move_and_slide()
		return
	if not _player_nearby(enemy, player, chase_exit_range):
		_state = State.IDLE
		_last_seen = Vector2.INF
		_chasing_last_seen = false
		enemy.velocity = Vector2.ZERO
		enemy.move_and_slide()
		return
	if not enemy.sees(player):
		# #633 (Daniel): sight lost (tall grass) - chase to the last seen
		# position, then search there instead of giving up instantly.
		if _last_seen == Vector2.INF:
			_last_seen = player.global_position
		if enemy.global_position.distance_to(_last_seen) <= arrive_epsilon:
			_chasing_last_seen = false
			_state = State.SEARCH
			_search_timer = search_duration
			_spot = Vector2.INF
			enemy.velocity = Vector2.ZERO
			enemy.move_and_slide()
			return
		# Bounded travel (#634 review): the last seen point can be
		# unreachable (water for a non-swimmer, a blocked or disconnected
		# route) and TerrainPath yields zero movement when no route exists.
		# Give up and search where we stopped instead of stalling forever.
		var spd0: float = enemy.chase_speed()
		if not _chasing_last_seen:
			_chasing_last_seen = true
			_lost_travel_timer = enemy.global_position.distance_to(_last_seen) / maxf(spd0, 1.0) * 2.0 + 1.0
		_lost_travel_timer -= delta
		if _lost_travel_timer <= 0.0:
			_chasing_last_seen = false
			_state = State.SEARCH
			_search_timer = search_duration
			_spot = Vector2.INF
			_last_seen = enemy.global_position
			enemy.velocity = Vector2.ZERO
			enemy.move_and_slide()
			return
		var to_seen: Vector2 = _last_seen - enemy.global_position
		var want: Vector2 = to_seen.normalized() * spd0
		enemy.velocity = _terrain_path.steer(enemy.terrain, enemy.global_position, enemy.velocity, want, _last_seen, spd0, delta, enemy.can_swim)
		enemy.move_and_slide()
		return
	_chasing_last_seen = false
	_last_seen = player.global_position
	var to_player: Vector2 = player.global_position - enemy.global_position
	var spd: float = enemy.chase_speed()
	var chase: Vector2 = to_player.normalized() * spd if to_player.length() > 8.0 else Vector2.ZERO
	enemy.velocity = _terrain_path.steer(enemy.terrain, enemy.global_position, enemy.velocity, chase, player.global_position, spd, delta, enemy.can_swim)
	enemy.move_and_slide()
	if to_player.length() <= enemy.contact_range and _contact_timer <= 0.0:
		enemy.deal_hit(player, enemy.contact_damage, OnHit.DELIVERY_CONTACT)
		_contact_timer = enemy.contact_cooldown
		enemy.play_action(&"attack") # #177: visual swing only

func _search_step(enemy: Enemy, player, delta: float) -> void:
	# Regaining sight resumes the chase (and re-alerts nearby reds).
	if _player_nearby(enemy, player, chase_enter_range) and enemy.sees(player):
		_enter_chase(enemy, player)
		return
	_search_timer -= delta
	if _search_timer <= 0.0:
		_state = State.IDLE
		_spot = Vector2.INF
		_last_seen = Vector2.INF
		return
	# Short wander near the last seen position.
	if _spot == Vector2.INF:
		var p: Variant = _pick_walkable_near(enemy, _last_seen, search_radius)
		if p == null:
			enemy.velocity = Vector2.ZERO
			enemy.move_and_slide()
			return
		_spot = p
		var spd0: float = enemy.speed * stroll_fraction
		_travel_timer = enemy.global_position.distance_to(_spot) / maxf(spd0, 1.0) * 2.0 + 1.0
	var to_spot: Vector2 = _spot - enemy.global_position
	if to_spot.length() <= arrive_epsilon:
		_spot = Vector2.INF
		enemy.velocity = Vector2.ZERO
		enemy.move_and_slide()
		return
	_travel_timer -= delta
	if _travel_timer <= 0.0:
		_spot = Vector2.INF
		enemy.velocity = Vector2.ZERO
		enemy.move_and_slide()
		return
	var spd: float = enemy.speed * stroll_fraction
	var desired: Vector2 = to_spot.normalized() * spd
	enemy.velocity = _terrain_path.steer(enemy.terrain, enemy.global_position, enemy.velocity, desired, _spot, spd, delta, enemy.can_swim)
	enemy.move_and_slide()

## #639: an alerted red converges on the alert spot's flank ring at chase
## speed. Seeing the player switches straight to CHASE (and re-alerts);
## arriving or running out of travel budget drops to a local SEARCH, whose
## own expiry falls back to IDLE as usual.
func _alert_step(enemy: Enemy, player, delta: float) -> void:
	if _player_nearby(enemy, player, chase_enter_range) and enemy.sees(player):
		_enter_chase(enemy, player)
		return
	_alert_travel_timer -= delta
	var arrived := enemy.global_position.distance_to(_alert_target) <= arrive_epsilon
	if arrived or _alert_travel_timer <= 0.0:
		_last_seen = _alert_target if arrived else enemy.global_position
		_alert_target = Vector2.INF
		_state = State.SEARCH
		_search_timer = search_duration
		_spot = Vector2.INF
		enemy.velocity = Vector2.ZERO
		enemy.move_and_slide()
		return
	var spd: float = enemy.chase_speed()
	var want: Vector2 = (_alert_target - enemy.global_position).normalized() * spd
	enemy.velocity = _terrain_path.steer(enemy.terrain, enemy.global_position, enemy.velocity, want, _alert_target, spd, delta, enemy.can_swim)
	enemy.move_and_slide()

## Entering CHASE on a spotting alerts nearby red mustaches (#639). Each
## broadcast carries a sequence so a receiver acts once per alert; a red
## already chasing ignores it.
func _enter_chase(enemy: Enemy, player) -> void:
	_state = State.CHASE
	_spot = Vector2.INF
	_alert_target = Vector2.INF
	_last_seen = player.global_position
	_alert_seq += 1
	_broadcast_alert(enemy, _last_seen, _alert_seq)

func _broadcast_alert(enemy: Enemy, spot: Vector2, seq: int) -> void:
	for other in enemy.get_tree().get_nodes_in_group("enemies"):
		if other == enemy or not other is Enemy:
			continue
		if (other as Enemy).global_position.distance_to(enemy.global_position) > alert_radius:
			continue
		var b: EnemyBehavior = (other as Enemy)._behavior
		if b is EnemyBehaviorIdleChase:
			(b as EnemyBehaviorIdleChase)._receive_alert(other, spot, seq)

func _receive_alert(enemy: Enemy, spot: Vector2, seq: int) -> void:
	if seq <= _alert_handled or _state == State.CHASE:
		return
	_alert_handled = seq
	var bearing: Vector2 = enemy.global_position - spot
	if bearing.length() < 1.0:
		bearing = Vector2.from_angle(_rng.randf() * TAU)
	_alert_target = spot + bearing.normalized() * flank_ring
	var spd: float = enemy.chase_speed()
	# Travel budget (#634 pattern): straight-line time at chase speed,
	# doubled, plus slack - an unreachable flank point degrades to a local
	# search instead of stalling forever.
	_alert_travel_timer = enemy.global_position.distance_to(_alert_target) / maxf(spd, 1.0) * 2.0 + 1.0
	_state = State.ALERT
	_spot = Vector2.INF

func _pick_walkable_near(enemy: Enemy, center: Vector2, radius: float) -> Variant:
	for i in pick_attempts:
		var offset := Vector2(_rng.randf_range(-radius, radius), _rng.randf_range(-radius, radius))
		var p: Vector2 = center + offset
		if _walkable(enemy.terrain, p, enemy.can_swim):
			return p
	return null

func _player_nearby(enemy: Enemy, player, range: float) -> bool:
	return player != null and is_instance_valid(player) and player.hp > 0 \
		and enemy.global_position.distance_to(player.global_position) <= range

## A wander target: a walkable point near a blocking obstacle (tree) or
## inside tall grass, within wander_radius. Null when nothing qualifies.
func _pick_cover_spot(enemy: Enemy) -> Variant:
	var map: TerrainMap = enemy.terrain
	for i in pick_attempts:
		var offset := Vector2(_rng.randf_range(-wander_radius, wander_radius), _rng.randf_range(-wander_radius, wander_radius))
		var p: Vector2 = enemy.global_position + offset
		if not _walkable(map, p, enemy.can_swim):
			continue
		if _is_cover(map, p, enemy.can_swim):
			return p
	return null

## Cover means: inside tall grass (the #461 concealment seam), or standing
## next to a blocking, non-water obstacle cell (a tree/rock).
func _is_cover(map: TerrainMap, p: Vector2, can_swim: bool) -> bool:
	if map == null:
		return false
	if map.conceals_at(p): # tall grass
		return true
	var cell := map.world_to_cell(p)
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var c := cell + Vector2i(dx, dy)
			var t := map.tile_type_at_cell(c)
			if not map.is_walkable_type(t) and t != TerrainTypes.WATER:
				return true
	return false

func _walkable(map: TerrainMap, p: Vector2, can_swim: bool) -> bool:
	if map == null:
		return true
	if can_swim:
		return map.tile_type_at(p) != TerrainTypes.OBSTACLE
	return map.is_walkable_at(p)
