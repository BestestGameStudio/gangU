extends SceneTree
## #266: dungeon-defined terrain tiles (TerrainPalette / TerrainTile) and the
## WALKABLE / BLOCKING / FALLING movement categories. FALLING cells must
## stop the player for every kind of movement: WASD, dash, swimming,
## pushes / spell movement (Player.displace) and pathing (TerrainNav).

const DT := 1.0 / 60.0
const HIGHLANDS: TerrainPalette = preload("res://resources/terrain_palettes/highlands.tres")
const LAYOUT: TerrainLayout = preload("res://resources/terrain_layouts/enclosed_forked.tres")
const W := TerrainTypes.Movement.WALKABLE
const B := TerrainTypes.Movement.BLOCKING
const F := TerrainTypes.Movement.FALLING

var failures := 0
var _player_scene: PackedScene = preload("res://scenes/player.tscn")

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[266] ", name, " -> PASS")
	else:
		failures += 1
		print("[266] ", name, " -> FAIL")

func _initialize() -> void:
	_registry_legs()
	_palette_legs()
	await process_frame
	_map_legs()
	_generation_legs()
	_resolver_legs()
	await _player_legs()
	print("[266] ", "RESULT: ALL PASS" if failures == 0 else "RESULT: %d FAILED" % failures)
	quit(1 if failures > 0 else 0)

func _new_map(palette: TerrainPalette = HIGHLANDS) -> TerrainMap:
	var m := TerrainMap.new()
	m.cell_size = 64
	m.palette = palette
	root.add_child(m)
	return m

func _tile(id: StringName, movement: TerrainTypes.Movement) -> TerrainTile:
	var t := TerrainTile.new()
	t.id = id
	t.movement = movement
	return t

func _registry_legs() -> void:
	var expected := {
		TerrainTypes.GROUND: W, TerrainTypes.GRASS: W, TerrainTypes.SNOW: W, TerrainTypes.ICE: W, TerrainTypes.MUD: W,
		TerrainTypes.OBSTACLE: B, TerrainTypes.TREE: B, TerrainTypes.MOUNTAIN: B, TerrainTypes.WATER: B, TerrainTypes.BLOCK: B,
	}
	for type: StringName in TerrainTypes.ALL:
		var want: int = expected.get(type, -1)
		_check(TerrainTypes.movement(type) == want, "built-in %s is %s" % [type, TerrainTypes.MOVEMENT_NAMES.get(want, "?")])
		_check(TerrainTypes.is_walkable(type) == (TerrainTypes.movement(type) == W), "built-in %s: walkable follows its category" % type)
	_check(TerrainTypes.movement(&"lava") == B, "unknown type is BLOCKING")
	_check(TerrainTypes.Movement.size() == 3 and F != B and F != W, "FALLING is its own category")

func _palette_legs() -> void:
	_check(HIGHLANDS.validate().is_empty(), "highlands palette validates (%s)" % ", ".join(HIGHLANDS.validate()))
	_check(HIGHLANDS.custom_ids() == [&"meadow", &"pine_forest", &"scree", &"chasm", &"cliff"], "custom ids in palette order, built-in restyle excluded (%s)" % [HIGHLANDS.custom_ids()])
	var cases := {&"meadow": W, &"scree": W, &"pine_forest": B, &"mountain": B, &"chasm": F, &"cliff": F}
	for id: StringName in cases:
		var p := HIGHLANDS.properties(id)
		_check(p["movement"] == cases[id] and p["walkable"] == (cases[id] == W), "palette tile %s is %s" % [id, TerrainTypes.MOVEMENT_NAMES[cases[id]]])
	_check(HIGHLANDS.properties(&"meadow")["speed_multiplier"] == 1.0 and HIGHLANDS.properties(&"chasm")["speed_multiplier"] == 0.0, "new walkable tile moves at full speed; new falling tile has none")
	_check(HIGHLANDS.properties(TerrainTypes.ICE)["friction"] == TerrainTypes.friction(TerrainTypes.ICE), "type the palette does not list keeps built-in properties")
	_check(HIGHLANDS.biomes() == [[&"meadow", &"pine_forest"], [&"scree", &"chasm"]] and HIGHLANDS.border() == &"mountain", "palette drives generator biomes and border")

	var restyle := TerrainPalette.new()
	var tree_pit := _tile(TerrainTypes.TREE, F)
	var water_pit := _tile(TerrainTypes.WATER, F)
	restyle.tiles = [tree_pit, water_pit]
	_check(restyle.properties(TerrainTypes.TREE)["destroyable"] == true and restyle.properties(TerrainTypes.TREE)["movement"] == F, "restyled built-in keeps its other properties, takes the new category")
	_check(restyle.properties(TerrainTypes.WATER)["swimmable"] == false, "a FALLING tile is never swimmable")

	var bad := TerrainPalette.new()
	bad.tiles = [_tile(&"pit", F), _tile(&"pit", W)]
	bad.open_tiles = [&"pit"]
	bad.feature_tiles = [&"nope"]
	bad.border_tile = TerrainTypes.GRASS
	var errors := " | ".join(bad.validate())
	_check(errors.contains("duplicate") and errors.contains("not walkable") and errors.contains("unknown feature") and errors.contains("border tile"), "invalid palette reports each problem (%s)" % errors)
	_check(bad.biomes() == TerrainGen.BIOMES and bad.border() == TerrainTypes.OBSTACLE, "invalid palette falls back to built-in biomes and border")

