extends SceneTree
## #396 harness: every gated dungeon map (DungeonA-E) is a terrain map.
## Run: godot --headless --path . --script res://scripts/test396_dungeon_terrain.gd
##
## Legs:
##   (A) TerrainFixedLayout: ASCII rows -> cells (origin, default legend,
##       custom legend, unknown char = GROUND) and TerrainMap.fixed_layout
##       fills the store in _ready; an unknown tile id refuses the batch.
##   (B) per dungeon scene: a "Terrain" TerrainMap with a fixed layout and a
##       palette; the walkable region reachable from PlayerSpawn is enclosed
##       (finite, bounded by the wall ring) and holds every authored point:
##       spawns, SpawnData entries, WaveSpawns, DefenseCore, the main.gd boss
##       spawn and the default exit portal spot (576,120). The decorative
##       frame sits on the wall's inner edge.
##   (C) movement: a boss-style scripted move (Enemy.terrain_move_and_slide)
##       and a knockback both stop at the arena wall; with no terrain the same
##       move leaves the arena (negative control: the walls are terrain only).
##   (D) PRODUCTION (main.tscn): mounting each dungeon wires its TerrainMap to
##       the Player and the spawned mobs; C/D/B bosses get it too.

const DUNGEONS := [
	{"scene": "res://scenes/dungeon_a.tscn", "name": "DungeonA", "boss": Vector2(-1, -1)},
	{"scene": "res://scenes/dungeon_b.tscn", "name": "DungeonB", "boss": Vector2(576, 240)},
	{"scene": "res://scenes/dungeon_c.tscn", "name": "DungeonC", "boss": Vector2(576, 300)},
	{"scene": "res://scenes/dungeon_d.tscn", "name": "DungeonD", "boss": Vector2(576, 280)},
	{"scene": "res://scenes/dungeon_e.tscn", "name": "DungeonE", "boss": Vector2(-1, -1)},
]
const EXIT_PORTAL_DEFAULT := Vector2(576, 120)
## Flood-fill guard: a leak past the walls would run into this.
const MAX_FILL := 2000

var failures := 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("[396] ", label, " -> PASS")
	else:
		failures += 1
		print("[396] ", label, " -> FAIL")

func _physics(n: int) -> void:
	for i in n:
		await physics_frame

func _initialize() -> void:
	await _leg_layout()
	await _leg_scenes()
	await _leg_movement()
	await _leg_production()
	print("[396] DONE failures=", failures)
	print("RESULT: ALL PASS" if failures == 0 else "RESULT: FAIL")
	quit(failures)

# (A) -----------------------------------------------------------------------
func _leg_layout() -> void:
	var l := TerrainFixedLayout.new()
	l.origin = Vector2i(3, -1)
	l.rows = PackedStringArray(["#.T", "~?x", "z"])
	l.legend = {"z": "mud"}
	var cells := l.cells()
	_check(cells.size() == 4, "(A) only non-ground characters become cells (got %d)" % cells.size())
	_check(cells.get(Vector2i(3, -1)) == TerrainTypes.OBSTACLE, "(A) '#' = obstacle at the origin")
	_check(cells.get(Vector2i(5, -1)) == TerrainTypes.TREE, "(A) 'T' = tree, columns run right")
	_check(cells.get(Vector2i(3, 0)) == TerrainTypes.WATER, "(A) '~' = water, rows run down")
	_check(not cells.has(Vector2i(4, 0)) and not cells.has(Vector2i(5, 0)), "(A) unmapped characters are ground")
	_check(cells.get(Vector2i(3, 1)) == TerrainTypes.MUD, "(A) the custom legend maps 'z'")

	var map := TerrainMap.new()
	map.fixed_layout = l
	root.add_child(map)
	await process_frame
	_check(map.tile_type_at_cell(Vector2i(3, -1)) == TerrainTypes.OBSTACLE and not map.is_walkable_at_cell(Vector2i(3, -1)),
		"(A) TerrainMap.fixed_layout fills the store in _ready")
	_check(map.debug_layer_cells(false).has(Vector2i(3, -1)), "(A) the layout is drawn (obstacle layer)")
	map.queue_free()

	var bad := TerrainFixedLayout.new()
	bad.rows = PackedStringArray(["#q"])
	bad.legend = {"q": "no_such_tile"}
	var m2 := TerrainMap.new()
	_check(not bad.apply(m2) and m2.assigned_cells().is_empty(), "(A) an unknown tile id refuses the whole layout")
	m2.free()
	await process_frame

