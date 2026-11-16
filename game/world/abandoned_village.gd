class_name AbandonedVillage
extends LocationTrigger
## First production location event (#484). Layout and state belong to the
## area-owned trigger, not the shared AmbushEvent Resource.
## Defaults: one attempt per run, 100c clear bonus plus normal enemy drops.

const CENTER := Vector2(576, 1400)
const CLEAR_RADIUS := 350.0
const FOREST_RADIUS := 490.0
const ROAD_HALF_WIDTH := 72.0
const AMBUSH_COUNT := 30
const CLEAR_COINS := 100
## #546: ambushers appear just outside the outer tree ring (trees reach ~506).
const SPAWN_RADIUS := 540.0
## Doors are bottom-centre of each house sprite, facing south.
const DOOR_OFFSET := Vector2(0.0, 62.0 - 0.0)
const PATH_HALF_WIDTH := 20.0
const LANE_HALF_WIDTH := 22.0

## Lane centre line y at village-local x: a slow S-curve.
static func lane_y(x: float) -> float:
	return 26.0 * sin(x / 88.0) + 8.0 * sin(x / 41.0 + 1.0)

## Cobble lane (narrow, winding) plus short flagstone walks to every door.
static func path_segments() -> Array[PackedVector2Array]:
	var segs: Array[PackedVector2Array] = []
	var lane := PackedVector2Array()
	var x := -270.0
	while x <= 290.0:
		lane.append(Vector2(x, lane_y(x)))
		x += 15.0
	segs.append(lane)
	for column: int in [-1, 0, 1]:
		var cx := column * 170.0
		# North houses: short walk from the door straight down to the lane.
		var nd := house_foot(column, -1) + Vector2(0, 14)
		segs.append(PackedVector2Array([nd, Vector2(cx, lane_y(cx))]))
		# South houses: down the gap beside the house, then across to the door.
		var sd := house_foot(column, 1) + Vector2(0, 14)
		var gap := cx + 62.0
		segs.append(PackedVector2Array([Vector2(gap, lane_y(gap)), Vector2(gap, sd.y - 52.0)]))
	return segs

const HOUSE_HALF := Vector2(44, 30)
# #574: the footprint fits the visible well art, not its 96x96 draw rect.
# The art's opaque pixels span ~64.5x72 px (0.75 scale from the 128px atlas
# tile), centered ~4.5 px below the draw-rect center. Sizes are tuned for the
# 32px terrain grid: the marked OBSTACLE cells come out to x [-32, 32] and
# y [-56, 40] relative to the village center, the tightest cell span that
# still covers the art (was x [-64, 64] - double the art's width).
const WELL_HALF := Vector2(32, 30)
# 6.5 (was 4.5): keeps the footprint top below the north-centre door cell row
# so the door at the lane is reachable on the 32px grid.
const WELL_OFFSET := Vector2(0, 6.5)
const HOUSES: Array[Texture2D] = [
	preload("res://assets/sprites/village/village_house_a.png"),
	preload("res://assets/sprites/village/village_house_b.png"),
	preload("res://assets/sprites/village/village_house_c.png"),
]
const WELL_TEX: Texture2D = preload("res://assets/sprites/village/village_well.png")
const TOWER_TEX: Texture2D = preload("res://assets/sprites/village/village_bell_tower.png")
## Ground-contact points (village-local). Houses keep their old 170px grid.
const WELL_FOOT := Vector2(0, 36)
const TOWER_FOOT := Vector2(285, 24)
const TOWER_HALF := Vector2(20, 14)
const HOUSE_FOOT_DY := 50.0

static func house_foot(column: int, side: int) -> Vector2:
	# North row sits close to the lane; the south row keeps its old spot.
	return Vector2(column * 170.0, -62.0 if side < 0 else 170.0 + HOUSE_FOOT_DY)
const ENEMY := preload("res://game/enemies/enemy.tscn")
const LOOT := preload("res://data/rewards/demo_table.tres")

var ambushers: Array[Enemy] = []
var active := false
var status := "ABANDONED VILLAGE"
var _hero: Player
var _remaining := 0
var _rewarded := false
var _caption: Label

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = -1
	trigger_id = &"abandoned_village"
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 300.0
	shape.shape = circle
	add_child(shape)
	var ambush := AmbushEvent.new()
	ambush.display_name = "Village ambush"
	ambush.relative_to_trigger = true
	for i in AMBUSH_COUNT:
		var angle := TAU * float(i) / AMBUSH_COUNT
		ambush.entries.append(SpawnEntry.new(Vector2.from_angle(angle) * SPAWN_RADIUS, ENEMY, LOOT))
	ambush.ambush_started.connect(_begin)
	event = ambush
	_caption = Label.new()
	_caption.z_index = 8
	_caption.position = Vector2(-330, 290)
	_caption.size = Vector2(660, 36)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 22)
	_caption.text = status
	add_child(_caption)
	super._ready()