func _map_legs() -> void:
	var m := _new_map()
	_check(m.set_cell(Vector2i(2, 2), &"chasm") and m.tile_type_at_cell(Vector2i(2, 2)) == &"chasm", "map accepts a palette tile")
	_check(not m.set_cell(Vector2i(3, 3), &"lava"), "map still rejects unknown types")
	_check(m.movement_at_cell(Vector2i(2, 2)) == F and not m.is_walkable_at_cell(Vector2i(2, 2)), "map reports FALLING and not walkable for the chasm cell")
	_check(m.movement_at(m.cell_to_world(Vector2i(9, 9))) == W, "unset cell is walkable ground")
	m.set_cell(Vector2i(4, 2), &"meadow")
	_check(m.debug_layer_cells(true).has(Vector2i(4, 2)) and m.debug_layer_cells(false).has(Vector2i(2, 2)), "walkable tile drawn on Ground, falling tile on Obstacle")
	_check(_same(_drawn(m, &"chasm"), HIGHLANDS.tile(&"chasm").color), "atlas draws the palette's chasm color")
	_check(_same(_drawn(m, &"mountain"), HIGHLANDS.tile(&"mountain").color), "atlas draws the palette's mountain restyle")
	_check(_same(_drawn(m, TerrainTypes.SNOW), TerrainMap.TYPE_COLORS[TerrainTypes.SNOW]), "unlisted built-in keeps its base color")

	var tex_palette := TerrainPalette.new()
	var tex_tile := _tile(&"striped", W)
	var art := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	art.fill(Color(1, 0, 0, 1))
	art.fill_rect(Rect2i(0, 0, 4, 2), Color(0, 0, 1, 1))
	tex_tile.texture = ImageTexture.create_from_image(art)
	tex_palette.tiles = [tex_tile]
	m.palette = tex_palette
	var col := TerrainTypes.ALL.size() * m.cell_size
	var img := _atlas_image(m)
	_check(_same(img.get_pixel(col + 5, 5), Color(0, 0, 1, 1)) and _same(img.get_pixel(col + 5, 60), Color(1, 0, 0, 1)), "tile texture is scaled into its atlas cell")
	_check(m.tile_type_at_cell(Vector2i(2, 2)) == &"chasm" and m.movement_at_cell(Vector2i(2, 2)) == B, "swapping palettes keeps cell data; a type the palette lost blocks")
	m.queue_free()

