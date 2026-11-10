extends SceneTree
## #437 harness: spell-created terrain blocks are VISIBLE in the overworld
## (Daniel, 2026-11-09: "stone block spell crested terrain is invisible in
## the overworld" - collision worked, nothing rendered). The overworld's
## Terrain node is a hidden collision-only grid (#391), so the block
## visuals live as its SIBLING and resolve the map through map_path.
##   (A) scene wiring: overworld.tscn carries a BlockVisuals node that is
##       NOT under the hidden Terrain node, and it resolves the area's
##       TerrainMap through its exported map_path.
##   (B) visibility chain: the visuals node renders even though the
##       Terrain node stays invisible.
##   (C) lifecycle on the real scene: a fresh BLOCK cell on the overworld
##       grid gets a standing wall sprite; destroying the cell drops it.
##   (D) dungeon wiring unchanged: dungeon_generated.tscn keeps its
##       BlockVisuals as a child of Terrain with the parent fallback.

var failures := 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[437] ", label, " -> ", "PASS" if ok else "FAIL")

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# Leg A/B/C: the real overworld scene.
	var area: Node2D = load("res://scenes/overworld.tscn").instantiate()
	root.add_child(area)
	await _frames(2)
	var terrain := area.get_node_or_null("Terrain") as TerrainMap
	_check(terrain != null, "overworld has its Terrain grid (#391)")
	var vis := area.get_node_or_null("BlockVisuals") as TerrainBlockVisuals
	_check(vis != null, "overworld has a BlockVisuals node")
	if terrain == null or vis == null:
		print("[437] failures: ", failures)
		quit(1)
		return
	_check(vis.get_parent() != terrain, "BlockVisuals is not a child of the hidden Terrain")
	_check(vis.map_path != NodePath(""), "BlockVisuals names its map through map_path")
	await _frames(2)
	_check(vis._map == terrain, "map_path resolves the overworld TerrainMap")
	_check(not terrain.visible, "Terrain stays hidden (collision-only grid)")
	_check(vis.is_visible_in_tree(), "BlockVisuals renders while Terrain is hidden")

	# a fresh block appears and disappears with the cell
	var cell := Vector2i(4, 4)
	_check(terrain.tile_type_at_cell(cell) != TerrainTypes.BLOCK, "target cell starts clear")
	terrain.set_cell(cell, TerrainTypes.BLOCK)
	await _frames(2)
	var wall := vis.debug_standing_at(cell)
	_check(wall != null, "fresh overworld BLOCK gets a standing wall sprite")
	if wall != null:
		_check(wall.position == (Vector2(cell) + Vector2(0.5, 0.5)) * float(terrain.cell_size), "wall centred on its cell at the overworld cell size")
	_check(terrain.destroy_at(terrain.cell_to_world(cell)), "overworld block still destroys (#169 semantics)")
	await _frames(2)
	_check(vis.debug_standing_at(cell) == null, "destroyed block's wall is gone")

	area.queue_free()
	await _frames(2)

	# Leg D: the dungeon keeps the original child-of-Terrain wiring.
	var dungeon: Node2D = load("res://scenes/dungeon_generated.tscn").instantiate()
	root.add_child(dungeon)
	await _frames(2)
	var dterrain := dungeon.get_node_or_null("Terrain") as TerrainMap
	var dvis := dungeon.get_node_or_null("Terrain/BlockVisuals") as TerrainBlockVisuals
	_check(dterrain != null and dvis != null, "dungeon BlockVisuals stays a child of Terrain")
	if dvis != null:
		_check(dvis.map_path == NodePath(""), "dungeon BlockVisuals keeps the parent fallback (no map_path)")
		await _frames(2)
		_check(dvis._map == dterrain, "dungeon BlockVisuals resolves its parent TerrainMap")

	print("[437] failures: ", failures)
	quit(1 if failures > 0 else 0)
