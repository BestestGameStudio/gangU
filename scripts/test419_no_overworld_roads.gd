extends SceneTree
## #419 harness: the overworld no longer draws dirt paths to the gates
## (Daniel, 2026-11-09: "Remove the visible dirt paths leading to gates in
## the overworld. Keep this change cosmetic").
##   (A) layout unchanged: one road polyline per gate is still computed, decor
##       is still kept off it, and every road spine stays walkable on the
##       Terrain grid - so tree placement, collision and routes are as before.
##   (B) rendered (skipped under --headless, run with xvfb + opengl3): points
##       on every road spine, clear of the arrival clearing and gate pads, are
##       not painted in the dirt road colours any more.

var failures := 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[419] ", label, " -> ", "PASS" if ok else "FAIL")

func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.025 and absf(a.g - b.g) < 0.025 and absf(a.b - b.b) < 0.025

func _initialize() -> void:
	var area: Node2D = load("res://scenes/overworld.tscn").instantiate()
	root.add_child(area)
	for i in 3:
		await physics_frame
	var ground := area.get_node("Ground") as OverworldGround
	var map := area.get_node("Terrain") as TerrainMap

	# --- (A) layout untouched ---
	var gates := 0
	for c in area.get_children():
		if c is Gate:
			gates += 1
	_check(gates > 0 and ground.roads.size() == gates, "A: one road layout per gate still computed (%d/%d)" % [ground.roads.size(), gates])
	var decor_ok := ground.decor.size() > 40
	for d in ground.decor:
		if ground.road_distance(d["at"]) <= OverworldGround.ROAD_CLEAR:
			decor_ok = false
	_check(decor_ok, "A: %d decor pieces, still none on a (now invisible) road" % ground.decor.size())
	var walkable := map != null
	if map != null:
		for road in ground.roads:
			for p in road:
				if not map.is_walkable_at(p):
					walkable = false
	_check(walkable, "A: every road spine still walkable")

	# --- (B) nothing dirt-coloured along the old roads ---
	if DisplayServer.get_name() == "headless":
		print("[419] B: headless display - pixel check skipped (run under xvfb with opengl3)")
	else:
		var cam := Camera2D.new()
		area.add_child(cam)
		cam.make_current()
		var samples: Array[Vector2] = []
		for road in ground.roads:
			for i in road.size() - 1:
				var mid: Vector2 = road[i].lerp(road[i + 1], 0.5)
				if mid.distance_to(ground.spawn) < OverworldGround.ARRIVAL_R + 30.0:
					continue
				var by_gate := false
				for l in ground.landmarks:
					if mid.distance_to(l) < 90.0:
						by_gate = true
				if not by_gate:
					samples.append(mid)
		var dirty := 0
		for s in samples:
			cam.global_position = s
			for i in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			var c := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
			if _near(c, OverworldGround.ROAD) or _near(c, OverworldGround.ROAD_EDGE_COLOR):
				dirty += 1
				print("[419]   dirt colour %s at %s" % [c, s])
		_check(samples.size() >= ground.roads.size(), "B: sampled %d road-spine points" % samples.size())
		_check(dirty == 0, "B: no road-spine point is drawn as dirt (%d dirty)" % dirty)

	print("RESULT: ", "ALL PASS" if failures == 0 else "%d FAIL" % failures)
	quit(0 if failures == 0 else 1)
