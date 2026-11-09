extends SceneTree
## Production Main/areas. Enemy kills synthetic; travel uses real dispatch.
var failures := 0
func _check(ok: bool, label: String) -> void:
	print("[349 flow] ", label, " -> ", "PASS" if ok else "FAIL")
	if not ok:
		failures += 1
func _frames(count: int = 3) -> void:
	for i in count:
		await physics_frame
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	Bestiary.save_path = "user://test349_bestiary.cfg"
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await _frames()
	var player: Player = main.get_node("Player")
	_check(main.cleared_ids().is_empty(), "fresh canonical clear IDs empty")
	_check(not main._fast_travel._open_button.visible, "fresh hub no destination buttons")
	main._request_fast_travel(&"dungeon_a")
	await _frames()
	_check(main.current_area.name == "Hub", "uncleared route denied")
	main.enter_overworld()
	await _frames()
	_check(not main.can_fast_return(), "overworld with spawn capability cannot fast return")
	var gate: Gate = main.current_area.get_node("GateNormal")
	main._on_gate_entered(gate)
	await _frames()
	_check(not main.can_fast_return(), "uncleared current dungeon cannot fast return")
	var clears: Array[StringName] = []
	main.dungeon_cleared.connect(func(id: StringName): clears.append(id))
	for enemy in get_nodes_in_group("enemies"):
		enemy.apply_damage(99999)
	await _frames()
	# A may roll RED and spawn Warlord after mob kills.
	for enemy in get_nodes_in_group("enemies"):
		enemy.apply_damage(99999)
	await _frames()
	_check(main.is_cleared(&"dungeon_a") and clears == [&"dungeon_a"], "objective writes sole clear store and emits once")
	_check(main.can_fast_return(), "completed current visit can return")
	var hp := player.hp
	var wallet: Node = main.get_node("CurrencyWallet")
	main._request_fast_return()
	await _frames()
	_check(main.current_area.name == "Hub", "fast return reaches real Hub")
	_check(main.get_node("Player") == player and player.hp == hp, "same Player and HP retained")
	_check(main.get_node("CurrencyWallet") == wallet, "same run wallet retained")
	_check(main._fast_travel._rows.get_child_count() == 1, "hub offers one cleared destination")
	main._request_fast_travel(&"dungeon_a")
	await _frames()
	_check(main.current_area.name == "DungeonA", "hub shortcut mounts actual cleared DungeonA")
	_check(not get_nodes_in_group("enemies").is_empty(), "re-entry retains interior enemies")
	_check(not main.current_area.get_node("DungeonObjective").is_cleared(), "re-entry has fresh objective")
	_check(not main.can_fast_return(), "unresolved historical-clear shortcut is held")
	main._request_fast_travel(&"dungeon_b")
	await _frames()
	_check(main.current_area.name == "DungeonA", "direct dungeon-to-dungeon denied")
	main._load_hub()
	main.cleared_dungeons.clear() # synthetic death-state invalidation for stale click check
	main._request_fast_travel(&"dungeon_a")
	await _frames()
	_check(main.current_area.name == "Hub", "stale button selection revalidates empty record")
	main.queue_free()
	await _frames()
	var fresh: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(fresh)
	current_scene = fresh
	await _frames()
	_check(fresh.current_area.name == "Hub" and fresh.cleared_ids().is_empty() and not fresh._fast_travel._open_button.visible, "fresh Main resets travel with run")
	print("[349 flow] failures=", failures)
	quit(1 if failures else 0)
