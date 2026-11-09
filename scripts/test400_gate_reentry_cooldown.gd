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
##   (F) same close -> re-arm loop through a RED-rolled gate: the RED
##       clear-or-die exit portal stays locked until the fresh boss clear,
##       and that clear also starts the entrance-gate cooldown
## The cooldown is shortened via main.gate_reentry_cooldown_seconds so the
## harness does not wait a real minute. Kills are synthetic apply_damage
## calls - NOT player combat proof (the PR's demo video carries that).
## #350: the offering roll is pinned per leg (test9 idiom) so both the
## NORMAL and the RED path are covered deterministically; the roll itself
## is test350's scope and the RED clear-or-die policy is production,
## intentionally untouched. The 8-round kill loop drains #394 slime split
## descendants (same idiom as the current-main test348).

var failures := 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[400] ", label, " -> ", "PASS" if ok else "FAIL")

## Area-transition assertions: a failed one leaves every later lookup
## meaningless (null gate hangs), so bail out immediately.
func _require(ok: bool, label: String) -> void:
	_check(ok, label)
	if not ok:
		print("[400] DONE failures=", failures, " (bail)")
		quit(1)

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _enter(main: Node, gate_name: String, pin_type: int = -1) -> void:
	var gate: Gate = main.current_area.get_node(gate_name)
	if pin_type >= 0:
		gate.gate_type = pin_type # #350 pin, before entry (test9 idiom)
	gate._on_body_entered(main.get_node("Player"))
	await _frames(3)

## Kills everything alive, including #394 slime split descendants and a
## RED-rolled dungeon's boss, until the area is drained.
func _drain_enemies() -> void:
	for _round in 8:
		var alive := get_nodes_in_group("enemies").filter(func(n): return is_instance_valid(n) and not n.is_queued_for_deletion())
		if alive.is_empty():
			break
		for e in alive:
			e.apply_damage(9999)
		await _frames(3)

func _initialize() -> void:
	Bestiary.save_path = "user://test400_bestiary.cfg" # keep the player's real record untouched
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(3)
	var p: Player = main.get_node("Player")
	main.gate_reentry_cooldown_seconds = 0.5 # shortened; production default is 60s

	# into the overworld, then clear DungeonA through a NORMAL-pinned gate
	await _enter(main, "GateOverworld")
	_require(main.current_area.name == "Overworld", "TRAVEL gate -> overworld")
	main._offering_rolls[&"GateNormal"] = Gate.GateType.NORMAL # #350 pin: fresh gate instances read the cached roll
	await _enter(main, "GateNormal", Gate.GateType.NORMAL)
	_require(main.current_area.name == "DungeonA", "GateNormal -> DungeonA")
	_require(not (main.current_area.get_node("ExitPortal") as ExitPortal).locked, "NORMAL mount: exit portal unlocked")
	await _drain_enemies()
	_require(main.cleared_dungeons.has(&"dungeon_a"), "DungeonA cleared")

	# exit portal -> back at the overworld entrance (#378)
	(main.current_area.get_node("ExitPortal") as ExitPortal)._on_body_entered(p)
	await _frames(3)
	_require(main.current_area.name == "Overworld", "exit portal returns to the overworld (#378)")
	var ow: Node = main.current_area
	var gate_normal: Gate = ow.get_node("GateNormal")
	var gate_red: Gate = ow.get_node("GateRed")

	# (A)
	_check(gate_normal.is_disabled(), "(A) cleared dungeon's gate is closed")
	_check(not gate_normal.monitoring, "(A) closed gate stops monitoring bodies")

	# (B) walking into the closed gate swaps nothing
	gate_normal._on_body_entered(p)
	await _frames(3)
	_require(main.current_area.name == "Overworld", "(B) closed gate ignores the player")

	# (C)
	_check(not gate_red.is_disabled() and gate_red.monitoring, "(C) uncleared DungeonB gate stays open")
	var gate_hub: Gate = ow.get_node("GateHub")
	_check(not gate_hub.is_disabled() and gate_hub.monitoring, "(C) TRAVEL gate is never closed")

	# (E) deliberate travel is unaffected: hub FAST TRAVEL still reaches the
	# cleared dungeon during the cooldown
	main._load_hub()
	await _frames(3)
	_require(main.current_area.name == "Hub", "(E) back in the hub")
	main._commit_fast_travel(&"dungeon_a")
	await _frames(3)
	_require(main.current_area.name == "DungeonA", "(E) fast travel enters the cleared dungeon during the cooldown")
	(main.current_area.get_node("ExitPortal") as ExitPortal)._on_body_entered(p)
	await _frames(3)
	_require(main.current_area.name == "Overworld", "(E) exit portal back to the overworld")
	ow = main.current_area
	gate_normal = ow.get_node("GateNormal")

	# (D) cooldown expiry re-arms the gate (0.5s set before the clear)
	await create_timer(1.0).timeout
	await _frames(3)
	_check(not gate_normal.is_disabled(), "(D) gate re-arms after the cooldown")
	_check(gate_normal.monitoring, "(D) monitoring restored")
	p.global_position = (ow.get_node("PlayerSpawn") as Node2D).global_position
	await _enter(main, "GateNormal", Gate.GateType.NORMAL)
	_require(main.current_area.name == "DungeonA", "(D) entry works again after re-arming")

	# (F) RED-rolled gate: clear-or-die locked exit, and the boss clear
	# starts the cooldown too
	main._offering_rolls[&"GateNormal"] = Gate.GateType.RED
	(main.current_area.get_node("ExitPortal") as ExitPortal)._on_body_entered(p)
	await _frames(3)
	_require(main.current_area.name == "Overworld", "(F) back in the overworld")
	var gate_red_rolled: Gate = main.current_area.get_node("GateNormal")
	_check(gate_red_rolled.gate_type == Gate.GateType.RED, "(F) fresh gate instance rolled RED from the pinned cache")
	await _enter(main, "GateNormal", Gate.GateType.RED)
	_require(main.current_area.name == "DungeonA", "(F) RED gate -> RED DungeonA")
	var red_portal: ExitPortal = main.current_area.get_node("ExitPortal")
	_check(red_portal.locked, "(F) RED mount: exit portal locked (clear-or-die)")
	await _drain_enemies()
	_require(main.cleared_dungeons.has(&"dungeon_a"), "(F) RED DungeonA cleared")
	_check(not red_portal.locked, "(F) clear unlocks the RED exit portal")
	red_portal._on_body_entered(p)
	await _frames(3)
	_require(main.current_area.name == "Overworld", "(F) RED exit returns to the overworld")
	gate_normal = main.current_area.get_node("GateNormal")
	_check(gate_normal.is_disabled(), "(F) RED clear closes the entrance gate too")
	await create_timer(1.0).timeout
	await _frames(3)
	_check(not gate_normal.is_disabled(), "(F) gate re-arms after the RED cooldown")

	print("[400] DONE failures=", failures)
	if failures == 0:
		print("RESULT: ALL PASS")
	quit(1 if failures > 0 else 0)