func should_fire(body: Node2D) -> bool:
	if not super.should_fire(body):
		return false
	var history := _run_history()
	return history == null or history.location_event_fire_count(id()) == 0

## #512: the run-scoped fire history lives on Main's AreaLoader (the node
## that receives `triggered`). Walk up to the first ancestor that either keeps
## the history itself or has an AreaLoader child. A bare village outside a
## Main (unit fixtures) has no history and fires once per instance.
func _run_history() -> AreaLoader:
	var n := get_parent()
	while n != null:
		if n is AreaLoader:
			return n
		var loader := n.get_node_or_null("AreaLoader") as AreaLoader
		if loader != null:
			return loader
		n = n.get_parent()
	return null

## Called by Ground before tree collision is planted. Only this village's
## footprint changes; the road and clearing are free of random decor.
func shape_decor(ground: OverworldGround) -> void:
	var kept: Array[Dictionary] = []
	for d in ground.decor:
		if (d["at"] as Vector2).distance_to(position) > FOREST_RADIUS + 60.0:
			kept.append(d)
	ground.decor = kept
	# Two loose rows with aligned walking gaps. The forest is cover, not a
	# solid wall: normal enemy pathfinding can approach through the trees.
	# The single visible road still crosses east-west.
	for ring in 2:
		var radius := 400.0 + ring * 80.0
		var count := 24
		for i in count:
			var angle := TAU * float(i) / count
			var offset := Vector2.from_angle(angle) * radius
			if absf(offset.y) < ROAD_HALF_WIDTH + 34.0:
				continue
			ground.decor.append({"kind": "tree", "at": position + offset, "r": 26.0})

## #546: whole-footprint solids for the six houses and the well, as
## OBSTACLE cells plus projectile-blocker circles (same mechanism as trees).
func footprints() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for side: int in [-1, 1]:
		for column: int in [-1, 0, 1]:
			var at := position + house_foot(column, side) - Vector2(0, 28)
			rects.append(Rect2(at - HOUSE_HALF, HOUSE_HALF * 2.0))
	rects.append(Rect2(position + WELL_OFFSET - WELL_HALF, WELL_HALF * 2.0))
	rects.append(Rect2(position + TOWER_FOOT - Vector2(0, TOWER_HALF.y) - TOWER_HALF, TOWER_HALF * 2.0))
	return rects

func plant_footprints(map: TerrainMap, cells: Dictionary, blockers: Array[Vector3]) -> void:
	for r in footprints():
		var lo := map.world_to_cell(r.position)
		var hi := map.world_to_cell(r.end)
		for cx in range(lo.x, hi.x + 1):
			for cy in range(lo.y, hi.y + 1):
				var cell := Vector2i(cx, cy)
				# Any cell whose square overlaps the footprint is solid, so
				# the whole footprint blocks (the patch may exceed the sprite
				# by up to one cell edge). Shots use the finer circles below.
				var half := Vector2(map.cell_size, map.cell_size) * 0.5
				if Rect2(map.cell_to_world(cell) - half, half * 2.0).intersects(r):
					cells[cell] = TerrainTypes.OBSTACLE
		var step := 36.0
		var x := r.position.x + 18.0
		while x < r.end.x + 18.0:
			var y := r.position.y + 18.0
			while y < r.end.y + 18.0:
				blockers.append(Vector3(minf(x, r.end.x - 4.0), minf(y, r.end.y - 4.0), 26.0))
				y += step
			x += step

func _begin(context: OverworldEventContext, enemies: Array[Enemy]) -> void:
	disarm()
	_hero = context.player
	ambushers = enemies
	_remaining = enemies.size()
	active = true
	for enemy in enemies:
		enemy.died.connect(_enemy_died, CONNECT_ONE_SHOT)
	_update_caption()
	if _remaining != AMBUSH_COUNT:
		_end(false) # incomplete spawn never earns the clear bonus

func _physics_process(_delta: float) -> void:
	if not active:
		return
	# #573: no escape mechanic - leaving the village never ends the ambush and
	# the mustache men never despawn; only the hero dying ends it early.
	if not is_instance_valid(_hero) or _hero.hp <= 0:
		_end(false)

func _enemy_died() -> void:
	if not active:
		return
	_remaining -= 1
	_update_caption()
	if _remaining == 0:
		_end(true)

func _end(cleared: bool) -> void:
	if not active:
		return
	active = false
	if cleared and not _rewarded:
		_rewarded = true
		status = "VILLAGE CLEARED - +%dc" % CLEAR_COINS
		_drop_reward.call_deferred()
	else:
		# Hero died (or the spawn was incomplete) - not an escape: there is no
		# escape. Survivors are cleaned up only because the run is over.
		status = "AMBUSH FAILED - NO CLEAR REWARD"
		for enemy in ambushers:
			if is_instance_valid(enemy) and enemy.hp > 0:
				enemy.queue_free()
	_caption.text = status

