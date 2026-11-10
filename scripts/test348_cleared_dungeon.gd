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
	var gate: Gate = main.area_loader.current_area.get_node(gate_name)
	gate._on_body_entered(main.get_node("Player"))
	await _frames(3)

func _guards(main: Node) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for n in main.area_loader.current_area.get_children():
		if n is Enemy and not _roams((n as Enemy)):
			out.append(n)
	return out

## #373 migrants and the #478 day bird (spawned at a random angle around
## the player) belong to no entrance.
func _roams(e: Enemy) -> bool:
	return e._behavior is EnemyBehaviorMigrate or e._behavior is EnemyBehaviorBird

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
	main.area_loader.gate_reentry_cooldown_seconds = 0.2 # #400: shortened so re-entry legs wait moments, not a real minute

	# uncleared baseline
	await _enter(main, "GateOverworld")
	var ow: Node = main.area_loader.current_area
	var before := _guards(main)
	# #414 mix: 5 posted guards + 14 patrollers (Normal 1+3, Red 1+2, Generated/Beast/Boss 1+3 each);
	# #490: 2 camp Fishy at each of the 5 entrances.
	_check(before.size() == 29, "uncleared: 29 around the 5 entrances, 5 posted guards + 14 patrollers (#414) + 10 camp Fishy (#490) (got %d)" % before.size())
	_check(_near(before, ow.get_node("GateNormal").global_position, 200.0) == 4, "uncleared: 4 at the DungeonA entrance (guard, 2 patrols, #414 slime patroller)")
	p.global_position = (ow.get_node("PlayerSpawn") as Node2D).global_position
	await _clear_dungeon_a(main)
	_check(main.area_loader.current_area.name == "DungeonA", "overworld GateNormal -> DungeonA")
	# (A)
	_check(main.cleared_dungeons.has(&"dungeon_a"), "(A) clearing DungeonA records dungeon_a")
	_check(not main.cleared_dungeons.has(&"dungeon_b"), "(A) dungeon_b is not recorded")
	(main.area_loader.current_area.get_node("ExitPortal") as ExitPortal)._on_body_entered(p)
	await _frames(3)
	_check(main.area_loader.current_area.name == "Overworld", "exit portal returns to the overworld (#378)")

	# (B)
	ow = main.area_loader.current_area
	var after := _guards(main)
	_check(_near(after, ow.get_node("GateNormal").global_position, 200.0) == 0, "(B) cleared DungeonA entrance has no guards")
	_check(_near(after, ow.get_node("GateRed").global_position, 160.0) == 3, "(B) uncleared DungeonB entrance keeps its guards (guard + 2 patrols, #414)")
	_check(after.size() == 23, "(B) 23 total: 29 minus the whole 6-strong DungeonA group (#414, #490) (got %d)" % after.size())

	# (C) re-entry of the cleared dungeon is a full fresh run.
	# #400: the entrance gate is closed for the post-clear cooldown; wait it
	# out (shortened above) before the re-entry this leg pins.
	await create_timer(0.4).timeout
	await _frames(3)
	p.global_position = (ow.get_node("PlayerSpawn") as Node2D).global_position
	await _enter(main, "GateNormal")
	var area: Node = main.area_loader.current_area
	var obj := area.get_node_or_null("DungeonObjective") as DungeonObjective
	var enemies := get_nodes_in_group("enemies").size()
	_check(area.name == "DungeonA", "(C) re-entry lands in DungeonA")
	_check(enemies == 7, "(C) re-entry DungeonA has its 7 enemies (3 + 2 slimes #392 + 2 Fishy #490) (got %d)" % enemies)
	_check(obj != null and obj.progress() == Vector2i(0, 7) and not obj.is_cleared(), "(C) re-entry objective is fresh 0/7 (2 Fishy, #490)")
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
	_check(main.area_loader.current_area.name == "Overworld", "(D) exit lands back in the overworld (#378)")
	_check(_near(_guards(main), main.area_loader.current_area.get_node("GateNormal").global_position, 200.0) == 0, "(D) DungeonA entrance stays unguarded")

	# (E) death restart forgets clears
	p.apply_damage(9999)
	for i in 600:
		await process_frame
		if current_scene != main and current_scene != null:
			break
	var fresh: Node = current_scene
	_check(fresh != main and fresh.area_loader.current_area.name == "Hub", "(E) death restarts the run in the hub")
	_check(fresh.cleared_dungeons.is_empty(), "(E) cleared dungeons reset with the run")
	fresh.area_loader.enter_overworld()
	await _frames(3)
	_check(_guards(fresh).size() == 29, "(E) every entrance is guarded again, all 29 (#414 + #490) (got %d)" % _guards(fresh).size())
	print("[348] DONE failures=", failures)
	if failures == 0:
		print("RESULT: ALL PASS")
	quit(1 if failures > 0 else 0)
