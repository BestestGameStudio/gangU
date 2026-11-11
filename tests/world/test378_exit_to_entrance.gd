extends SceneTree
## #378 harness (headless, production main.tscn + the real #346 overworld).
## Exiting a dungeon returns the player to THAT dungeon's overworld entrance:
##   (A) for every overworld dungeon gate, the exit portal lands in the
##       Overworld, standing Main.ENTRANCE_EXIT_OFFSET in front of (below)
##       the gate that leads into the dungeon just left
##   (B) the landing spot is outside the gate's footprint, so the player
##       stays in the overworld instead of being pulled straight back in
##   (C) HP and the SpellCaster instance carry through (same-run exit)
##   (D) a dungeon with no overworld entrance (fixture / direct swap) still
##       falls back to the hub
##   (E) the #349 fast-return shortcut is unchanged: it still goes to the hub
## Locked portals are opened with ExitPortal.unlock(); no kills are needed.

var failures := 0

const DUNGEON_GATES := {
	"GateNormal": "DungeonA",
	"GateRed": "DungeonB",
	"GateGenerated": "DungeonGenerated",
	"GateBoss": "DungeonC",
	"GateBeast": "DungeonD",
	"GateDefense": "DungeonE",
}

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[378] ", label, " -> ", "PASS" if ok else "FAIL")

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _initialize() -> void:
	Bestiary.save_path = "user://test378_bestiary.cfg" # keep the player's real record untouched
	var main: Node = (load("res://game/core/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(3)
	var p: Player = main.get_node("Player")
	var caster := p.get_node("SpellCaster")
	main.area_loader.enter_overworld()
	await _frames(3)
	_check(main.area_loader.current_area.name == "Overworld", "setup: in the overworld")

	for gate_name: String in DUNGEON_GATES:
		var gate: Gate = main.area_loader.current_area.get_node(gate_name)
		var gate_pos := gate.global_position
		p.hp = p.max_hp
		gate._on_body_entered(p)
		await _frames(3)
		var area: Node = main.area_loader.current_area
		var expected: String = DUNGEON_GATES[gate_name]
		var dname := String(area.name) # area is freed once we exit
		_check(dname == expected, "%s leads into %s (got %s)" % [gate_name, expected, dname])
		var portal := area.get_node_or_null("ExitPortal") as ExitPortal
		_check(portal != null, "%s: dungeon has an exit portal" % dname)
		if portal == null:
			continue
		if portal.locked:
			portal.unlock()
		p.hp = 77
		portal._on_body_entered(p)
		await _frames(3)
		var spot: Vector2 = gate_pos + main.area_loader.ENTRANCE_EXIT_OFFSET
		# (A)
		_check(main.area_loader.current_area.name == "Overworld", "(A) exiting %s returns to the overworld (got %s)" % [dname, main.area_loader.current_area.name])
		_check(p.global_position.distance_to(spot) < 4.0, "(A) exiting %s lands in front of %s (at %s, want %s)" % [dname, gate_name, p.global_position, spot])
		# (B)
		var gate_now: Gate = main.area_loader.current_area.get_node(gate_name)
		var half := ((gate_now.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D).size / 2.0
		_check(absf(p.global_position.y - gate_now.global_position.y) > half.y + 10.0, "(B) landing spot is clear of the %s footprint" % gate_name)
		# (C)
		_check(p.hp == 77 and p.get_node("SpellCaster") == caster, "(C) %s exit keeps HP and SpellCaster" % dname)
		await _frames(20)
		_check(main.area_loader.current_area.name == "Overworld", "(B) still in the overworld 20 frames after exiting %s" % dname)

	# (D) no overworld entrance -> hub fallback
	main.area_loader._exit_dungeon("res://game/enemies/spawners/wolf_cave.tscn")
	await _frames(3)
	_check(main.area_loader.current_area.name == "Hub", "(D) dungeon without an overworld entrance falls back to the hub")
	main.area_loader._exit_dungeon("")
	await _frames(3)
	_check(main.area_loader.current_area.name == "Hub", "(D) unknown dungeon falls back to the hub")

	# (E) fast return still goes to the hub
	main.area_loader.cleared_dungeons[&"dungeon_a"] = true
	main.area_loader.enter_overworld()
	await _frames(3)
	(main.area_loader.current_area.get_node("GateNormal") as Gate)._on_body_entered(p)
	await _frames(3)
	_check(main.area_loader.current_area.name == "DungeonA" and main.travel.can_fast_return(), "(E) cleared DungeonA re-entry can fast return")
	main.travel._request_fast_return()
	await _frames(3)
	_check(main.area_loader.current_area.name == "Hub", "(E) fast return still goes to the hub")

	print("[378] DONE failures=", failures)
	if failures == 0:
		print("RESULT: ALL PASS")
	quit(1 if failures > 0 else 0)
