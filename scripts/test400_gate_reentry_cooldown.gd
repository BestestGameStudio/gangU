extends SceneTree
## #400 harness (headless, production main.tscn + the real #346 overworld).
## Daniel 2026-11-09: "dungeon gates should temporarily disable (~1min)
## after clear so the player doesnt re-enter by accident". Pins:
##   (A) clearing DungeonA closes its overworld entrance GateNormal
##       (disabled flag, monitoring off)
##   (B) walking into the closed gate does NOT swap the area
##   (C) the other dungeon gates stay open
##   (D) the gate re-arms once the cooldown ends and entry works again
##   (E) deliberate fast travel (#349 hub panel) still reaches the cleared
##       dungeon during the cooldown - only walking in pauses
## The cooldown is shortened via main.gate_reentry_cooldown_seconds so the
## harness does not wait a real minute. Kills are synthetic apply_damage
## calls - NOT player combat proof (the PR's demo video carries that).
## #350 pin (labeled, same idiom as test9): GateNormal is pinned NORMAL and
## the run's cached roll overridden, because a RED-rolled GateNormal makes
## every DungeonA mount clear-or-die - its exit portal stays LOCKED until a
## fresh clear, and the fast-travel leg below exits without one. The roll
## itself is test350's scope; the RED locked-exit policy is production and
## intentionally untouched here.

var failures := 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[400] ", label, " -> ", "PASS" if ok else "FAIL")

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _enter(main: Node, gate_name: String) -> void:
	var gate: Gate = main.current_area.get_node(gate_name)
	if gate_name == "GateNormal":
		gate.gate_type = Gate.GateType.NORMAL # #350 pin (see header)
	gate._on_body_entered(main.get_node("Player"))
	await _frames(3)

func _initialize() -> void:
	Bestiary.save_path = "user://test400_bestiary.cfg" # keep the player's real record untouched
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(3)
	var p: Player = main.get_node("Player")
	main.gate_reentry_cooldown_seconds = 0.5 # shortened; production default is 60s
	_check(main.gate_reentry_cooldown_seconds == 0.5, "cooldown tunable set")

	# into the overworld, then clear DungeonA (same synthetic path as #348)
	await _enter(main, "GateOverworld")
	_check(main.current_area.name == "Overworld", "TRAVEL gate -> overworld")
	await _enter(main, "GateNormal")
	_check(main.current_area.name == "DungeonA", "GateNormal -> DungeonA")
	for e in get_nodes_in_group("enemies"):
		e.apply_damage(9999)
	await _frames(3)
	_check(main.cleared_dungeons.has(&"dungeon_a"), "DungeonA cleared")

	# exit portal -> back at the overworld entrance (#378)
	(main.current_area.get_node("ExitPortal") as ExitPortal)._on_body_entered(p)
	await _frames(3)
	_check(main.current_area.name == "Overworld", "exit portal returns to the overworld (#378)")
	var ow: Node = main.current_area
	var gate_normal: Gate = ow.get_node("GateNormal")
	var gate_red: Gate = ow.get_node("GateRed")

	# (A)
	_check(gate_normal.is_disabled(), "(A) cleared dungeon's gate is closed")
	_check(not gate_normal.monitoring, "(A) closed gate stops monitoring bodies")

	# (B) walking into the closed gate swaps nothing
	gate_normal._on_body_entered(p)
	await _frames(3)
	_check(main.current_area.name == "Overworld", "(B) closed gate ignores the player")

	# (C)
	_check(not gate_red.is_disabled() and gate_red.monitoring, "(C) uncleared DungeonB gate stays open")
	var gate_hub: Gate = ow.get_node("GateHub")
	_check(not gate_hub.is_disabled() and gate_hub.monitoring, "(C) TRAVEL gate is never closed")

	# (E) deliberate travel is unaffected: hub FAST TRAVEL still reaches the
	# cleared dungeon during the cooldown
	main._load_hub()
	await _frames(3)
	_check(main.current_area.name == "Hub", "(E) back in the hub")
	main._offering_rolls[&"GateNormal"] = Gate.GateType.NORMAL # #350 pin: fast travel reuses the cached roll
	main._commit_fast_travel(&"dungeon_a")
	await _frames(3)
	_check(main.current_area.name == "DungeonA", "(E) fast travel enters the cleared dungeon during the cooldown")
	(main.current_area.get_node("ExitPortal") as ExitPortal)._on_body_entered(p)
	await _frames(3)
	_check(main.current_area.name == "Overworld", "(E) exit portal back to the overworld")
	ow = main.current_area
	gate_normal = ow.get_node("GateNormal")

	# (D) cooldown expiry re-arms the gate (0.5s set before the clear)
	await create_timer(1.0).timeout
	await _frames(3)
	_check(not gate_normal.is_disabled(), "(D) gate re-arms after the cooldown")
	_check(gate_normal.monitoring, "(D) monitoring restored")
	p.global_position = (ow.get_node("PlayerSpawn") as Node2D).global_position
	await _enter(main, "GateNormal")
	_check(main.current_area.name == "DungeonA", "(D) entry works again after re-arming")

	print("[400] DONE failures=", failures)
	if failures == 0:
		print("RESULT: ALL PASS")
	quit(1 if failures > 0 else 0)
