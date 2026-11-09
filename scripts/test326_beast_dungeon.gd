extends SceneTree
## #326 harness: the Beast boss (#174) gets its own arena, DungeonD, behind a
## fifth hub gate (GateBeast, BOSS type, label "BEAST").
## Run: godot --headless --path . --script res://scripts/test326_beast_dungeon.gd
##
## Legs:
##   (A) dungeon_d.tscn: root named DungeonD, PlayerSpawn marker, no SpawnData
##       (boss arena only).
##   (B) hub: GateBeast is a BOSS gate labelled BEAST targeting dungeon_d.tscn;
##       it sits off the x=576 spawn column (test106's sweep) and clear of
##       every other gate and hub prop.
##   (C) PRODUCTION flow (main.tscn): GateBeast -> DungeonD spawns the Beast
##       on entry (no mobs) wired to the Player; ELIMINATION objective; exit
##       portal LOCKED while it lives (entry ignored), unlocks when it dies,
##       returns to the hub. Kills are synthetic apply_damage calls.
##   (D) DungeonC is unchanged: GateBoss still leads to the Head boss.

var failures := 0

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[326] ", name, " -> PASS")
	else:
		failures += 1
		print("[326] ", name, " -> FAIL")

func _physics(n: int) -> void:
	for i in n:
		await physics_frame

func _initialize() -> void:
	await _leg_area()
	await _leg_hub()
	await _leg_production()
	await _leg_dungeon_c_unchanged()
	print("[326] DONE failures=", failures)
	print("RESULT: ALL PASS" if failures == 0 else "RESULT: FAIL")
	quit(failures)

# (A) -----------------------------------------------------------------------
func _leg_area() -> void:
	var ps: PackedScene = load("res://scenes/dungeon_d.tscn")
	_check(ps != null, "(A) dungeon_d.tscn loads")
	if ps == null:
		return
	var a := ps.instantiate()
	_check(a.name == "DungeonD", "(A) root is named DungeonD (main.gd matches on it)")
	_check(a.get_node_or_null("PlayerSpawn") is Marker2D, "(A) PlayerSpawn marker")
	_check(a.get_node_or_null("SpawnData") == null, "(A) no SpawnData: boss arena only")
	a.free()

# (B) -----------------------------------------------------------------------
func _leg_hub() -> void:
	var hub: Node = load("res://scenes/hub.tscn").instantiate()
	root.add_child(hub)
	await process_frame
	var g := hub.get_node_or_null("GateBeast") as Gate
	_check(g != null and g.gate_type == Gate.GateType.BOSS, "(B) GateBeast is a BOSS gate")
	if g != null:
		_check(g.target_dungeon != null and g.target_dungeon.resource_path == "res://scenes/dungeon_d.tscn",
			"(B) GateBeast targets DungeonD")
		_check((g.get_node("TypeLabel") as Label).text == "BEAST", "(B) gate label reads BEAST")
		_check(absf(g.position.x - 576.0) > 80.0, "(B) off the x=576 spawn column (test106 sweep)")
		var spawn := (hub.get_node("PlayerSpawn") as Node2D).position
		_check(g.position.distance_to(spawn) > 120.0, "(B) not on top of the player spawn")
		var ok := true
		for c in hub.get_children():
			if c == g or not (c is Node2D) or c.name == "PlayerSpawn":
				continue
			if (c is Gate or c.name in ["ShopVendor", "SpellDirectory", "BestiaryStation"]) and (c as Node2D).position.distance_to(g.position) < 120.0:
				ok = false
				print("[326]   too close to ", c.name)
		_check(ok, "(B) >= 120px from every other gate, the shop, the directory and the bestiary station")
	hub.queue_free()
	await process_frame

# (C) -----------------------------------------------------------------------
func _leg_production() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var p: Player = scene.get_node("Player")
	var gate := scene.current_area.get_node_or_null("GateBeast") as Gate
	_check(gate != null, "(C) production hub mounts GateBeast")
	if gate == null:
		scene.queue_free()
		return
	gate._on_body_entered(p)
	await _physics(6)
	var area: Node = scene.current_area
	_check(area.name == "DungeonD", "(C) GateBeast enters DungeonD (area=%s)" % area.name)
	var spawn := area.get_node("PlayerSpawn") as Node2D
	_check(p.global_position.distance_to(spawn.global_position) < 40.0, "(C) player placed at DungeonD's spawn")
	var bosses := get_nodes_in_group(&"boss")
	var boss: Enemy = bosses[0] if bosses.size() == 1 else null
	_check(boss != null and boss.get_parent() == area and boss._behavior is EnemyBehaviorBeast,
		"(C) the Beast boss spawns on entry (bosses=%d)" % bosses.size())
	var mobs := 0
	for e in get_nodes_in_group(&"enemies"):
		if e != boss:
			mobs += 1
	_check(mobs == 0, "(C) boss arena only: no mobs (got %d)" % mobs)
	_check(boss != null and boss._player == p, "(C) Beast wired to the production Player")
	var obj := area.get_node_or_null("DungeonObjective") as DungeonObjective
	_check(obj != null and obj.dungeon_id == &"dungeon_d" \
		and obj.objective_type == DungeonObjective.ObjectiveType.ELIMINATION \
		and obj.progress() == Vector2i(0, 1), "(C) ELIMINATION objective dungeon_d, target = the Beast")
	var portal := area.get_node_or_null("ExitPortal") as ExitPortal
	_check(portal != null and portal.locked, "(C) exit portal LOCKED while the Beast lives")
	if portal == null or boss == null:
		scene.queue_free()
		current_scene = null
		await process_frame
		return
	portal._on_body_entered(p)
	await _physics(4)
	_check(scene.current_area == area, "(C) locked portal entry ignored")
	boss.apply_damage(9999) # synthetic kill
	await _physics(4)
	_check(obj.is_cleared() and not portal.locked, "(C) Beast death clears the den and unlocks the portal")
	portal._on_body_entered(p)
	await _physics(4)
	_check(scene.current_area.name == "Hub", "(C) unlocked portal returns to the hub")
	scene.queue_free()
	current_scene = null
	await process_frame

# (D) -----------------------------------------------------------------------
func _leg_dungeon_c_unchanged() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var p: Player = scene.get_node("Player")
	var gate := scene.current_area.get_node_or_null("GateBoss") as Gate
	var had_gate := gate != null # the hub (and gate) is freed by the swap
	if had_gate:
		gate._on_body_entered(p)
		await _physics(6)
	var bosses := get_nodes_in_group(&"boss")
	var head: Enemy = bosses[0] if bosses.size() == 1 else null
	var is_head := false
	if head != null:
		is_head = head._behavior is EnemyBehaviorHead
	_check(had_gate and scene.current_area.name == "DungeonC" and is_head,
		"(D) GateBoss still leads to the Head boss in DungeonC (area=%s, bosses=%d)" % [scene.current_area.name, bosses.size()])
	scene.queue_free()
	current_scene = null
	await process_frame
