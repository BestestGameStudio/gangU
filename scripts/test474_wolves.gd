extends SceneTree
## #474 acceptance harness: wolf enemy type (Daniel, 2026-11-09:
## "Wolves spawn in caves in the overworld. Wolves only hunt at night and
## travel in packs. They are very fast, weave around trees, and can
## telegraph a pounce. Caves cannot be entered. Wolves spawn in at night.
## Make the sprites yourself"; answers: "6 wolves, caves spawn near the
## edges of the overworld", "Retreat into cave and despawn. If a player
## fights them they fight back and do not retreat", "heavy damage, 0.5s",
## caves are "Decor").
##   (A) production scene: WolfCaves container places 3 decor caves near
##       the overworld edges; a cave is no Gate/Area2D (not enterable).
##   (B) night spawn: no wolves by day; at nightfall the cave spawns a
##       pack of 6 fast wolves (wolf.tres stats).
##   (C) pounce: 0.5s telegraph, THEN the lunge lands heavy damage.
##   (D) daybreak: unengaged wolves retreat into the cave and despawn.
##   (E) engaged wolves fight back and do not retreat at daybreak; they
##       leave once the fight ends.
##   (H) regression (#476 review): survivors of a day fight hunt again the
##       next night - the stale wolf_retreat flag is cleared at nightfall.
##   (F) wolves weave around trees on the way to the player (#391 seam).
##   (G) pack hunt: one engaged wolf pulls the pack in from beyond its
##       own hunt range.
## Fixture idioms follow test414/test391. Run:
## godot --headless --path . -s scripts/test474_wolves.gd

const DT := 1.0 / 60.0

var failures := 0
var _player_scene: PackedScene
var _wolf_scene: PackedScene
var _cave_scene: PackedScene

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[474] ", label, " -> ", "PASS" if ok else "FAIL")

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _initialize() -> void:
	_player_scene = load("res://scenes/player.tscn")
	_wolf_scene = load("res://scenes/enemy_wolf.tscn")
	_cave_scene = load("res://scenes/wolf_cave.tscn")
	await _leg_a_scene_data()
	await _leg_b_night_spawn()
	await _leg_c_pounce()
	await _leg_d_daybreak_retreat()
	await _leg_e_engaged_no_retreat()
	await _leg_h_next_night_hunt()
	await _leg_f_tree_weave()
	await _leg_g_pack_hunt()
	print("[474] DONE failures=", failures)
	if failures == 0:
		print("RESULT: ALL PASS")
	quit(1 if failures > 0 else 0)

# --- fixture helpers ---------------------------------------------------------

func _mk_stage(with_map: bool = false) -> Array:
	var stage := Node2D.new()
	stage.name = "Stage474"
	root.add_child(stage)
	var map: TerrainMap = null
	if with_map:
		map = TerrainMap.new()
		map.name = "Terrain"
		map.cell_size = 32
		stage.add_child(map)
	return [stage, map]

func _mk_player(stage: Node2D, pos: Vector2) -> Player:
	var p: Player = _player_scene.instantiate()
	p.name = "Player"
	p.max_hp = 1000 # #493 stacked pounces must not end the behavior fixtures early.
	p.collision_layer = 0
	p.collision_mask = 0
	p.set_process(false)
	stage.add_child(p)
	p.global_position = pos
	p.set_physics_process(false)
	return p

func _mk_clock(time: float) -> DayNightClock:
	var clock := DayNightClock.ensure(self)
	clock.time_of_day = time
	return clock

func _mk_cave(stage: Node2D, pos: Vector2, map: TerrainMap = null) -> WolfCave:
	var cave: WolfCave = _cave_scene.instantiate()
	cave.terrain = map
	stage.add_child(cave)
	cave.global_position = pos
	cave.player_path = NodePath("../Player")
	return cave

func _state(w: Enemy) -> String:
	var beh: RefCounted = w.get("_behavior")
	if beh == null or not beh.has_method("state_name"):
		return "?"
	return beh.state_name()