func _generation_legs() -> void:
	var allowed := {&"meadow": true, &"pine_forest": true, &"scree": true, &"chasm": true, &"cliff": true, &"mountain": true}
	var counts := {}
	var all_reachable := true
	var only_palette := true
	var border_ok := true
	for map_seed in range(1, 13):
		var m := _new_map()
		var result := TerrainGen.generate(m, map_seed, TerrainGen.DEFAULT_SIZE, LAYOUT)
		for y in TerrainGen.DEFAULT_SIZE.y:
			for x in TerrainGen.DEFAULT_SIZE.x:
				var t := m.tile_type_at_cell(Vector2i(x, y))
				counts[t] = counts.get(t, 0) + 1
				if not allowed.has(t):
					only_palette = false
				if (x == 0 or y == 0) and t != &"mountain":
					border_ok = false
		all_reachable = all_reachable and TerrainNav.reachable_from_cell(m, result["spawn"]).has(result["exit"])
		m.free()
	_check(only_palette, "palette maps use only palette tiles (%s)" % [counts])
	_check(border_ok, "palette border tile rings the map")
	_check(counts.get(&"chasm", 0) > 0 and counts.get(&"pine_forest", 0) > 0 and counts.get(&"meadow", 0) > 0 and counts.get(&"scree", 0) > 0, "both biomes and their falling / blocking features appear over seeds 1..12 (%s)" % [counts])

	# Three biomes split the noise range into three bands.
	var three := TerrainPalette.new()
	three.tiles = [_tile(&"a", W), _tile(&"b", W), _tile(&"c", W), _tile(&"pit", F)]
	three.open_tiles = [&"a", &"b", &"c"]
	three.feature_tiles = [&"pit", &"pit", &"pit"]
	var m3 := _new_map(three)
	TerrainGen.generate(m3, 5, TerrainGen.DEFAULT_SIZE)
	var seen := {}
	for c: Vector2i in m3.assigned_cells():
		seen[m3.tile_type_at_cell(c)] = true
	_check(three.validate().is_empty() and seen.has(&"b") and not seen.has(TerrainTypes.GRASS), "a palette may define more than two biomes (%s)" % [seen.keys()])
	m3.free()
	_check(all_reachable, "exit stays walkable-reachable from spawn on every seed (pits never cut the route)")

	var a := _new_map()
	var b := _new_map()
	TerrainGen.generate(a, 7, TerrainGen.DEFAULT_SIZE, LAYOUT)
	TerrainGen.generate(b, 7, TerrainGen.DEFAULT_SIZE, LAYOUT)
	var same := true
	for c: Vector2i in a.assigned_cells():
		same = same and a.tile_type_at_cell(c) == b.tile_type_at_cell(c)
	_check(same and a.assigned_cells().size() == b.assigned_cells().size(), "same seed + palette gives the same map")
	a.free()
	b.free()

	var plain := TerrainMap.new()
	TerrainGen.generate(plain, 3, TerrainGen.DEFAULT_SIZE, LAYOUT)
	var builtin_only := true
	for c: Vector2i in plain.assigned_cells():
		builtin_only = builtin_only and TerrainTypes.is_valid(plain.tile_type_at_cell(c))
	_check(builtin_only, "a map without a palette still generates built-in tiles")
	plain.free()

func _resolver_legs() -> void:
	var m := _new_map()
	var right := Vector2(320, 0)
	for pair: Array in [[2, &"chasm"], [4, &"cliff"], [6, &"pine_forest"]]:
		m.set_cell(Vector2i(1, pair[0]), pair[1])
		var pos := Vector2(60, pair[0] * 64 + 32)
		_check(TerrainMotion.resolve(m, pos, Vector2.ZERO, right, DT, true) == Vector2.ZERO, "%s blocks movement, even for a swimmer" % pair[1])
		_check(TerrainMotion.resolve(m, pos, Vector2.ZERO, Vector2(320, 320), DT, false) == Vector2(0, 320), "diagonal into %s slides along it" % pair[1])
		_check(not TerrainMotion.can_enter(m, pos + Vector2(64, 0), true), "can_enter refuses %s" % pair[1])
	m.set_cell(Vector2i(1, 8), &"meadow")
	_check(TerrainMotion.resolve(m, Vector2(60, 544), Vector2.ZERO, right, DT, false) == right, "meadow is entered at full speed")
	var start := Vector2(32, 160)
	var to := TerrainMotion.clamp_displacement(m, start, start + Vector2(300, 0), false)
	_check(to.x < 64.0 and m.world_to_cell(to) == Vector2i(0, 2), "a push toward a chasm stops before its edge (x=%.1f)" % to.x)
	var open_to := TerrainMotion.clamp_displacement(m, Vector2(32, 800), Vector2(332, 800), false)
	_check(open_to == Vector2(332, 800), "a push over open ground lands where asked")
	_check(TerrainMotion.clamp_displacement(null, start, Vector2(999, 9), false) == Vector2(999, 9), "null map: displacement unchanged")
	m.queue_free()

