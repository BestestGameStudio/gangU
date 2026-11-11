class_name EnemyBehaviorBarricader
extends EnemyBehaviorChaseContact
## #420: the barricade-deploying Moustache variant (scenes/enemy_barricader.tscn,
## its own bestiary entry). Daniel, 2026-11-09 (WhatsApp):
##   "Special Moustache men can deploy barricades as cover... These mustache
##    men will run to open space and deploy the cover if there are no viable
##    or good cover spots towards the player."
##   "yes it should be a variant and a separate entry in the bestiary."
##
## Everything else is the regular #406/#414/#443 cover machine inherited
## from EnemyBehaviorChaseContact (seek, dash, hold + rocks, charge). This
## layer only adds the "no cover -> make cover" branch:
##   1. While the cover machine has no cover (SEEK without a pick, or
##      ENGAGED at range) and the player is within DEPLOY_RANGE but not in
##      melee, scan every SCAN_INTERVAL for viable cover toward the player
##      (the cover machine's own candidate filter).
##   2. None: pick the nearest OPEN spot toward the player (walkable ground
##      with no blocking terrain or solid within OPEN_RADIUS, where the
##      barricade cell in front is walkable too) and RUN there (FAST_MULT,
##      the cover dash speed).
##   3. Arrive (or stall for STALL_TIME): place a Barricade BARRICADE_AHEAD
##      toward the player, rotated to face them, stand BUILD_TIME, then hand
##      back to the cover machine with an immediate rescan, so it holds
##      behind it - and throws
##      rocks over it (lobbed shots fly over cover-group bodies).
## One live barricade per deployer; DEPLOY_COOLDOWN after each placement.
## The barricade joins the "cover" group, so other cover-seekers can use it
## too (human-open on #420). All numbers are PLACEHOLDER tuning.
## Non-Player targets, FlowNav maze enemies and enemies without cover_seek
## never deploy (they keep the inherited behaviour exactly).

const BARRICADE_SCENE: PackedScene = preload("res://scenes/barricade.tscn")
const DEPLOY_RANGE: float = 420.0 ## only deploy when the player is this close (PLACEHOLDER)
const MIN_DEPLOY_DIST: float = 110.0 ## never stop to build in melee range (PLACEHOLDER)
const DEPLOY_COOLDOWN: float = 6.0 ## seconds between placements (PLACEHOLDER)
const SCAN_INTERVAL: float = 0.5 ## viable-cover rescan cadence while uncovered (PLACEHOLDER)
const BARRICADE_AHEAD: float = 40.0 ## barricade centre this far in front, toward the player (PLACEHOLDER)
const OPEN_RADIUS: float = 40.0 ## "open space": no blocking terrain / solids this close (PLACEHOLDER)
const SPOT_MIN: float = 48.0 ## open-spot search ring, from the mover (PLACEHOLDER)
const SPOT_MAX: float = 160.0
const SPOT_RINGS: int = 4
const SPOT_RAYS: int = 9 ## rays across the toward-player half-cone
const SPOT_CONE: float = PI / 3.0 ## +-60deg around the player direction (PLACEHOLDER)
const FAST_MULT: float = EnemyBehaviorCover.FAST_MULT
const ARRIVE_EPS: float = 10.0
const STALL_TIME: float = 1.0
const MAX_RUN_TIME: float = 3.0 ## give up running and build where it stands (PLACEHOLDER)
const BUILD_TIME: float = 0.4 ## stands still placing the barricade (PLACEHOLDER)

## #513: authored tuning; constants remain compatibility defaults.
@export var deploy_range: float = DEPLOY_RANGE
@export var min_deploy_dist: float = MIN_DEPLOY_DIST
@export var deploy_cooldown: float = DEPLOY_COOLDOWN
@export var scan_interval: float = SCAN_INTERVAL
@export var barricade_ahead: float = BARRICADE_AHEAD
@export var open_radius: float = OPEN_RADIUS
@export var spot_min: float = SPOT_MIN
@export var spot_max: float = SPOT_MAX
@export var spot_rings: int = SPOT_RINGS
@export var spot_rays: int = SPOT_RAYS
@export var spot_cone: float = SPOT_CONE
@export var fast_mult: float = FAST_MULT
@export var arrive_eps: float = ARRIVE_EPS
@export var stall_time: float = STALL_TIME
@export var max_run_time: float = MAX_RUN_TIME
@export var build_time: float = BUILD_TIME

var _deploy_cd: float = 0.0
var _scan_t: float = 0.0
var _running := false
var _spot := Vector2.ZERO
var _run_t := 0.0
var _stall_t := 0.0
var _build_t := 0.0
var _barricade: Barricade = null
var _run_path := TerrainPath.new()
## Barricades placed by this enemy (test/debug counter only).
var deployed: int = 0

func physics_step(enemy: Enemy, player, delta: float) -> void:
	_deploy_cd = maxf(0.0, _deploy_cd - delta)
	_scan_t = maxf(0.0, _scan_t - delta)
	if not _eligible(enemy, player):
		_running = false
		super.physics_step(enemy, player, delta)
		return
	if _build_t > 0.0:
		_build_t -= delta
		enemy.velocity = Vector2.ZERO
		EnemyBehaviorChaseContact._slide(enemy)
		if _build_t <= 0.0:
			_cover.seek_now() # take cover behind the fresh barricade
		return
	if _running:
		_run(enemy, player, delta)
		return
	if _scan_t <= 0.0 and _wants_barricade(enemy, player):
		_scan_t = scan_interval
		if not _cover.viable_cover_exists(enemy, player):
			_start_run(enemy, player)
			if _running:
				_run(enemy, player, delta)
				return
	super.physics_step(enemy, player, delta)