func _teardown(stage: Node2D) -> void:
	# Free enemies before the player/stage: enemy._exit_tree unpairs
	# collision exceptions and the engine ERR_PRINTs on freed peers.
	for e in get_nodes_in_group("enemies"):
		(e as Node).queue_free()
	await process_frame
	await process_frame
	stage.queue_free()
	await process_frame
	await process_frame

# --- (A) production scene data ------------------------------------------------

func _leg_a_scene_data() -> void:
	var ow: Node2D = load("res://scenes/overworld.tscn").instantiate()
	root.add_child(ow)
	await _frames(3)
	var holder := ow.get_node_or_null("WolfCaves")
	_check(holder != null, "(A) overworld has a WolfCaves container")
	var ground := ow.get_node("Ground") as OverworldGround
	var caves := ow.find_children("WolfCave*", "WolfCave", true, false)
	_check(caves.size() == 3, "(A) 3 wolf caves placed (got %d)" % caves.size())
	var edge_min: float = 0.6 * minf(OverworldGround.RADII.x, OverworldGround.RADII.y)
	var all_edge := true
	var all_inside := true
	var all_decor := true
	for c in caves:
		var d: float = (c as Node2D).position.distance_to(OverworldGround.CENTER)
		if d < edge_min:
			all_edge = false
		if not ground.covers((c as Node2D).position):
			all_inside = false
		for n in (c as Node).find_children("*", "", true, false):
			if n is Gate or n is Area2D:
				all_decor = false
		if (c as Node).get_node_or_null("Sprite") == null:
			all_decor = false
	_check(all_edge, "(A) every cave sits near the overworld edge (>= %.0fpx from field centre)" % edge_min)
	_check(all_inside, "(A) every cave is inside the field outline")
	_check(all_decor, "(A) caves are decor: sprite only, no Gate/Area2D (cannot be entered)")
	# day clock: no wolves in the production scene
	var wolves := ow.find_children("Wolf*", "Enemy", true, false)
	_check(wolves.is_empty(), "(A) daytime mount spawns no wolves")
	ow.free()

# --- (B) night spawn ----------------------------------------------------------

func _leg_b_night_spawn() -> void:
	var fx := _mk_stage()
	var stage: Node2D = fx[0]
	_mk_player(stage, Vector2(4000, 4000)) # far away: no engagement
	var clock := _mk_clock(0.5) # noon
	var cave := _mk_cave(stage, Vector2.ZERO)
	await _frames(10)
	_check(cave.alive_count() == 0, "(B) no wolves by day")
	clock.time_of_day = 0.85 # night falls
	await _frames(10)
	_check(cave.alive_count() == 6, "(B) nightfall spawns a pack of 6 (got %d)" % cave.alive_count())
	var fast := true
	var heavy := true
	var wolf_def := true
	for w in cave.pack:
		if w.speed < 250.0:
			fast = false
		if w.contact_damage < 25:
			heavy = false
		if w.definition == null or w.definition.behavior.get_script() != EnemyBehaviorWolf:
			wolf_def = false
	_check(fast and cave.pack.size() > 0, "(B) wolves are very fast (speed %.0f vs player 320)" % (cave.pack[0].speed if cave.pack.size() > 0 else 0.0))
	_check(heavy, "(B) pounce damage stat is heavy (30 vs mob contact 10)")
	_check(wolf_def, "(B) wolves carry the wolf definition/behavior")
	_check(WolfCave.is_night(0.85) and not WolfCave.is_night(0.5), "(B) night window is sunset..sunrise")
	await _teardown(stage)

# --- (C) pounce: telegraph then heavy hit --------------------------------------

