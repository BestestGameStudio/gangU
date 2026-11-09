extends SceneTree
## #348 harness (headless, production main.tscn + the real #346 overworld).
## Cleared state lives in ONE place: Main.cleared_dungeons (#346). This test
## pins the behavior #348 asks for on top of it:
##   (A) clearing DungeonA marks it in Main.cleared_dungeons (others untouched)
##   (B) the overworld then mounts no guards at the DungeonA entrance; the
##       other entrances keep theirs
##   (C) re-entering the cleared DungeonA still mounts fresh enemies, a fresh
##       objective (0/3, not cleared) and reward drops on kills
##   (D) clearing it again leaves a single entry; guards stay suppressed
##   (E) a death restart forgets every clear and re-guards every entrance
## Kills are synthetic apply_damage calls.

var failures := 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[348] ", label, " -> ", "PASS" if ok else "FAIL")

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _enter(main: Node, gate_name: String) -> void:
	var gate: Gate = main.current_area.get_node(gate_name)
	gate._on_body_entered(main.get_node("Player"))
	await _frames(3)

func _guards(main: Node) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for n in main.current_area.get_children():
		if n is Enemy and not ((n as Enemy)._behavior is EnemyBehaviorMigrate): # #373: migrants belong to no entrance
			out.append(n)
	return out

func _near(enemies: Array[Enemy], at: Vector2, r: float) -> int:
	var n := 0
	for e in enemies:
		if e.global_position.distance_to(at) <= r:
			n += 1
	return n

func _drops(area: Node) -> int:
	var n := 0
	for c in area.get_children():
		if c is RewardDrop:
			n += 1
	return n

func _clear_dungeon_a(main: Node) -> void:
	await _enter(main, "GateNormal")
	for _round in 8: # #392: slimes split, keep killing until none remain
		var alive := get_nodes_in_group("enemies").filter(func(n): return is_instance_valid(n) and not n.is_queued_for_deletion())
		if alive.is_empty():
			break
		for e in alive:
			e.apply_damage(9999)
		await _frames(3)

func _initialize() -> void:
	Bestiary.save_path = "user://test348_bestiary.cfg" # keep the player's real record untouched
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(3)
	var p: Player = main.get_node("Player")
	_check(main.get_node_or_null("DungeonClearRecord") == null, "no second store: Main.cleared_dungeons is the only clear state")
	_check(main.cleared_dungeons.is_empty(), "run starts with nothing cleared")

	# uncleared baseline
	await _enter(main, "GateOverworld")
	var ow: Node = main.current_area
	var before := _guards(main)
	_check(before.size() == 16, "uncleared: 16 guards around the 5 entrances, incl. #392 slime (got %d)" % before.size())
	_check(_near(before, ow.get_node("GateNormal").global_position, 200.0) == 3, "uncleared: 3 guards at the DungeonA entrance (guard, patrol, #392 slime)")
	p.global_position = (ow.get_node("PlayerSpawn") as Node2D).global_position
	await _clear_dungeon_a(main)
	_check(main.current_area.name == "DungeonA", "overworld GateNormal -> DungeonA")
	# (A)
	_check(main.cleared_dungeons.has(&"dungeon_a"), "(A) clearing DungeonA records dungeon_a")
	_check(not main.cleared_dungeons.has(&"dungeon_b"), "(A) dungeon_b is not recorded")
	(main.current_area.get_node("ExitPortal") as ExitPortal)._on_body_entered(p)
	await _frames(3)
	_check(main.current_area.name == "Overworld", "exit portal returns to the overworld (#378)")

	# (B)
	ow = main.current_area
	var after := _guards(main)
	_check(_near(after, ow.get_node("GateNormal").global_position, 200.0) == 0, "(B) cleared DungeonA entrance has no guards")
	_check(_near(after, ow.get_node("GateRed").global_position, 160.0) == 2, "(B) uncleared DungeonB entrance keeps its guards")
	_check(after.size() == 13, "(B) 13 guards total (got %d)" % after.size())

	# (C) re-entry of the cleared dungeon is a full fresh run
	p.global_position = (ow.get_node("PlayerSpawn") as Node2D).global_position
	await _enter(main, "GateNormal")
	var area: Node = main.current_area
	var obj := area.get_node_or_null("DungeonObjective") as DungeonObjective
	var enemies := get_nodes_in_group("enemies").size()
	_check(area.name == "DungeonA", "(C) re-entry lands in DungeonA")
	_check(enemies == 5, "(C) re-entry DungeonA has its 5 enemies (3 + 2 slimes, #392) (got %d)" % enemies)
	_check(obj != null and obj.progress() == Vector2i(0, 5) and not obj.is_cleared(), "(C) re-entry objective is fresh 0/5")
	for _round in 8: # #392: slimes split, keep killing until none remain
		var alive := get_nodes_in_group("enemies").filter(func(n): return is_instance_valid(n) and not n.is_queued_for_deletion())
		if alive.is_empty():
			break
		for e in alive:
			e.apply_damage(9999)
		await _frames(3)
	_check(_drops(area) > 0, "(C) re-entry kills drop rewards (%d)" % _drops(area))
	_check(obj.is_cleared(), "(C) re-entry objective clears again")
	# (D)
	_check(main.cleared_dungeons.size() == 1 and main.cleared_dungeons.has(&"dungeon_a"), "(D) still a single dungeon_a entry")
	(area.get_node("ExitPortal") as ExitPortal)._on_body_entered(p)
	await _frames(3)
	_check(main.current_area.name == "Overworld", "(D) exit lands back in the overworld (#378)")
	_check(_near(_guards(main), main.current_area.get_node("GateNormal").global_position, 200.0) == 0, "(D) DungeonA entrance stays unguarded")

	# (E) death restart forgets clears
	p.apply_damage(9999)
	for i in 600:
		await process_frame
		if current_scene != main and current_scene != null:
			break
	var fresh: Node = current_scene
	_check(fresh != main and fresh.current_area.name == "Hub", "(E) death restarts the run in the hub")
	_check(fresh.cleared_dungeons.is_empty(), "(E) cleared dungeons reset with the run")
	fresh.enter_overworld()
	await _frames(3)
	_check(_guards(fresh).size() == 16, "(E) every entrance is guarded again (got %d)" % _guards(fresh).size())
	print("[348] DONE failures=", failures)
	if failures == 0:
		print("RESULT: ALL PASS")
	quit(1 if failures > 0 else 0)
