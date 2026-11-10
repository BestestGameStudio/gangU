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
const HOUSE_HALF := Vector2(58, 54)
const WELL_HALF := Vector2(40, 46)
const PROPS: Texture2D = preload("res://assets/sprites/village_props.png")
const ENEMY := preload("res://scenes/enemy.tscn")
const LOOT := preload("res://resources/rewards/demo_table.tres")

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
		ambush.entries.append({"position": Vector2.from_angle(angle) * SPAWN_RADIUS,
			"enemy": ENEMY, "reward_table": LOOT})
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
	var host := get_parent().get_parent()
	return not host.has_method("location_event_fire_count") or host.location_event_fire_count(id()) == 0

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
	for side in [-1, 1]:
		for column in [-1, 0, 1]:
			var at := position + Vector2(column * 170, side * 170)
			rects.append(Rect2(at - HOUSE_HALF, HOUSE_HALF * 2.0))
	rects.append(Rect2(position - WELL_HALF, WELL_HALF * 2.0))
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
	if not is_instance_valid(_hero) or _hero.hp <= 0:
		_end(false)
		return
	var local := to_local(_hero.global_position)
	# Both road mouths; the outer-radius guard also handles forced movement
	# or teleport escapes instead of leaving an orphan encounter running.
	if (absf(local.x) > FOREST_RADIUS + 24.0 and absf(local.y) < ROAD_HALF_WIDTH + 20.0) or local.length() > FOREST_RADIUS + 100.0:
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
		status = "AMBUSH ESCAPED - NO CLEAR REWARD"
		for enemy in ambushers:
			if is_instance_valid(enemy) and enemy.hp > 0:
				enemy.queue_free()
	_caption.text = status

func _update_caption() -> void:
	status = "AMBUSH - %d LEFT | road exits open" % _remaining
	_caption.text = status

func _drop_reward() -> void:
	var drop: RewardDrop = preload("res://scenes/reward_drop.tscn").instantiate()
	var coins := RewardEntry.new()
	coins.kind = RewardEntry.Kind.CURRENCY
	coins.currency_amount = CLEAR_COINS
	drop.setup(coins)
	get_parent().add_child(drop)
	drop.global_position = global_position

func _draw() -> void:
	# Static atlas: three collapsed-house variants and one dry well.
	# Houses and the well are solid (#546); see plant_footprints().
	for x in range(-9, 9):
		for y in range(-1, 1):
			var cell := Vector2i(x, y)
			draw_texture_rect_region(TerrainArt.TILES, Rect2(Vector2(x * 64, y * 64), Vector2(64, 64)),
				Rect2(TerrainArt.variant(cell, 484) * 64, TerrainArt.row(&"ground") * 64, 64, 64), Color(0.8, 0.75, 0.62))
	for side in [-1, 1]:
		for column in [-1, 0, 1]:
			var at := Vector2(column * 170, side * 170)
			var variant := posmod(column + 1 + (1 if side > 0 else 0), 3)
			draw_texture_rect_region(PROPS, Rect2(at - Vector2(64, 64), Vector2(128, 128)),
				Rect2(variant * 128, 0, 128, 128))
	draw_texture_rect_region(PROPS, Rect2(-48, -48, 96, 96), Rect2(384, 0, 128, 128))