func _leg_c_pounce() -> void:
	var fx := _mk_stage()
	var stage: Node2D = fx[0]
	var p := _mk_player(stage, Vector2.ZERO)
	_mk_clock(0.85)
	var wolf: Enemy = _wolf_scene.instantiate()
	wolf.player_path = NodePath("../Player")
	wolf.context = _ctx_at(Vector2(-170, 0))
	stage.add_child(wolf)
	wolf.global_position = Vector2(-170, 0)
	await _frames(5)
	var telegraph_frame := -1
	var hit_frame := -1
	var hp0: int = p.hp
	var dmg_during_telegraph := false
	var f := 0
	while f < 600 and hit_frame < 0:
		await physics_frame
		f += 1
		var st := _state(wolf)
		if st == "TELEGRAPH" and telegraph_frame < 0:
			telegraph_frame = f
		if p.hp < hp0:
			hit_frame = f
			if telegraph_frame < 0 or f <= telegraph_frame + 2:
				dmg_during_telegraph = true
	_check(telegraph_frame >= 0, "(C) wolf telegraphs the pounce (crouch state)")
	_check(hit_frame >= 0, "(C) the pounce lands")
	if telegraph_frame >= 0 and hit_frame >= 0:
		var delay := (hit_frame - telegraph_frame) * DT
		_check(not dmg_during_telegraph and delay >= 0.45,
			"(C) damage lands only after the 0.5s telegraph (got %.2fs)" % delay)
		_check(hp0 - p.hp >= 25, "(C) pounce damage is heavy (got %d)" % (hp0 - p.hp))
	await _teardown(stage)

# --- (D) daybreak retreat ------------------------------------------------------

func _leg_d_daybreak_retreat() -> void:
	var fx := _mk_stage()
	var stage: Node2D = fx[0]
	_mk_player(stage, Vector2(4000, 4000)) # far: nobody is fighting
	var clock := _mk_clock(0.85) # night
	var cave := _mk_cave(stage, Vector2.ZERO)
	await _frames(10)
	_check(cave.alive_count() == 6, "(D) pack out at night")
	clock.time_of_day = 0.4 # daybreak
	var gone := false
	for i in 300: # up to 5s
		await physics_frame
		if cave.alive_count() == 0:
			gone = true
			break
	_check(gone, "(D) at daybreak unengaged wolves retreat into the cave and despawn")
	await _teardown(stage)

# --- (E) engaged wolves do not retreat -----------------------------------------

func _leg_e_engaged_no_retreat() -> void:
	var fx := _mk_stage()
	var stage: Node2D = fx[0]
	var p := _mk_player(stage, Vector2.ZERO)
	var clock := _mk_clock(0.85)
	var cave := _mk_cave(stage, Vector2(300, 0)) # pack spawns 300px from the player
	await _frames(10)
	_check(cave.alive_count() == 6, "(E) pack out at night")
	clock.time_of_day = 0.4 # daybreak mid-hunt
	await _frames(180) # 3s of daylight
	var alive_mid := cave.alive_count()
	_check(alive_mid > 0, "(E) engaged wolves fight back and do not retreat at daybreak (alive %d/6)" % alive_mid)
	# fight ends (player leaves): the survivors go home and despawn
	p.global_position = Vector2(6000, 6000)
	var gone := false
	for i in 600: # up to 10s (combat memory + walk home)
		await physics_frame
		if cave.alive_count() == 0:
			gone = true
			break
	_check(gone, "(E) once the fight ends the wolves retreat and despawn")
	await _teardown(stage)

# --- (H) next night: survivors of a day fight hunt again -------------------------

