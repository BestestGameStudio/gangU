extends SceneTree
## TerrainMap repaints only the changed cells (and their autotile
## neighbours) on set_cell / set_cells / clear_cell / destroy / interact.
## After every one of 400 seeded writes on a walled map with art visible,
## every color and art layer cell (source, atlas coords, alternative) must
## equal what a full _rebuild_presentation() draws.
## Run: godot --headless --path . -s scripts/test_terrain_repaint.gd

var failures := 0

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[repaint] ", name, " -> PASS")
	else:
		failures += 1
		print("[repaint] ", name, " -> FAIL")

func _initialize() -> void:
	for season in [TerrainSeason.Season.SUMMER, TerrainSeason.Season.WINTER]:
		await _run(season)
	print("[repaint] ", "RESULT: ALL PASS" if failures == 0 else "RESULT: %d FAILED" % failures)
	quit(1 if failures > 0 else 0)

func _run(season: TerrainSeason.Season) -> void:
	var m := TerrainMap.new()
	m.cell_size = 32
	m.season = season
	root.add_child(m)
	await process_frame
	_check(m.is_visible_in_tree() and m.debug_art_coords("floor", Vector2i(50, 50)) == Vector2i(-1, -1), "season %s: map is in the tree with art drawn" % season)
	var cells := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for y in range(0, 20):
		for x in range(0, 24):
			var edge := x == 0 or y == 0 or x == 23 or y == 19
			cells[Vector2i(x, y)] = TerrainTypes.OBSTACLE if edge or rng.randf() < 0.3 else [TerrainTypes.GRASS, TerrainTypes.WATER, TerrainTypes.TREE, TerrainTypes.GROUND][rng.randi_range(0, 3)]
	m.set_cells(cells)
	var types := TerrainTypes.ALL
	var incremental := 0
	var mismatches := 0
	var full := {}
	var first_bad := ""
	for step in 400:
		var c := Vector2i(rng.randi_range(-1, 24), rng.randi_range(-1, 20))
		var before := m.art_bounds()
		match step % 5:
			0, 1: m.set_cell(c, types[rng.randi_range(0, types.size() - 1)])
			2: m.destroy_cell(c)
			3: m.interact_cell(c, [&"cold"]) if rng.randf() < 0.5 else m.clear_cell(c)
			4:
				var batch := {}
				for k in 4:
					batch[c + Vector2i(k % 2, k / 2)] = types[rng.randi_range(0, types.size() - 1)]
				m.set_cells(batch)
		if m.art_bounds() == before:
			incremental += 1
		var drawn := _layers(m)
		m._rebuild_presentation()
		full = _layers(m)
		if drawn != full:
			mismatches += 1
			if first_bad == "":
				first_bad = "step %d cell %s" % [step, c]
	_check(full.size() > 800, "season %s: the layers hold art and swatches (%d cells)" % [season, full.size()])
	_check(mismatches == 0, "season %s: incremental repaint == full rebuild after all 400 writes (first mismatch: %s)" % [season, first_bad])
	_check(incremental > 300, "season %s: most writes took the incremental path (%d of 400)" % [season, incremental])
	m.free()

func _layers(m: TerrainMap) -> Dictionary:
	var out := {}
	for child in m.get_children():
		var layer := child as TileMapLayer
		if layer == null:
			continue
		for c in layer.get_used_cells():
			out["%s %s" % [layer.name, c]] = [layer.get_cell_source_id(c), layer.get_cell_atlas_coords(c), layer.get_cell_alternative_tile(c)]
	return out