# (B) -----------------------------------------------------------------------
func _reachable(map: TerrainMap, from: Vector2i) -> Dictionary:
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty() and seen.size() <= MAX_FILL:
		var c: Vector2i = queue.pop_back()
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n := c + d
			if not seen.has(n) and map.is_walkable_at_cell(n):
				seen[n] = true
				queue.append(n)
	return seen

func _leg_scenes() -> void:
	for d in DUNGEONS:
		var area: Node2D = load(d["scene"]).instantiate()
		root.add_child(area)
		await process_frame
		var tag: String = d["name"]
		var map := area.get_node_or_null("Terrain") as TerrainMap
		_check(map != null, "(B) %s has a Terrain TerrainMap" % tag)
		if map == null:
			area.queue_free()
			continue
		_check(map.fixed_layout != null and map.palette != null, "(B) %s: hand-designed fixed layout + palette" % tag)
		_check(map.assigned_cells().size() > 30, "(B) %s: the layout is in the store (%d cells)" % [tag, map.assigned_cells().size()])
		var spawn := (area.get_node("PlayerSpawn") as Node2D).global_position
		var start := map.world_to_cell(spawn)
		_check(map.is_walkable_at_cell(start), "(B) %s: PlayerSpawn is on a walkable cell" % tag)
		var region := _reachable(map, start)
		_check(region.size() > 40 and region.size() <= MAX_FILL, "(B) %s: the arena is enclosed by terrain walls (%d cells)" % [tag, region.size()])
		var points: Array[Vector2] = [EXIT_PORTAL_DEFAULT]
		var sd := area.get_node_or_null("SpawnData") as AreaSpawnData
		if sd != null:
			for e in sd.entries:
				points.append(area.to_global(e["position"]))
		var waves := area.get_node_or_null("WaveSpawns")
		if waves != null:
			for m in waves.get_children():
				points.append((m as Node2D).global_position)
		var core := area.get_node_or_null("DefenseCore") as Node2D
		if core != null:
			points.append(core.global_position)
		if d["boss"] != Vector2(-1, -1):
			points.append(area.to_global(d["boss"]))
		if tag == "DungeonA":
			points.append(area.to_global(Vector2(900, 480))) # main.gd revive item
		var bad: Array[Vector2] = []
		for p in points:
			if not region.has(map.world_to_cell(p)):
				bad.append(p)
		_check(bad.is_empty(), "(B) %s: all %d authored points are walkable and reachable from spawn %s" % [tag, points.size(), str(bad)])
		# every authored point keeps a body-width clearance from the walls
		var tight: Array[Vector2] = []
		for p in points:
			for off: Vector2 in [Vector2(14, 0), Vector2(-14, 0), Vector2(0, 14), Vector2(0, -14)]:
				if not map.is_walkable_at(p + off):
					tight.append(p)
					break
		_check(tight.is_empty(), "(B) %s: authored points sit >= 14 px from any wall %s" % [tag, str(tight)])
		var frame := area.get_node_or_null("Background/ArenaFrameLeft") as ColorRect
		if frame != null:
			var inside := Vector2(frame.offset_right + 1.0, spawn.y)
			var wall := Vector2(frame.offset_left + 1.0, spawn.y)
			_check(map.is_walkable_at(inside) and not map.is_walkable_at(wall), "(B) %s: the frame line traces the wall's inner edge" % tag)
		area.queue_free()
		await process_frame

# (C) -----------------------------------------------------------------------
func _mover(map: TerrainMap, parent: Node, at: Vector2) -> Enemy:
	var e: Enemy = load("res://scenes/enemy.tscn").instantiate()
	e.terrain = map
	parent.add_child(e)
	e.global_position = at
	return e

