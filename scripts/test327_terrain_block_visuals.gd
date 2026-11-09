extends SceneTree
## #327 harness: the terrain-block sprite-sheet visuals (headless).
## Proves: the packed SpriteFrames carries create/intact/damage/destroy with
## the expected frame counts and loop flags and the sheet reads rock-brown;
## a fresh BLOCK cell gets a standing wall sprite that plays the build-up
## then settles on intact; a pre-existing BLOCK cell (map seeding, no cast)
## renders intact without the build-up; destroying the block drops the wall,
## plays one collapse one-shot and frees it; and destroying a NON-BLOCK
## destroyable (TREE) spawns nothing. Presentation only: the map's cell data
## and one-hit destroy are #216/#169's, untouched here.

var failures := 0

func _check(cond: bool, name: String) -> void:
	if not cond:
		failures += 1
	print("[327] ", name, " -> ", "PASS" if cond else "FAIL")

func _anim(frames: SpriteFrames, name: StringName) -> Array:
	var out := []
	for i in range(frames.get_frame_count(name)):
		out.append(frames.get_frame_texture(name, i))
	return out

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# Leg A: the resource contract.
	var frames: SpriteFrames = load("res://resources/sprites/terrain_block_frames.tres")
	_check(frames != null, "frames resource loads")
	if frames == null:
		print("[327] failures: ", failures)
		quit(1)
		return
	var expected := {&"create": [6, false], &"intact": [1, true], &"damage": [4, false], &"destroy": [6, false]}
	for anim: StringName in expected:
		_check(frames.has_animation(anim), "animation '%s' exists" % anim)
		if frames.has_animation(anim):
			_check(frames.get_frame_count(anim) == expected[anim][0], "animation '%s' has %d frames" % [anim, expected[anim][0]])
			_check(frames.get_animation_loop(anim) == expected[anim][1], "animation '%s' loop flag" % anim)
	var tex: Texture2D = load("res://assets/sprites/terrain_block.png")
	_check(tex != null and tex.get_width() == 384 and tex.get_height() == 192, "packed sheet is 384x192")
	if tex != null:
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		# centre of the intact cell (row 1, col 0): solid rock, warm brown-grey
		var px := img.get_pixel(32, 64 + 20)
		_check(px.a > 0.9 and px.r > px.b and px.r > 0.25 and px.r < 0.9, "intact cell samples rock-brown (got %s)" % px)

	# Leg B: lifecycle on a real TerrainMap.
	var stage := Node2D.new()
	root.add_child(stage)
	var map := TerrainMap.new()
	map.cell_size = 64
	stage.add_child(map)
	map.set_cell(Vector2i(5, 5), TerrainTypes.BLOCK) # pre-existing: seeded before visuals arrive
	var vis := TerrainBlockVisuals.new()
	map.add_child(vis)
	await physics_frame
	await physics_frame
	var seeded: AnimatedSprite2D = vis.debug_standing_at(Vector2i(5, 5))
	_check(seeded != null, "pre-existing BLOCK renders a standing wall")
	if seeded != null:
		_check(seeded.animation == &"intact", "pre-existing BLOCK settles on intact without build-up")
	_check(seeded != null and seeded.position == (Vector2(5, 5) + Vector2(0.5, 0.5)) * 64.0, "wall centred on its cell")

	# fresh placement plays the build-up first
	map.set_cell(Vector2i(7, 5), TerrainTypes.BLOCK)
	await physics_frame
	await physics_frame
	var fresh: AnimatedSprite2D = vis.debug_standing_at(Vector2i(7, 5))
	_check(fresh != null, "fresh BLOCK gets a standing wall")
	if fresh != null:
		_check(fresh.animation == &"create" or fresh.animation == &"intact", "fresh wall plays create then intact (on '%s')" % fresh.animation)
	await create_timer(1.0).timeout
	_check(is_instance_valid(fresh) and fresh.animation == &"intact", "build-up settles on intact")

	# destruction: wall drops, one collapse plays, then frees
	_check(map.destroy_at(map.cell_to_world(Vector2i(7, 5))), "map destroy still works (#169 semantics)")
	await physics_frame
	_check(vis.debug_standing_at(Vector2i(7, 5)) == null, "destroyed block's wall is gone")
	_check(vis.debug_rubble_count() == 1, "exactly one collapse one-shot plays")
	await create_timer(1.2).timeout
	_check(vis.debug_rubble_count() == 0, "collapse frees itself")
	_check(vis.debug_standing_at(Vector2i(5, 5)) != null, "untouched block keeps its wall")

	# a non-BLOCK destroyable spawns nothing
	map.set_cell(Vector2i(2, 2), TerrainTypes.TREE)
	await physics_frame
	await physics_frame
	_check(vis.debug_standing_at(Vector2i(2, 2)) == null, "TREE gets no wall sprite")
	map.destroy_at(map.cell_to_world(Vector2i(2, 2)))
	await physics_frame
	_check(vis.debug_rubble_count() == 0, "TREE destruction spawns no collapse")

	print("[327] failures: ", failures)
	if failures == 0:
		print("RESULT: ALL PASS")
	quit(1 if failures > 0 else 0)
