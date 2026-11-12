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

enum State { IDLE, CHASE, SEARCH }

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

var _travel_timer: float = 0.0
var _last_seen := Vector2.INF
var _search_timer: float = 0.0

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

func _idle_step(enemy: Enemy, player, delta: float) -> void:
	if _player_nearby(enemy, player, chase_enter_range):
		_state = State.CHASE
		_spot = Vector2.INF
		_last_seen = player.global_position
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
	if player == null or not is_instance_valid(player) or player.hp <= 0:
		_state = State.IDLE
		enemy.velocity = Vector2.ZERO
		enemy.move_and_slide()
		return
	if not _player_nearby(enemy, player, chase_exit_range):
		_state = State.IDLE
		enemy.velocity = Vector2.ZERO
		enemy.move_and_slide()
		return
	if not enemy.sees(player):
		# #633 (Daniel): sight lost (tall grass) - chase to the last seen
		# position, then search there instead of giving up instantly.
		if _last_seen == Vector2.INF:
			_last_seen = player.global_position
		if enemy.global_position.distance_to(_last_seen) <= arrive_epsilon:
			_state = State.SEARCH
			_search_timer = search_duration
			_spot = Vector2.INF
			enemy.velocity = Vector2.ZERO
			enemy.move_and_slide()
			return
		var spd0: float = enemy.chase_speed()
		var to_seen: Vector2 = _last_seen - enemy.global_position
		var want: Vector2 = to_seen.normalized() * spd0
		enemy.velocity = _terrain_path.steer(enemy.terrain, enemy.global_position, enemy.velocity, want, _last_seen, spd0, delta, enemy.can_swim)
		enemy.move_and_slide()
		return
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
	# Regaining sight resumes the chase.
	if _player_nearby(enemy, player, chase_enter_range) and enemy.sees(player):
		_state = State.CHASE
		_spot = Vector2.INF
		_last_seen = player.global_position
		return
	_search_timer -= delta
	if _search_timer <= 0.0:
		_state = State.IDLE
		_spot = Vector2.INF
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
