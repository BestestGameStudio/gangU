class_name OverworldBird
extends Node
## #478 (Daniel, 2026-11-09: "one bird day only" - the wolves' day
## counterpart): the overworld's bird driver, same idiom as WolfCaves
## (#474). While the DayNightClock reads DAY it keeps exactly ONE bird
## flying; at nightfall it orders the bird to leave (the behavior flies
## off and hands itself back here to despawn, like wolves into their
## cave). Mounting the overworld mid-day spawns the bird too.
##
## The clock is root-parked and keeps running in dungeons (#448), and the
## overworld (with this node and its bird) is freed on every area swap -
## so a player who leaves the overworld simply leaves the bird behind.
##
## Harnesses that mount a bare enemy_bird.tscn directly never load this
## driver; it exists only for production scene placement.

const BIRD_SCENE := preload("res://scenes/enemy_bird.tscn")
const BIRD_TABLE := preload("res://resources/rewards/demo_table.tres")

## Day window on the DayNightClock fraction: sunrise (0.25) to sunset
## (0.75), the quarter marks the clock documents (#448) - the exact
## complement of the wolves' night window (#474).
const DAY_START := 0.25
const DAY_END := 0.75

## player_path for the spawned bird, resolved against the BIRD (which is
## parented to the area): production Main/<Area>/<Bird> -> Main/Player.
@export var player_path: NodePath = NodePath("../../Player")
## Where the spawned bird goes; this node's parent (the area) by default.
@export var area_path: NodePath = NodePath("..")
## Optional terrain wiring for the open-space check; auto-detected from
## the area's "Terrain" child when unset (same source EnemySpawner uses).
var terrain: TerrainMap = null

var bird: Enemy = null
var _day := false
var _checked_initial := false
var _area: Node = null
var _rng := RandomNumberGenerator.new()

static func is_day(time_of_day: float) -> bool:
	return time_of_day >= DAY_START and time_of_day < DAY_END

func _ready() -> void:
	add_to_group(&"overworld_bird")
	_rng.randomize()
	_area = get_node_or_null(area_path)
	if terrain == null and _area != null:
		terrain = _area.get_node_or_null("Terrain") as TerrainMap
	DayNightClock.ensure(get_tree())

func _process(_delta: float) -> void:
	var clock := DayNightClock.find_clock(get_tree())
	if clock == null:
		return
	var day := is_day(clock.time_of_day)
	if not _checked_initial:
		_checked_initial = true
		_day = day
		if day:
			spawn_bird()
		return
	if day and not _day:
		spawn_bird() # sunrise
	elif _day and not day:
		order_leave() # nightfall
	_day = day

## Spawn the one bird, circling high near the player. No-op while a bird
## is already up ("one bird day only").
func spawn_bird() -> Enemy:
	if _area == null:
		return null
	if bird != null and is_instance_valid(bird) and bird.hp > 0:
		return bird
	var p := _player()
	if p == null:
		# Fixtures that mount the overworld without a player get no bird
		# (an Enemy without a target just idles and warns on _ready).
		return null
	var b: Enemy = BIRD_SCENE.instantiate()
	b.player_path = player_path
	b.terrain = terrain
	b.reward_table = BIRD_TABLE
	b.set_meta("bird_manager", self)
	_area.add_child(b)
	# Arrive already circling: start one orbit-radius out at full height.
	b.global_position = p.global_position + Vector2.from_angle(_rng.randf() * TAU) * EnemyBehaviorBird.CIRCLE_RADIUS
	b.died.connect(_on_bird_died.bind(b))
	bird = b
	return b

## Nightfall: tell the bird to fly off (a stunned bird cannot move; its
## behavior waits out the stun, then leaves).
func order_leave() -> void:
	if bird != null and is_instance_valid(bird):
		bird.set_meta("bird_leave", true)

## The bird finished its leave climb: despawn "into the sky".
func absorb_bird(b: Enemy) -> void:
	if b == bird:
		bird = null
	b.queue_free()

func alive() -> bool:
	return bird != null and is_instance_valid(bird) and bird.hp > 0

func _player() -> Player:
	# Production Main/<Area>/OverworldBird -> Main/Player (the production
	# Player is in no group, same wiring problem Enemy solves explicitly).
	var p := get_node_or_null(NodePath("../../Player")) as Player
	if p == null:
		p = get_tree().get_first_node_in_group("player") as Player
	return p

func _on_bird_died(b: Enemy) -> void:
	if b == bird:
		bird = null