func _leg_h_next_night_hunt() -> void:
	# #476 review (Mitra): order_retreat sets wolf_retreat on the live pack
	# at dawn; a survivor that kept fighting carries the stale flag into the
	# next night, and the behavior then retreats instead of hunting.
	var fx := _mk_stage()
	var stage: Node2D = fx[0]
	var p := _mk_player(stage, Vector2(400, 0)) # engaged: inside 500 fight range
	var clock := _mk_clock(0.85) # night 1
	var cave := _mk_cave(stage, Vector2.ZERO)
	await _frames(10)
	_check(cave.alive_count() == 6, "(H) night 1: pack out")
	clock.time_of_day = 0.4 # daybreak mid-hunt: retreat ordered on the live pack
	await _frames(30)
	var flagged := false
	for w in cave.pack:
		if (w.context as WolfContext).retreat:
			flagged = true
	_check(flagged, "(H) daybreak flags the live pack wolf_retreat (fixture)")
	# The fight runs into the next night; the player then steps out of fight
	# range but stays inside hunt range.
	clock.time_of_day = 0.85 # night 2
	await _frames(5)
	p.global_position = Vector2(400, 800) # ~800px: inside 1150 hunt, outside 500 fight
	await _frames(15)
	var hunting := 0
	for w in cave.pack:
		if _state(w) == "HUNT":
			hunting += 1
	_check(hunting > 0, "(H) next night: survivors hunt again instead of obeying the stale retreat (hunting %d/%d)" % [hunting, cave.pack.size()])
	var cleared := true
	for w in cave.pack:
		if (w.context as WolfContext).retreat:
			cleared = false
	_check(cleared, "(H) nightfall clears the stale wolf_retreat flag")
	await _teardown(stage)

# --- (F) weave around trees -----------------------------------------------------

func _leg_f_tree_weave() -> void:
	var fx := _mk_stage(true)
	var stage: Node2D = fx[0]
	var map: TerrainMap = fx[1]
	var p := _mk_player(stage, Vector2(220, 0))
	_mk_clock(0.85)
	# A solid tree wall between the wolf and the player (test391 idiom).
	var cells := {}
	for cy in range(-5, 6):
		cells[Vector2i(0, cy)] = TerrainTypes.OBSTACLE
	map.set_cells(cells)
	var wolf: Enemy = _wolf_scene.instantiate()
	wolf.player_path = NodePath("../Player")
	wolf.terrain = map
	wolf.context = _ctx_at(Vector2(-220, 0))
	stage.add_child(wolf)
	wolf.global_position = Vector2(-220, 0)
	var reached := false
	var clean := true
	for i in 600: # up to 10s
		await physics_frame
		var cell := map.world_to_cell(wolf.global_position)
		if cells.has(cell):
			clean = false
		if wolf.global_position.distance_to(p.global_position) <= 210.0:
			reached = true
			break
	_check(reached, "(F) wolf paths around the tree wall to the player")
	_check(clean, "(F) wolf never stands on a blocked cell (weaves around trees)")
	await _teardown(stage)

# --- (G) pack hunt ---------------------------------------------------------------

func _leg_g_pack_hunt() -> void:
	var fx := _mk_stage()
	var stage: Node2D = fx[0]
	var p := _mk_player(stage, Vector2.ZERO)
	_mk_clock(0.85)
	var cave := _mk_cave(stage, Vector2(400, 0))
	await _frames(10)
	_check(cave.alive_count() == 6, "(G) pack out at night")
	if cave.alive_count() < 2:
		await _teardown(stage)
		return
	# Stage: wolf0 fights the player up close; wolf5 sits 1300px out,
	# beyond its own HUNT_RANGE but inside the pack alert radius.
	cave.pack[0].global_position = Vector2(150, 0)
	cave.pack[5].global_position = Vector2(-1300, 0)
	cave.pack[0].apply_damage(5) # a hit: wolf0 is fighting
	await _frames(90) # 1.5s
	_check(_state(cave.pack[0]) != "PROWL", "(G) the engaged wolf hunts")
	_check(_state(cave.pack[5]) == "HUNT", "(G) pack alert pulls the far packmate into the hunt (got %s)" % _state(cave.pack[5]))
	await _teardown(stage)

func _ctx_at(anchor: Vector2) -> WolfContext:
	var c := WolfContext.new()
	c.anchor = anchor
	c.has_anchor = true
	return c
