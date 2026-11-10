class_name WolfCave
extends Node2D
## #474 (Daniel, 2026-11-09): a wolf den in the overworld. DECOR ONLY -
## "Caves cannot be entered", "Decor": no gate, no Area2D, no interaction;
## characters simply walk past it. Caves sit near the edges of the
## overworld (placement: wolf_caves.gd).
##
## Day/night pack driver (Daniel: "Wolves spawn in at night", "Wolves only
## hunt at night and travel in packs", "Retreat into cave and despawn. If a
## player fights them they fight back and do not retreat", "6 wolves"):
## - when the DayNightClock crosses into night the cave spawns its pack
##   (six wolves) at its mouth; mounting the overworld at night spawns too.
## - when the clock crosses into day it orders the pack home: unengaged
##   wolves retreat and despawn into the cave; engaged wolves keep
##   fighting (the behavior owns that call) and retreat once the fight
##   ends.
## The clock is root-parked and keeps running in dungeons (#448), and the
## overworld (with this cave and its wolves) is freed on every area swap -
## so a player who leaves the overworld simply leaves the hunt.

## Pack size per cave (Daniel: "6 wolves").
const PACK_SIZE := 6
## Night window on the DayNightClock fraction: sunset (0.75) to sunrise
## (0.25), the quarter marks the clock documents.
const NIGHT_START := 0.75
const NIGHT_END := 0.25
## Seconds the pack-alert stays up after the last engaged wolf.
const ALERT_HOLD := 4.0

const WOLF_SCENE := preload("res://scenes/enemy_wolf.tscn")
const WOLF_TABLE := preload("res://resources/rewards/demo_table.tres")

## player_path for spawned wolves, resolved against the WOLF (which is
## parented to the area): production Main/<Area>/<Wolf> -> Main/Player.
@export var player_path: NodePath = NodePath("../../Player")
## Where spawned wolves go; the container points this at the area.
@export var area_path: NodePath = NodePath("..")
## Optional terrain wiring for tree-aware movement; auto-detected from the
## area's "Terrain" child when unset (same source EnemySpawner uses).
var terrain: TerrainMap = null

var pack: Array[Enemy] = []
var _alert_t: float = 0.0
var _night := false
var _checked_initial := false
var _area: Node = null

static func is_night(time_of_day: float) -> bool:
	return time_of_day >= NIGHT_START or time_of_day < NIGHT_END

func _ready() -> void:
	add_to_group(&"wolf_caves")
	_area = get_node_or_null(area_path)
	if terrain == null and _area != null:
		terrain = _area.get_node_or_null("Terrain") as TerrainMap
	DayNightClock.ensure(get_tree())

func _process(delta: float) -> void:
	_alert_t = maxf(0.0, _alert_t - delta)
	var clock := DayNightClock.find_clock(get_tree())
	if clock == null:
		return
	var night := is_night(clock.time_of_day)
	if not _checked_initial:
		_checked_initial = true
		_night = night
		if night:
			spawn_pack()
		return
	if night and not _night:
		spawn_pack() # nightfall
	elif _night and not night:
		order_retreat() # daybreak
	_night = night

## Spawn wolves at the cave mouth up to PACK_SIZE live members.
func spawn_pack() -> Array[Enemy]:
	var out: Array[Enemy] = []
	if _area == null:
		return out
	_prune()
	# Nightfall restarts the hunt: survivors of a day fight still carry the
	# wolf_retreat flag order_retreat set at dawn, and the behavior obeys it
	# whenever it is not engaged - without this clear they would walk home
	# and despawn on the new night instead of hunting (#476 review, Mitra).
	for w in pack:
		(w.context as WolfContext).retreat = false
	var missing := PACK_SIZE - pack.size()
	var base_angle := randf() * TAU
	for i in missing:
		var idx := pack.size()
		var mouth := global_position + Vector2.from_angle(base_angle + TAU * i / maxi(missing, 1)) * 44.0
		var ctx := WolfContext.new()
		ctx.anchor = global_position
		ctx.has_anchor = true
		ctx.cave = self
		ctx.index = idx
		var opts := EnemySpawner.SpawnOptions.new()
		opts.wire_enemy = true
		opts.player_path = player_path
		opts.terrain = terrain
		opts.reward_table = WOLF_TABLE
		opts.context = ctx
		var wolf := EnemySpawner.spawn(WOLF_SCENE, Vector2.ZERO, opts) as Enemy
		_area.add_child(wolf)
		wolf.global_position = mouth
		wolf.died.connect(_on_wolf_died.bind(wolf))
		pack.append(wolf)
		out.append(wolf)
	return out

## Daybreak: tell every live wolf to go home (engaged wolves refuse in
## their behavior until the fight ends).
func order_retreat() -> void:
	_prune()
	for w in pack:
		(w.context as WolfContext).retreat = true

## A wolf reached the mouth on retreat: despawn "into the cave".
func absorb_wolf(wolf: Enemy) -> void:
	pack.erase(wolf)
	wolf.queue_free()

## Pack hunt: true while any packmate is (or was just) in combat.
func pack_alert_active() -> bool:
	return _alert_t > 0.0

## Wolves report combat here (called by the behavior through its meta).
func notify_engaged(_wolf: Enemy) -> void:
	_alert_t = ALERT_HOLD

func alive_count() -> int:
	_prune()
	return pack.size()

func _prune() -> void:
	pack = pack.filter(func(w: Enemy) -> bool: return is_instance_valid(w) and w.hp > 0)

func _on_wolf_died(wolf: Enemy) -> void:
	pack.erase(wolf)