func _leg_movement() -> void:
	var area: Node2D = load("res://scenes/dungeon_d.tscn").instantiate()
	root.add_child(area)
	await process_frame
	var map := area.get_node("Terrain") as TerrainMap
	var west_wall_x := 320.0 # DungeonD interior starts at cell column 5

	# scripted move (the boss path), physics off so only the harness drives it
	var e := _mover(map, area, Vector2(400, 380))
	e.set_physics_process(false)
	for i in 30:
		e.velocity = Vector2(-1200, 0)
		e.terrain_move_and_slide()
		await physics_frame
	_check(e.global_position.x >= west_wall_x and map.is_walkable_at(e.global_position),
		"(C) scripted charge stops at the arena wall (x=%.1f)" % e.global_position.x)
	_check(e.velocity == Vector2(-1200, 0), "(C) the behavior's own velocity is kept (no compounding)")
	# sliding: a diagonal charge into the wall keeps its vertical component
	var y0 := e.global_position.y
	for i in 10:
		e.velocity = Vector2(-600, 300)
		e.terrain_move_and_slide()
		await physics_frame
	_check(e.global_position.y > y0 + 20.0 and e.global_position.x >= west_wall_x, "(C) a diagonal charge slides along the wall")

	# negative control: the same move with no terrain walks straight out
	e.terrain = null
	for i in 30:
		e.velocity = Vector2(-1200, 0)
		e.terrain_move_and_slide()
		await physics_frame
	_check(e.global_position.x < 256.0, "(C) no terrain = plain move_and_slide, leaves the arena (x=%.1f)" % e.global_position.x)
	e.queue_free()

	# knockback (Water Ball shove) on a terrain grid is clamped too
	var k := _mover(map, area, Vector2(360, 380))
	await physics_frame
	k.knockback(Vector2(-2400, 0))
	await _physics(30)
	_check(k.global_position.x >= west_wall_x and map.is_walkable_at(k.global_position),
		"(C) a knockback cannot shove an enemy through the wall (x=%.1f)" % k.global_position.x)
	k.queue_free()
	area.queue_free()
	await process_frame

# (D) -----------------------------------------------------------------------
func _leg_production() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var p: Player = scene.get_node("Player")
	for d in DUNGEONS:
		scene._swap(load(d["scene"]).instantiate())
		await _physics(4)
		var area: Node = scene.current_area
		var tag: String = d["name"]
		var map := area.get_node_or_null("Terrain") as TerrainMap
		_check(area.name == tag and map != null and p.terrain == map, "(D) %s mounted: Player walks on its TerrainMap" % tag)
		var unwired := 0
		var count := 0
		for e in get_nodes_in_group(&"enemies"):
			if e is Enemy and area.is_ancestor_of(e):
				count += 1
				if (e as Enemy).terrain != map:
					unwired += 1
		_check(unwired == 0, "(D) %s: every spawned enemy (%d) moves on the area terrain" % [tag, count])
		if tag == "DungeonC" or tag == "DungeonD":
			var bosses := get_nodes_in_group(&"boss")
			_check(bosses.size() == 1 and (bosses[0] as Enemy).terrain == map, "(D) %s: the boss moves on the area terrain" % tag)
		if tag == "DungeonB":
			for e in get_nodes_in_group(&"enemies"):
				if area.is_ancestor_of(e):
					e.apply_damage(9999)
			await _physics(6)
			var bosses := get_nodes_in_group(&"boss")
			_check(bosses.size() == 1 and (bosses[0] as Enemy).terrain == map, "(D) DungeonB: the Warlord moves on the area terrain")
		# player walks into the west wall and stops there (mobs removed
		# silently first so nothing can kill the player mid-walk)
		for e in get_nodes_in_group(&"enemies"):
			if area.is_ancestor_of(e):
				e.queue_free()
		p.global_position = (area.get_node("PlayerSpawn") as Node2D).global_position
		var x0 := p.global_position.x
		Input.action_press(&"move_left")
		await _physics(100)
		Input.action_release(&"move_left")
		var west_edge := 192.0 if tag in ["DungeonA", "DungeonB", "DungeonE"] else 320.0
		_check(p.global_position.x < x0 - 100.0 and p.global_position.x >= west_edge and map.is_walkable_at(p.global_position),
			"(D) %s: walking west stops at the wall (x=%.1f)" % [tag, p.global_position.x])
	scene.queue_free()
	current_scene = null
	await process_frame
