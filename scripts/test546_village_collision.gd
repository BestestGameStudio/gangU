extends SceneTree
## #546 harness: village houses + well are solid (cells and shots), the
## ambushers spawn outside the tree ring, the trigger stays at the centre.

var failures := 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[546] ", label, " -> ", "PASS" if ok else "FAIL")

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _initialize() -> void:
	var area: Node2D = load("res://scenes/overworld.tscn").instantiate()
	root.add_child(area)
	await _frames(2)
	var village := area.get_node("AbandonedVillage") as AbandonedVillage
	var map := area.get_node("Terrain") as TerrainMap
	var rects := village.footprints()
	_check(rects.size() == 7, "six houses and the well have footprints (%d)" % rects.size())
	var all_solid := true
	var shot_solid := true
	for r in rects:
		for fx in [0.5]:
			for fy in [0.5]:
				var pt := r.position + Vector2(r.size.x * fx, r.size.y * fy)
				if map.is_walkable_at(pt):
					all_solid = false
				if not map.blocks_projectiles_at_cell(map.world_to_cell(pt)) and map.projectile_block_t(pt - Vector2(60, 0), Vector2(120, 0)) >= 1.0:
					shot_solid = false
	_check(all_solid, "the centre of every footprint is unwalkable")
	_check(shot_solid, "shots crossing every footprint are blocked")
	var well := rects[6]
	_check(map.projectile_block_t(well.position - Vector2(80, -well.size.y * 0.5), Vector2(well.size.x + 160, 0)) < 1.0, "a shot through the well is blocked")
	_check(map.is_walkable_at(village.position + Vector2(85, 0)), "the gap between well and houses stays walkable")
	# Spawn ring
	var min_r := 99999.0
	for e in (village.event as AmbushEvent).entries:
		min_r = minf(min_r, (e["position"] as Vector2).length())
	_check(min_r >= 520.0, "all 30 ambushers spawn outside the tree ring (min radius %.0f)" % min_r)
	_check((village.event as AmbushEvent).entries.size() == 30, "still 30 ambushers")
	var cs := village.get_child(0) as CollisionShape2D
	_check((cs.shape as CircleShape2D).radius == 300.0 and village.position == AbandonedVillage.CENTER, "trigger stays at the village centre (r 300)")
	var ground := area.get_node("Ground") as OverworldGround
	var tree_far := 0.0
	for d in ground.decor:
		if d["kind"] == "tree" and (d["at"] as Vector2).distance_to(village.position) < 520.0:
			tree_far = maxf(tree_far, (d["at"] as Vector2).distance_to(village.position) + float(d["r"]))
	_check(tree_far < min_r, "tree ring outer edge %.0f is inside the spawn radius" % tree_far)
	print("[546] failures: ", failures)
	quit(1 if failures > 0 else 0)