func _update_caption() -> void:
	status = "AMBUSH - %d LEFT" % _remaining
	_caption.text = status

func _drop_reward() -> void:
	var drop: RewardDrop = preload("res://game/economy/reward_drop.tscn").instantiate()
	var coins := RewardEntry.new()
	coins.kind = RewardEntry.Kind.CURRENCY
	coins.currency_amount = CLEAR_COINS
	drop.setup(coins)
	get_parent().add_child(drop)
	drop.global_position = global_position

## Props: [sprite name, village-local ground point]. Pure decoration (no
## collision yet). Layout follows Mitra's reference: cart in the lane,
## barrels and woodpiles by the houses, low walls behind the north plots, a
## fence in front of the south plots, a small walled graveyard by the tower.
static func prop_list() -> Array:
	var l: Array = []
	l.append(["cart", Vector2(-70, lane_y(-70) + 30)])
	for x in [-250, -194, 194, 250]:
		l.append(["wall_straight", Vector2(x, -140)])
	l.append(["wall_end", Vector2(-290, -140)])
	l.append(["wall_corner", Vector2(290, -140)])
	l.append(["wall_straight", Vector2(-138, -146)])
	l.append(["firewood_leanto", Vector2(-80, -64)])
	l.append(["barrel_a", Vector2(86, -60)])
	l.append(["barrel_b", Vector2(-248, -60)])
	l.append(["barrel_a", Vector2(250, -58)])
	l.append(["firewood_leanto", Vector2(-272, 224)])
	l.append(["barrel_b", Vector2(-236, 228)])
	l.append(["barrel_a", Vector2(224, 228)])
	for x in [-250, -194, -138]:
		l.append(["fence_straight", Vector2(x, 268)])
	l.append(["fence_leaning", Vector2(-24, 268)])
	l.append(["fence_straight", Vector2(32, 268)])
	l.append(["fence_gap", Vector2(150, 268)])
	l.append(["fence_straight", Vector2(206, 268)])
	# Graveyard beside the bell tower.
	l.append(["wall_straight", Vector2(326, 70)])
	l.append(["wall_end", Vector2(374, 70)])
	l.append(["grave_cross", Vector2(318, 106)])
	l.append(["grave_round", Vector2(346, 102)])
	l.append(["grave_slab", Vector2(372, 114)])
	l.append(["grave_cross", Vector2(330, 144)])
	l.append(["grave_slab", Vector2(358, 150)])
	# Flowers and dead sunflowers creeping along edges.
	for f in [["flower_purple", -300, 40], ["flower_white", -210, 44], ["flower_purple", -40, 48], ["flower_white", 120, 52],
			["flower_purple", 214, 46], ["flower_white", -120, -30], ["flower_purple", 60, -28], ["flower_white", 240, -26],
			["flower_purple", -200, 250], ["flower_white", 60, 250]]:
		l.append([f[0], Vector2(f[1], f[2])])
	l.append(["sunflower_dead", Vector2(-300, 70)])
	l.append(["sunflower_dead", Vector2(286, 232)])
	l.append(["sunflower_dead", Vector2(300, 190)])
	return l

static var _prop_tex: Dictionary = {}

static func _prop(name: String) -> Texture2D:
	if not _prop_tex.has(name):
		_prop_tex[name] = load("res://assets/sprites/village/prop_%s.png" % name) as Texture2D
	return _prop_tex[name]

func _draw() -> void:
	# Vine-covered sprites, bottom-centre anchored on the ground contact point,
	# drawn back to front so overlaps read correctly.
	# Houses and the well are solid (#546); see plant_footprints().
	var items: Array = []
	for side: int in [-1, 1]:
		for column: int in [-1, 0, 1]:
			var variant := posmod(column + 1 + (1 if side > 0 else 0), 3)
			items.append([house_foot(column, side).y, HOUSES[variant], house_foot(column, side), 1.0])
	items.append([WELL_FOOT.y, WELL_TEX, WELL_FOOT, 1.5])
	items.append([TOWER_FOOT.y, TOWER_TEX, TOWER_FOOT, 1.0])
	for pr in prop_list():
		var foot: Vector2 = pr[1]
		items.append([foot.y, _prop(pr[0]), foot, 1.0])
	items.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for it in items:
		_draw_prop(it[1], it[2], it[3])

func _draw_prop(tex: Texture2D, foot: Vector2, k: float = 1.0) -> void:
	var size := tex.get_size() * k
	draw_texture_rect(tex, Rect2(foot - Vector2(size.x * 0.5, size.y), size), false)