func _spawn_player(terrain: TerrainMap, pos: Vector2) -> Player:
	var p: Player = _player_scene.instantiate() as Player
	p.collision_layer = 0
	p.collision_mask = 0
	p.terrain = terrain
	root.add_child(p)
	p.global_position = pos
	return p

func _physics_frames(n: int) -> void:
	for i in n:
		await physics_frame

func _player_legs() -> void:
	var m := _new_map()
	for y in range(0, 12):
		m.set_cell(Vector2i(3, y), &"chasm")
	m.set_cell(Vector2i(3, 12), &"cliff")
	var walker := _spawn_player(m, Vector2(40, 32))
	var dasher := _spawn_player(m, Vector2(40, 288))
	var cliff_walker := _spawn_player(m, Vector2(40, 12 * 64 + 32))
	await _physics_frames(2)
	for p: Player in [walker, dasher, cliff_walker]:
		p.velocity = Vector2.ZERO
	walker.global_position = Vector2(40, 32)
	dasher.global_position = Vector2(40, 288)
	cliff_walker.global_position = Vector2(40, 12 * 64 + 32)
	_check(walker.can_swim, "test player can swim (falling must still stop it)")

	Input.action_press(&"move_right")
	_check(dasher.try_dash(Vector2.RIGHT), "dash starts toward the chasm")
	await _physics_frames(60)
	Input.action_release(&"move_right")
	_check(m.world_to_cell(walker.global_position).x == 2 and walker.velocity == Vector2.ZERO, "WASD: player halts at the chasm edge (x=%.1f)" % walker.global_position.x)
	_check(m.world_to_cell(dasher.global_position).x == 2, "dash: player halts at the chasm edge (x=%.1f)" % dasher.global_position.x)
	_check(m.world_to_cell(cliff_walker.global_position).x == 2, "WASD: player halts at the cliff edge (x=%.1f)" % cliff_walker.global_position.x)

	var pushed := _spawn_player(m, Vector2(40, 480))
	await _physics_frames(1)
	pushed.global_position = Vector2(40, 480)
	var applied := pushed.displace(Vector2(400, 0))
	_check(m.world_to_cell(pushed.global_position) == Vector2i(2, 7) and applied.x > 0.0 and applied.x < 152.0, "push / spell movement: displace stops before the chasm (moved %.1f)" % applied.x)
	var back := pushed.displace(Vector2(-60, 0))
	_check(is_equal_approx(back.x, -60.0), "displace away from the chasm is applied in full")
	var boxed := _new_map()
	var walls := {}
	for y in range(0, 5):
		for x in range(0, 7):
			if x == 0 or y == 0 or x == 6 or y == 4:
				walls[Vector2i(x, y)] = &"mountain"
			elif x == 3:
				walls[Vector2i(x, y)] = &"chasm"
	boxed.set_cells(walls)
	var reach := TerrainNav.reachable_from_cell(boxed, Vector2i(1, 2))
	_check(reach.has(Vector2i(2, 2)) and not reach.has(Vector2i(4, 2)), "pathing does not cross a chasm")
	boxed.queue_free()
	for p: Player in [walker, dasher, cliff_walker, pushed]:
		p.queue_free()
	m.queue_free()
	await process_frame

func _atlas_image(map: TerrainMap) -> Image:
	var layer := map.get_node("Ground") as TileMapLayer
	var src := layer.tile_set.get_source(0) as TileSetAtlasSource
	return src.texture.get_image()

func _drawn(map: TerrainMap, type: StringName) -> Color:
	var cs := map.cell_size
	var col := map._atlas_types().find(type)
	return _atlas_image(map).get_pixel(col * cs + cs / 2, cs / 2)

func _same(drawn: Color, want: Color) -> bool:
	return absf(drawn.r - want.r) <= 1.0 / 255.0 and absf(drawn.g - want.g) <= 1.0 / 255.0 \
		and absf(drawn.b - want.b) <= 1.0 / 255.0 and absf(drawn.a - want.a) <= 1.0 / 255.0
