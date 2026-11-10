extends SceneTree
## #392 harness: slime splits into two half-stat children on death, only when
## its max HP is at least 40 (Daniel).

var failures := 0

## Spawn policy that refuses descendants at/below 20 max HP (policy test).
class SpawnerCap extends EnemySpawner:
	func should_spawn(entry: Dictionary) -> bool:
		var d: Variant = entry.get("definition")
		return d == null or (d as EnemyDefinition).max_hp > 20

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[392] ", name, " -> PASS")
	else:
		failures += 1
		print("[392] ", name, " -> FAIL")

func _slimes(area: Node) -> Array:
	var out: Array = []
	for c in area.get_children():
		if c is EnemySlime:
			out.append(c)
	return out

## Live (not dying) slimes under area; hp > 0 filters by max_hp generation.
func _live(area: Node, hp: int = 0) -> Array:
	var out: Array = []
	for c in area.get_children():
		if c is EnemySlime and is_instance_valid(c) and not c.is_queued_for_deletion() and (hp == 0 or c.max_hp == hp):
			out.append(c)
	return out

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/enemy_slime.tscn")
	var area := Node2D.new()
	root.add_child(area)
	var s := scene.instantiate() as EnemySlime
	area.add_child(s)
	await process_frame
	_check(s.max_hp == 80 and s.contact_damage == 16 and is_equal_approx(s.speed, 90.0), "base slime stats from definition")
	s.apply_damage(80)
	await process_frame
	await process_frame
	var kids := _slimes(area)
	_check(kids.size() == 2, "80 HP slime splits into two")
	if kids.size() == 2:
		var k: EnemySlime = kids[0]
		await process_frame
		_check(k.max_hp == 40 and k.hp == 40, "child max_hp and hp are half")
		_check(k.contact_damage == 8, "child contact_damage is half")
		_check(is_equal_approx(k.speed, 45.0), "child speed is half")
		_check(k.contact_cooldown == 0.8 and k.contact_range == 40.0, "cooldown/range unchanged")
		_check(k.has_meta(&"split_child"), "child flagged split_child")
		_check(k.is_in_group("enemies"), "child joins enemies group")
		_check(not is_equal_approx(kids[0].position.x, kids[1].position.x), "children offset apart")
		# 40 HP child still splits (at least 40, inclusive)
		k.apply_damage(40)
		await process_frame
		await process_frame
		var gk := _slimes(area).filter(func(n): return is_instance_valid(n) and not n.is_queued_for_deletion())
		_check(gk.size() == 3, "40 HP child splits (inclusive threshold): 1 sibling + 2 grandchildren")
		var small: Array = gk.filter(func(n): return n.max_hp == 20)
		_check(small.size() == 2, "grandchildren have 20 max HP")
		if small.size() == 2:
			small[0].apply_damage(20)
			await process_frame
			await process_frame
			var after := _slimes(area).filter(func(n): return is_instance_valid(n) and not n.is_queued_for_deletion())
			_check(after.size() == 2, "20 HP slime dies without splitting")
	# Children inherit movement/targeting context from the parent.
	var a4 := Node2D.new()
	root.add_child(a4)
	var p4 := scene.instantiate() as EnemySlime
	p4.can_swim = true
	p4.objective_aggro_range = 321.0
	a4.add_child(p4)
	await process_frame
	var tm := TerrainMap.new()
	p4.terrain = tm
	var p4_id := p4.get_instance_id()
	p4.apply_damage(80)
	await process_frame
	await process_frame
	var ck := _slimes(a4).filter(func(n): return is_instance_valid(n) and n.get_instance_id() != p4_id and not n.is_queued_for_deletion())
	_check(ck.size() == 2 and ck[0].terrain == tm and ck[0].can_swim and is_equal_approx(ck[0].objective_aggro_range, 321.0), "children inherit terrain, can_swim, objective aggro")
	a4.free()
	# Art: original slime frames, animations and a green body pixel.
	var frames: SpriteFrames = load("res://resources/sprites/slime_frames.tres")
	var counts := {&"idle": 4, &"walk": 6, &"hurt": 2, &"attack": 3, &"death": 5}
	var anims_ok := frames != null
	if anims_ok:
		for a in counts:
			anims_ok = anims_ok and frames.has_animation(a) and frames.get_frame_count(a) == counts[a]
	_check(anims_ok, "slime frames have idle/walk/hurt/attack/death with expected counts")
	var tex: Texture2D = frames.get_frame_texture(&"idle", 0)
	var img := tex.get_image()
	var green := false
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.9 and c.g > c.r + 0.2 and c.g > c.b + 0.2:
				green = true
	_check(green, "idle frame has green body pixels")
	var bs: Dictionary = Bestiary.catalog_entry(&"slime")
	_check(not bs.is_empty() and bs["scene"] == "res://scenes/enemy_slime.tscn", "bestiary lists slime")
	# Placement (Daniel 2026-11-09): normal dungeon A, added alongside the
	# three existing enemies, and near its normal gate in the overworld.
	var da := (load("res://scenes/dungeon_a.tscn") as PackedScene).instantiate()
	var da_entries: Array = da.get_node("SpawnData").entries
	var da_slimes := da_entries.filter(func(e): return (e["enemy"] as PackedScene).resource_path == "res://scenes/enemy_slime.tscn")
	_check(da_entries.size() == 6 and da_slimes.size() == 2, "dungeon A: 3 original + 2 slimes (+ #464 Fishy)")
	da.free()
	var ow := (load("res://scenes/overworld.tscn") as PackedScene).instantiate()
	var gn: Node = ow.get_node("EntranceGuards/GuardsNormal")
	var ow_slimes: Array = gn.entries.filter(func(e): return (e["enemy"] as PackedScene).resource_path == "res://scenes/enemy_slime.tscn")
	_check(gn.dungeon_id == &"dungeon_a" and ow_slimes.size() == 1 and ow_slimes[0].has("definition"), "overworld GuardsNormal has a slime guard")
	var gate_pos: Vector2 = (ow.get_node("GateNormal") as Node2D).position
	_check(ow_slimes.size() == 1 and (ow_slimes[0]["position"] as Vector2).distance_to(gate_pos) < 150.0, "slime guard is near the normal gate")
	ow.free()
	# 39 max HP does not split
	var a2 := Node2D.new()
	root.add_child(a2)
	var t := scene.instantiate() as EnemySlime
	var d := EnemyDefinition.new()
	d.max_hp = 39
	t.definition = d
	a2.add_child(t)
	await process_frame
	t.apply_damage(39)
	await process_frame
	await process_frame
	_check(_slimes(a2).is_empty(), "39 max HP slime does not split")
	# Objective counting: killing the parent must NOT complete a CLEAR_ALL
	# objective while children are alive; it completes only after all descend.
	area.free()
	a2.free()
	await process_frame
	var a3 := Node2D.new()
	root.add_child(a3)
	var p3 := scene.instantiate() as EnemySlime
	a3.add_child(p3)
	var obj := DungeonObjective.new()
	obj.objective_type = DungeonObjective.ObjectiveType.CLEAR_ALL_ENEMIES
	a3.add_child(obj)
	await process_frame
	_check(obj.progress() == Vector2i(0, 1), "objective starts at 0/1")
	p3.apply_damage(80)
	await process_frame
	await process_frame
	_check(not obj.is_cleared(), "parent death does not clear while children alive")
	_check(obj.progress() == Vector2i(1, 3), "progress 1/3 after parent death")
	var live := _slimes(a3).filter(func(n): return is_instance_valid(n) and not n.is_queued_for_deletion())
	_check(live.size() == 2, "two children alive")
	live[0].apply_damage(40)
	await process_frame
	await process_frame
	_check(not obj.is_cleared(), "still not cleared with grandchildren alive")
	var rest := _slimes(a3).filter(func(n): return is_instance_valid(n) and not n.is_queued_for_deletion())
	var guard := 0
	while not rest.is_empty() and guard < 10:
		for n in rest:
			n.apply_damage(n.hp)
		await process_frame
		await process_frame
		rest = _slimes(a3).filter(func(n): return is_instance_valid(n) and not n.is_queued_for_deletion())
		guard += 1
	_check(obj.is_cleared(), "cleared only after every descendant is dead")

	# --- stove-jebs #394 review regressions --------------------------------
	# CLEAR_ALL in production mount order (spawner first, objective after),
	# reviewer kill order: 80 root, then one full branch (first 40 + both 20s),
	# then the last 40. The last 40's death must NOT complete the objective
	# while its two 20 HP children are pending, and the spawner must count
	# every generation.
	var a5 := Node2D.new()
	root.add_child(a5)
	var sp := EnemySpawner.new()
	a5.add_child(sp)
	sp.setup([{"position": Vector2.ZERO, "enemy": scene, "reward_table": null}], NodePath(""), null, a5)
	sp.spawn_initial()
	var obj2 := DungeonObjective.new()
	obj2.objective_type = DungeonObjective.ObjectiveType.CLEAR_ALL_ENEMIES
	a5.add_child(obj2)
	await process_frame
	await process_frame
	_check(obj2.progress() == Vector2i(0, 1) and sp.total_alive() == 1, "review order: mounted 0/1 with one alive")
	_live(a5)[0].apply_damage(80)
	await process_frame
	await process_frame
	_check(obj2.progress() == Vector2i(1, 3) and sp.total_alive() == 2, "review order: 80 root -> 1/3, both 40s counted")
	_live(a5, 40)[0].apply_damage(40)
	await process_frame
	await process_frame
	_check(obj2.progress() == Vector2i(2, 5) and sp.total_alive() == 3, "review order: first 40 -> 2/5, grandchildren counted")
	for n in _live(a5, 20):
		n.apply_damage(20)
		await process_frame
		await process_frame
	_check(obj2.progress() == Vector2i(4, 5) and sp.total_alive() == 1, "review order: branch cleared -> 4/5, one 40 left")
	_live(a5, 40)[0].apply_damage(40)
	await process_frame
	await process_frame
	_check(not obj2.is_cleared(), "REVIEW BLOCKER 1: last 40's death must not complete CLEAR_ALL while its children live")
	_check(obj2.progress() == Vector2i(5, 7), "review order: last 40 -> 5/7")
	_check(sp.total_alive() == 2, "REVIEW BLOCKER 2: spawner counts the two pending 20 HP descendants")
	for n in _live(a5, 20):
		n.apply_damage(20)
		await process_frame
		await process_frame
	_check(obj2.is_cleared() and obj2.progress() == Vector2i(7, 7) and sp.total_alive() == 0, "cleared at 7/7 only when every descendant is dead")
	a5.free()
	await process_frame
	# ELIMINATION: the boss phase must not start while split descendants
	# remain (same order bug, second symptom).
	var a6 := Node2D.new()
	root.add_child(a6)
	var sp2 := EnemySpawner.new()
	a6.add_child(sp2)
	sp2.setup([{"position": Vector2.ZERO, "enemy": scene, "reward_table": null}], NodePath(""), null, a6)
	sp2.spawn_initial()
	var obj3 := DungeonObjective.new()
	obj3.objective_type = DungeonObjective.ObjectiveType.ELIMINATION
	obj3.boss_scene = load("res://scenes/enemy.tscn")
	a6.add_child(obj3)
	await process_frame
	await process_frame
	var boss_ref: Array = [null]
	obj3.boss_spawned.connect(func(b): boss_ref[0] = b)
	_check(obj3.progress() == Vector2i(0, 2), "elimination: 0/2 (one mob + boss)")
	_live(a6)[0].apply_damage(80)
	await process_frame
	await process_frame
	_live(a6, 40)[0].apply_damage(40)
	await process_frame
	await process_frame
	for n in _live(a6, 20):
		n.apply_damage(20)
		await process_frame
		await process_frame
	_check(boss_ref[0] == null and obj3.progress() == Vector2i(4, 6), "elimination: one branch cleared -> 4/6, no boss")
	_live(a6, 40)[0].apply_damage(40)
	await process_frame
	await process_frame
	_check(boss_ref[0] == null, "REVIEW BLOCKER 1: last 40's death must not start the boss phase while its children live")
	_check(obj3.progress() == Vector2i(5, 8) and not obj3.is_cleared(), "elimination: last 40 -> 5/8")
	for n in _live(a6, 20):
		n.apply_damage(20)
		await process_frame
		await process_frame
	_check(boss_ref[0] != null and _live(a6).is_empty(), "elimination: boss spawns only once every mob descendant is dead")
	if boss_ref[0] != null:
		var boss: Enemy = boss_ref[0]
		await process_frame
		await process_frame
		boss.apply_damage(boss.hp)
		await process_frame
		await process_frame
		_check(obj3.is_cleared() and obj3.progress() == Vector2i(8, 8), "elimination completes on the boss kill")
	a6.free()
	await process_frame
	# DEFENSE: a slime wave is not cleared until its descendants are dead.
	var a7 := Node2D.new()
	root.add_child(a7)
	var core := DefenseCore.new()
	core.name = "DefenseCore"
	a7.add_child(core)
	var obj4 := DungeonObjective.new()
	obj4.objective_type = DungeonObjective.ObjectiveType.DEFENSE
	obj4.wave_count = 1
	obj4.wave_base_size = 1
	obj4.wave_size_growth = 0
	obj4.wave_enemy_scene = scene
	obj4.wave_spawn_points = [Vector2.ZERO]
	a7.add_child(obj4)
	await process_frame
	await process_frame
	obj4.spawn_next_wave()
	await process_frame
	await process_frame
	_check(_live(a7).size() == 1 and obj4.progress() == Vector2i(0, 1), "defense: one-slime wave spawned")
	var guard2 := 0
	var gen := _live(a7)
	while not gen.is_empty() and guard2 < 10:
		gen[0].apply_damage(gen[0].hp)
		await process_frame
		await process_frame
		gen = _live(a7)
		if not gen.is_empty():
			_check(not obj4.is_cleared(), "defense: wave not cleared while descendants live")
		guard2 += 1
	_check(obj4.is_cleared() and obj4.progress() == Vector2i(1, 1), "defense: wave cleared only when every descendant is dead")
	a7.free()
	await process_frame
	# Spawn policy governs descendants routed through the spawner seam.
	var a8 := Node2D.new()
	root.add_child(a8)
	var sp3 := SpawnerCap.new()
	a8.add_child(sp3)
	sp3.setup([{"position": Vector2.ZERO, "enemy": scene, "reward_table": null}], NodePath(""), null, a8)
	sp3.spawn_initial()
	await process_frame
	await process_frame
	_live(a8)[0].apply_damage(80)
	await process_frame
	await process_frame
	_check(_live(a8).size() == 2 and sp3.total_alive() == 2, "policy allows the two 40 HP children")
	_live(a8, 40)[0].apply_damage(40)
	await process_frame
	await process_frame
	_check(_live(a8, 20).is_empty(), "policy refuses 20 HP grandchildren (should_spawn governs splits)")
	_check(sp3.total_alive() == 1, "refused children never enter spawner bookkeeping")
	a8.free()
	print("[392] DONE failures=", failures)
	quit(failures)
