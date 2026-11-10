extends SceneTree
## Terrain art pass harness: the packed atlases, the type -> art mapping
## (seasons, palettes, fallbacks), the art layers a TerrainMap builds
## (floor fill incl. default GROUND, hashed variants, animated water,
## neighbour-based autotile masks, objects over their floor) and the tree
## destroy one-shot. Run: godot --headless --path . --script res://scripts/test_terrain_art.gd

const SUMMER := TerrainSeason.Season.SUMMER
const WINTER := TerrainSeason.Season.WINTER
const HIGHLANDS: TerrainPalette = preload("res://resources/terrain_palettes/highlands.tres")

var failures := 0

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[art] ", name, " -> PASS")
	else:
		failures += 1
		print("[art] ", name, " -> FAIL")

func _initialize() -> void:
	_atlas_legs()
	_mapping_legs()
	await _map_legs()
	print("[art] DONE failures=", failures)
	print("RESULT: ", "ALL PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(1 if failures > 0 else 0)

func _atlas_legs() -> void:
	var tiles := TerrainArt.TILES.get_image()
	var objs := TerrainArt.OBJECTS.get_image()
	_check(tiles.get_size() == Vector2i(16 * 64, 25 * 64), "tiles atlas is 16 x 25 cells of 64 px")
	_check(objs.get_size() == Vector2i(8 * 80, 6 * 80), "objects atlas is 8 x 6 cells of 80 px")
	# floors are opaque; summer grass reads green, water blue, snow pale
	var g := tiles.get_pixel(32, TerrainArt.row(&"grass_summer") * 64 + 32)
	_check(g.a == 1.0 and g.g > g.r and g.g > g.b, "summer grass samples green (%s)" % g)
	var w := tiles.get_pixel(32, TerrainArt.row(&"water") * 64 + 32)
	_check(w.b > w.r, "water samples blue (%s)" % w)
	var opaque := true
	for r in 25:
		for c in 16:
			if r < 11 and c >= 4:
				continue
			if tiles.get_pixel(c * 64 + 1, r * 64 + 1).a < 1.0 or tiles.get_pixel(c * 64 + 62, r * 64 + 62).a < 1.0:
				opaque = false
	_check(opaque, "every floor / autotile cell is opaque to its edges")
	# objects: transparent corners, no white fringe (keyed background)
	var clear_corners := true
	var fringe := 0
	for r in 6:
		for c in 8:
			if objs.get_pixel(c * 80, r * 80).a != 0.0:
				clear_corners = false
	for y in 3 * 80: # trees spring..autumn: no snow, so no legit white
		for x in 8 * 80:
			var p := objs.get_pixel(x, y)
			if p.a > 0.0 and p.r > 0.9 and p.g > 0.9 and p.b > 0.9:
				fringe += 1
			if p.a > 0.0 and p.a < 1.0:
				fringe += 1
	_check(clear_corners, "object cells have transparent corners")
	_check(fringe == 0, "no white-halo or half-alpha pixels on the green/autumn trees (%d)" % fringe)

func _mapping_legs() -> void:
	_check(TerrainArt.art_for(TerrainTypes.GROUND, SUMMER) == &"ground", "GROUND -> ground floor")
	_check(TerrainArt.art_for(TerrainTypes.GRASS, TerrainSeason.Season.AUTUMN) == &"grass_autumn", "GRASS follows the season")
	_check(TerrainArt.art_for(TerrainTypes.TREE, TerrainSeason.Season.SPRING) == &"tree_spring", "TREE follows the season")
	_check(TerrainArt.art_for(TerrainTypes.WATER, SUMMER) == &"water" and TerrainArt.art_for(TerrainTypes.WATER, WINTER) == &"", "winter water keeps the color fallback")
	_check(TerrainArt.art_for(TerrainTypes.BLOCK, SUMMER) == &"", "BLOCK keeps its #327 sprite (no tile art)")
	_check(TerrainArt.art_for(&"pine_forest", SUMMER, HIGHLANDS.tile(&"pine_forest")) == &"pine_forest", "palette tile art id is used")
	var plain := TerrainTile.new()
	plain.id = &"obstacle"
	_check(TerrainArt.art_for(TerrainTypes.OBSTACLE, SUMMER, plain) == &"", "palette restyle without art keeps its swatch")
	var dungeon_a: TerrainPalette = load("res://resources/terrain_palettes/dungeon_a.tres")
	var dungeon_c: TerrainPalette = load("res://resources/terrain_palettes/dungeon_c.tres")
	_check(dungeon_a.tile(&"obstacle").art == &"obstacle_slate" and dungeon_c.tile(&"obstacle").art == &"obstacle_purple", "dungeon palettes pick their wall color row")
	_check(TerrainArt.floor_under(&"tree_winter") == &"grass_winter" and TerrainArt.floor_under(&"pine_forest") == &"meadow", "objects stand on their floor")
	_check(TerrainArt.variant(Vector2i(3, 4), 1) == TerrainArt.variant(Vector2i(3, 4), 1), "variant pick is deterministic")
	var seen := {}
	for x in 12:
		seen[TerrainArt.variant(Vector2i(x, 0), 1)] = true
	_check(seen.size() == 4, "variant pick uses all 4 variants")

func _map_legs() -> void:
	var m := TerrainMap.new()
	root.add_child(m)
	await process_frame
	# a 7x5 OBSTACLE ring around grass with a tree and water inside
	var cells := {}
	for y in 5:
		for x in 7:
			var edge := x == 0 or y == 0 or x == 6 or y == 4
			cells[Vector2i(x, y)] = TerrainTypes.OBSTACLE if edge else TerrainTypes.GRASS
	cells[Vector2i(2, 2)] = TerrainTypes.TREE
	cells[Vector2i(4, 2)] = TerrainTypes.WATER
	cells.erase(Vector2i(3, 1)) # default GROUND inside the bounds
	m.set_cells(cells)
	var wall_row := TerrainArt.row(&"obstacle_brown")
	_check(m.art_bounds() == Rect2i(0, 0, 7, 5), "art bounds = the assigned cells' box")
	_check(m.debug_art_coords("floor", Vector2i(3, 1)).y == TerrainArt.row(&"ground"), "unset GROUND inside the bounds gets a ground floor")
	_check(m.debug_art_coords("floor", Vector2i(9, 9)) == Vector2i(-1, -1), "nothing is drawn outside the bounds")
	_check(m.debug_art_coords("floor", Vector2i(1, 1)).y == TerrainArt.row(&"grass_summer"), "GRASS draws summer grass")
	_check(m.debug_art_coords("floor", Vector2i(4, 2)) == Vector2i(0, TerrainArt.row(&"water")), "WATER uses the animated tile")
	var src := TerrainArt.tile_set().get_source(TerrainArt.TILES_SOURCE) as TileSetAtlasSource
	_check(src.get_tile_animation_frames_count(Vector2i(0, TerrainArt.row(&"water"))) == 4, "water tile animates 4 frames")
	_check(m.debug_art_coords("objects", Vector2i(2, 2)).y == TerrainArt.row(&"tree_summer") and m.debug_art_coords("floor", Vector2i(2, 2)).y == TerrainArt.row(&"grass_summer"), "TREE: tree object over grass floor")
	# autotile masks: off-bounds neighbours connect, inner sides exposed
	var top := m.debug_art_coords("walls", Vector2i(3, 0))
	_check(top.x == TerrainArt.S and (top.y == wall_row or top.y == wall_row + 1), "top wall: only its south side exposed (%s)" % top)
	_check(m.debug_art_coords("walls", Vector2i(0, 2)).x == TerrainArt.E, "left wall: only its east side exposed")
	_check(m.debug_art_coords("walls", Vector2i(0, 0)).x == 0, "ring corner: interior piece")
	m.set_cell(Vector2i(3, 3), TerrainTypes.OBSTACLE)
	_check(m.debug_art_coords("walls", Vector2i(3, 3)).x == TerrainArt.N | TerrainArt.E | TerrainArt.W, "wall stub: three sides exposed")
	_check(m.debug_art_coords("walls", Vector2i(3, 4)).x == 0, "the ring cell under the stub connects to it")
	# season swaps grass and tree rows; winter water falls back to color
	m.season = WINTER
	_check(m.debug_art_coords("floor", Vector2i(1, 1)).y == TerrainArt.row(&"grass_winter") and m.debug_art_coords("objects", Vector2i(2, 2)).y == TerrainArt.row(&"tree_winter"), "winter swaps grass and tree art")
	_check(m.debug_art_coords("floor", Vector2i(4, 2)) == Vector2i(-1, -1) and m.debug_layer_cells(false).has(Vector2i(4, 2)), "winter water: no art, color swatch stays")
	m.season = SUMMER
	# destroy: tree breaks into grass with a destroy one-shot
	_check(m.destroy_cell(Vector2i(2, 2)) and m.debug_destroy_fx_count() == 1, "destroying a tree plays its destroy one-shot")
	_check(m.debug_art_coords("objects", Vector2i(2, 2)) == Vector2i(-1, -1), "the tree object is gone after the break")
	m.set_cell(Vector2i(5, 3), TerrainTypes.BLOCK)
	m.destroy_cell(Vector2i(5, 3))
	_check(m.debug_destroy_fx_count() == 1, "BLOCK destroy adds no tile fx (TerrainBlockVisuals owns it)")
	# art off / hidden map: nothing drawn
	m.art_enabled = false
	_check(m.debug_art_coords("floor", Vector2i(1, 1)) == Vector2i(-1, -1), "art_enabled off clears the art layers")
	m.art_enabled = true
	m.visible = false
	_check(m.debug_art_coords("floor", Vector2i(1, 1)) == Vector2i(-1, -1), "a hidden map (overworld collision grid) builds no art")
	m.queue_free()
	# highlands palette: pine over meadow, chasm/mountain autotiles, 32 px scaling
	var h := TerrainMap.new()
	h.cell_size = 32
	h.palette = HIGHLANDS
	root.add_child(h)
	await process_frame
	h.set_cells({Vector2i(0, 0): &"pine_forest", Vector2i(1, 0): &"chasm", Vector2i(2, 0): &"mountain", Vector2i(3, 0): &"cliff"})
	_check(h.debug_art_coords("objects", Vector2i(0, 0)).y == TerrainArt.row(&"pine_forest") and h.debug_art_coords("floor", Vector2i(0, 0)).y == TerrainArt.row(&"meadow"), "pine forest over meadow")
	var ch := h.debug_art_coords("walls", Vector2i(1, 0)).y
	_check(ch == TerrainArt.row(&"chasm") or ch == TerrainArt.row(&"chasm") + 1, "chasm draws its autotile")
	_check((h.get_node("ArtFloor") as Node2D).scale == Vector2(0.5, 0.5), "64 px art scales to a 32 px grid")
	h.queue_free()