func _eligible(enemy: Enemy, player) -> bool:
	return enemy.cover_seek and enemy.nav == null and player is Player and is_instance_valid(player) and player.hp > 0

func _wants_barricade(enemy: Enemy, player: Player) -> bool:
	if _deploy_cd > 0.0 or (_barricade != null and is_instance_valid(_barricade)):
		return false
	if not _cover.is_uncovered():
		return false
	var d := enemy.global_position.distance_to(player.global_position)
	return d >= min_deploy_dist and d <= deploy_range

# --- run to open space ------------------------------------------------------

func _start_run(enemy: Enemy, player: Player) -> void:
	var spot: Variant = find_open_spot(enemy, player)
	if spot == null:
		_deploy_cd = scan_interval * 2.0 # nowhere to build: retry a little later
		return
	_spot = spot
	_running = true
	_run_t = 0.0
	_stall_t = 0.0

func _run(enemy: Enemy, player: Player, delta: float) -> void:
	_run_t += delta
	var to := _spot - enemy.global_position
	var arrived := to.length() <= arrive_eps
	if not arrived:
		var speed := enemy.speed * fast_mult
		enemy.velocity = _run_path.steer(enemy.terrain, enemy.global_position, enemy.velocity, to.normalized() * speed, _spot, speed, delta, enemy.can_swim)
		EnemyBehaviorChaseContact._slide(enemy)
		if enemy.velocity.length_squared() < 1.0:
			_stall_t += delta
		else:
			_stall_t = 0.0
	else:
		enemy.velocity = Vector2.ZERO
		EnemyBehaviorChaseContact._slide(enemy)
	if arrived or _stall_t >= stall_time or _run_t >= max_run_time:
		_running = false
		deploy(enemy, player.global_position)

## The nearest open spot toward the player within the search rings, or null.
## The mover's own position is tried first (it may already stand in the open).
func find_open_spot(enemy: Enemy, player: Player) -> Variant:
	var origin := enemy.global_position
	var to_p := player.global_position - origin
	if to_p.length_squared() < 1.0:
		return null
	var base := to_p.angle()
	if _is_open_spot(enemy, origin, player.global_position):
		return origin
	for r in spot_rings:
		var dist := lerpf(spot_min, spot_max, float(r) / float(maxi(spot_rings - 1, 1)))
		# Rays fan out from the player direction (centre first).
		for k in spot_rays:
			var side := 1.0 if k % 2 == 1 else -1.0
			var step := floorf((k + 1) * 0.5)
			var a := base + side * step * (spot_cone / (float(spot_rays - 1) * 0.5))
			var p := origin + Vector2.from_angle(a) * dist
			if p.distance_to(player.global_position) < min_deploy_dist:
				continue
			if _is_open_spot(enemy, p, player.global_position):
				return p
	return null

func _is_open_spot(enemy: Enemy, p: Vector2, target: Vector2) -> bool:
	var dir := (target - p).normalized()
	var wall := p + dir * barricade_ahead
	var map := enemy.terrain
	if map != null:
		if not _walkable(map, p, enemy.can_swim) or not _walkable(map, wall, false):
			return false
		for i in 8:
			var q := p + Vector2.from_angle(TAU * i / 8.0) * open_radius
			if not _walkable(map, q, enemy.can_swim):
				return false
		# The run itself must not cut through blocking terrain.
		if not _line_walkable(map, enemy.global_position, p, enemy.can_swim):
			return false
	for n in enemy.get_tree().get_nodes_in_group(&"cover"):
		var s := n as Node2D
		if s != null and is_instance_valid(s) and (s.global_position.distance_to(p) < open_radius or s.global_position.distance_to(wall) < open_radius):
			return false
	return true

static func _walkable(map: TerrainMap, pos: Vector2, can_swim: bool) -> bool:
	var props := map.properties_at(pos)
	return props.get("walkable", true) or (props.get("swimmable", false) and can_swim)

static func _line_walkable(map: TerrainMap, a: Vector2, b: Vector2, can_swim: bool) -> bool:
	var steps := int(ceil(a.distance_to(b) / (map.cell_size * 0.5))) + 1
	for i in steps + 1:
		if not _walkable(map, a.lerp(b, float(i) / steps), can_swim):
			return false
	return true

# --- deploy -----------------------------------------------------------------

## Places this enemy's barricade barricade_ahead toward `target`, facing it,
## and hands back to the cover machine. Returns the barricade (null when the
## enemy is not in an area).
func deploy(enemy: Enemy, target: Vector2) -> Barricade:
	_deploy_cd = deploy_cooldown
	var area: Node = enemy.get_parent()
	if area == null:
		return null
	var dir := target - enemy.global_position
	dir = dir.normalized() if dir.length_squared() > 1.0 else Vector2.RIGHT
	var b: Barricade = BARRICADE_SCENE.instantiate()
	b.deployer = enemy
	var world := enemy.global_position + dir * barricade_ahead
	var area2d := area as Node2D
	b.position = area2d.to_local(world) if area2d != null else world
	b.rotation = dir.angle() - (area2d.global_rotation if area2d != null else 0.0)
	# D14: never add to the tree synchronously from a physics step.
	area.call_deferred("add_child", b)
	_barricade = b
	deployed += 1
	enemy.velocity = Vector2.ZERO
	enemy.play_action(&"attack")
	# Stand still while building: the barricade joins the "cover" group only
	# once the deferred add lands, so the cover rescan waits for build_time.
	_build_t = build_time
	return b
