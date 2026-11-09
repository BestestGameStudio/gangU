extends SceneTree
## #392 harness: slime splits into two half-stat children on death, only when
## its max HP is at least 40 (Daniel).

var failures := 0

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
	_check(da_entries.size() == 5 and da_slimes.size() == 2, "dungeon A: 3 original + 2 slimes")
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
	print("[392] DONE failures=", failures)
	quit(failures)
