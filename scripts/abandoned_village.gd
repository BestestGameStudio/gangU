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
		ambush.entries.append({"position": Vector2.from_angle(angle) * 320.0,
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
	# Faded foundations and broken roofs, open to walk through. Ruins are
	# deliberately cosmetic: only the surrounding trees block movement.
	draw_circle(Vector2.ZERO, CLEAR_RADIUS, Color(0.27, 0.29, 0.22, 0.6))
	# Reuse the terrain atlas for a worn, textured single road.
	for x in range(-9, 9):
		for y in range(-1, 1):
			var cell := Vector2i(x, y)
			draw_texture_rect_region(TerrainArt.TILES, Rect2(Vector2(x * 64, y * 64), Vector2(64, 64)),
				Rect2(TerrainArt.variant(cell, 484) * 64, TerrainArt.row(&"ground") * 64, 64, 64), Color(0.8, 0.75, 0.62))
	for side in [-1, 1]:
		for column in [-1, 0, 1]:
			var at := Vector2(column * 170, side * 170)
			draw_rect(Rect2(at - Vector2(52, 38), Vector2(104, 76)), Color(0.22, 0.23, 0.20))
			draw_rect(Rect2(at - Vector2(52, 38), Vector2(104, 76)), Color(0.45, 0.43, 0.36), false, 7)
			draw_colored_polygon(PackedVector2Array([at + Vector2(-60, -35), at + Vector2(0, -68), at + Vector2(22, -34), at + Vector2(-10, -12)]), Color(0.28, 0.19, 0.14))
			for brick in 6:
				var start := at + Vector2(-50 + brick * 18, 36)
				draw_line(start, start + Vector2(0, -7), Color(0.25, 0.26, 0.23), 2)
			# Broken doorway and rubble make the buildings read as abandoned.
			draw_rect(Rect2(at + Vector2(-10, 30), Vector2(20, 12)), Color(0.22, 0.23, 0.20))
			for rubble in 4:
				draw_rect(Rect2(at + Vector2(35 + rubble * 8, 32 + (rubble % 2) * 8), Vector2(8, 6)), Color(0.44, 0.42, 0.35))
			draw_line(at + Vector2(-42, 12), at + Vector2(20, -20), Color(0.41, 0.29, 0.18), 6)
			draw_line(at + Vector2(20, 30), at + Vector2(43, 2), Color(0.41, 0.29, 0.18), 5)
	# An empty well in the square, with room on all sides.
	draw_circle(Vector2.ZERO, 28, Color(0.44, 0.43, 0.37))
	draw_circle(Vector2.ZERO, 19, Color(0.10, 0.12, 0.11))
