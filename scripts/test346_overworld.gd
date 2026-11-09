extends SceneTree
## #346 harness: the overworld between the hub and the dungeon entrances.
##   (A) hub: keeps its services (shop, spell directory, bestiary) and holds
##       ONE travel gate to the overworld - no dungeon gates any more.
##   (B) overworld scene: every dungeon entrance (A, B, generated, C) plus a
##       travel gate back to the hub; ground covers them, a road per gate,
##       decor kept off roads and gates.
##   (C) PRODUCTION flow: hub -> overworld spawns leashed guards around every
##       uncleared entrance; they hold their posts while the player is at the
##       arrival point.
##   (D) guard behavior: engages in range or when hit, gives up past the
##       leash and walks home.
##   (E) clearing DungeonA removes its entrance guards on the next overworld
##       visit (the others stay); the overworld -> hub gate works.
##   (F) a death restart forgets cleared dungeons (per-run state).

var failures := 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[346] ", label, " -> ", "PASS" if ok else "FAIL")

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
		if n is Enemy:
			out.append(n)
	return out

func _near(enemies: Array[Enemy], at: Vector2, r: float) -> int:
	var n := 0
	for e in enemies:
		if e.global_position.distance_to(at) <= r:
			n += 1
	return n

func _initialize() -> void:
	_scene_legs()
	await _flow_legs()
	print("[346] DONE failures=", failures)
	if failures == 0:
		print("RESULT: ALL PASS")
	quit(1 if failures > 0 else 0)

func _scene_legs() -> void:
	# (A) hub
	var hub: Node = load("res://scenes/hub.tscn").instantiate()
	var gates: Array[Gate] = []
	for c in hub.get_children():
		if c is Gate:
			gates.append(c)
	_check(gates.size() == 1, "(A) hub holds exactly one gate (got %d)" % gates.size())
	var travel := hub.get_node_or_null("GateOverworld") as Gate
	_check(travel != null and travel.gate_type == Gate.GateType.TRAVEL, "(A) hub GateOverworld is a TRAVEL gate")
	_check(travel != null and travel.target_path == "res://scenes/overworld.tscn" and travel.target_scene() != null, "(A) GateOverworld leads to the overworld")
	for svc in ["ShopVendor", "SpellDirectory", "BestiaryStation"]:
		_check(hub.get_node_or_null(svc) != null, "(A) hub keeps its %s" % svc)
	for old in ["GateNormal", "GateRed", "GateGenerated", "GateBoss"]:
		_check(hub.get_node_or_null(old) == null, "(A) %s moved out of the hub" % old)
	hub.free()

	# (B) overworld
	var ow: Node2D = load("res://scenes/overworld.tscn").instantiate()
	var expect := {
		"GateNormal": "res://scenes/dungeon_a.tscn",
		"GateRed": "res://scenes/dungeon_b.tscn",
		"GateGenerated": "res://scenes/dungeon_generated.tscn",
		"GateBoss": "res://scenes/dungeon_c.tscn",
	}
	for gname: String in expect:
		var g := ow.get_node_or_null(gname) as Gate
		_check(g != null and g.target_dungeon != null and g.target_dungeon.resource_path == expect[gname], "(B) overworld %s leads to %s" % [gname, expect[gname]])
	var back := ow.get_node_or_null("GateHub") as Gate
	_check(back != null and back.gate_type == Gate.GateType.TRAVEL and back.target_path == "res://scenes/hub.tscn", "(B) overworld GateHub is a TRAVEL gate back to the hub")
	_check(ow.get_node_or_null("PlayerSpawn") is Marker2D, "(B) overworld has a PlayerSpawn")
	_check(ow.get_node_or_null("SpawnData") == null, "(B) no area-wide SpawnData: enemies are per-entrance")
	var ground := ow.get_node("Ground") as OverworldGround
	ground.build_from(ow)
	var spawn: Vector2 = (ow.get_node("PlayerSpawn") as Node2D).position
	_check(ground.covers(spawn), "(B) ground covers the arrival point")
	_check(ground.roads.size() == 5, "(B) one road per gate (got %d)" % ground.roads.size())
	var far := 0.0
	for c in ow.get_children():
		if c is Gate:
			var at: Vector2 = (c as Node2D).position
			_check(ground.covers(at), "(B) ground covers %s %s" % [c.name, at])
			far = maxf(far, at.distance_to(spawn))
	_check(far > 1000.0, "(B) explorable: farthest entrance is %.0f px from the arrival point (> 1000)" % far)
	var decor_ok := true
	for d in ground.decor:
		if ground.road_distance(d["at"]) <= OverworldGround.ROAD_CLEAR:
			decor_ok = false
	_check(ground.decor.size() > 40 and decor_ok, "(B) %d decor pieces, none on a road" % ground.decor.size())
	var holder := ow.get_node_or_null("EntranceGuards")
	var ids := {}
	if holder:
		for g in holder.get_children():
			if g is EntranceGuards:
				ids[(g as EntranceGuards).dungeon_id] = (g as EntranceGuards).entries.size()
	_check(ids.has(&"dungeon_a") and ids.has(&"dungeon_b") and ids.has(&"dungeon_c") and ids.has(&""), "(B) guard sets for A, B, C and the generated entrance (%s)" % [ids])
	ow.free()

func _flow_legs() -> void:
	Bestiary.save_path = "user://test346_bestiary.cfg" # keep the player's real record untouched
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(3)
	var p: Player = main.get_node("Player")
	_check(main.current_area.name == "Hub", "(C) boots into the hub")
	await _enter(main, "GateOverworld")
	var ow: Node = main.current_area
	_check(ow.name == "Overworld", "(C) hub GateOverworld -> Overworld (got %s)" % ow.name)
	_check(p.global_position == (ow.get_node("PlayerSpawn") as Node2D).global_position, "(C) player placed at the overworld PlayerSpawn")
	var guards := _guards(main)
	_check(guards.size() == 11, "(C) 11 guards around the 4 uncleared entrances (got %d)" % guards.size())
	_check(guards.all(func(e: Enemy) -> bool: return e._behavior is EnemyBehaviorGuard), "(C) every guard runs the leashed guard behavior")
	_check(_near(guards, ow.get_node("GateNormal").global_position, 160.0) == 2, "(C) 2 guards posted at the DungeonA entrance")
	_check(_near(guards, ow.get_node("GateBoss").global_position, 180.0) == 4, "(C) 4 guards posted at the boss entrance")
	var posts := {}
	for e in guards:
		posts[e] = e.global_position
	await _frames(60)
	var still := true
	for e in guards:
		if e.global_position.distance_to(posts[e]) > 2.0:
			still = false
	_check(still, "(C) guards hold their posts while the player stands at the arrival point")
	_check(p.hp == p.max_hp, "(C) no damage taken at the arrival point (hp %d)" % p.hp)

	# (D) guard behavior
	var g0: Enemy = null
	for e in guards:
		if e.global_position.distance_to(ow.get_node("GateRed").global_position) < 160.0:
			g0 = e
			break
	p.global_position = g0.global_position + Vector2(0, -150) # north: the gate is south
	await _frames(30)
	_check((g0._behavior as EnemyBehaviorGuard).engaged, "(D) a guard engages a player inside its aggro radius")
	_check(g0.global_position.distance_to(posts[g0]) > 10.0, "(D) the engaged guard leaves its post to chase")
	p.global_position = posts[g0] + Vector2(0, 900)
	await _frames(6)
	_check(not (g0._behavior as EnemyBehaviorGuard).engaged, "(D) the guard gives up past its leash")
	await _frames(240)
	_check(g0.global_position.distance_to(posts[g0]) <= EnemyBehaviorGuard.HOME_EPSILON + 1.0, "(D) and walks back to its post (%.1f px off)" % g0.global_position.distance_to(posts[g0]))
	var g1: Enemy = null
	for e in guards:
		if e.global_position.distance_to(ow.get_node("GateBoss").global_position) < 180.0:
			g1 = e
			break
	# 350 px: outside AGGRO_RADIUS, inside LEASH_RADIUS (a ranged snipe).
	p.global_position = posts[g1] + Vector2(0, 350)
	await _frames(3)
	_check(not (g1._behavior as EnemyBehaviorGuard).engaged, "(D) a guard ignores a player outside its aggro radius")
	g1.apply_damage(1)
	await _frames(2)
	_check((g1._behavior as EnemyBehaviorGuard).engaged, "(D) a guard hit from beyond aggro range fights back")
	p.hp = p.max_hp

	# (E) clear DungeonA, its entrance guards are gone next visit
	p.global_position = (ow.get_node("PlayerSpawn") as Node2D).global_position
	await _enter(main, "GateNormal")
	_check(main.current_area.name == "DungeonA", "(E) overworld GateNormal -> DungeonA")
	for e in get_nodes_in_group("enemies"):
		e.apply_damage(999) # synthetic kills
	await _frames(3)
	_check(main.cleared_dungeons.has(&"dungeon_a"), "(E) clearing DungeonA records it as cleared")
	var portal: ExitPortal = main.current_area.get_node("ExitPortal")
	portal._on_body_entered(p)
	await _frames(3)
	_check(main.current_area.name == "Hub", "(E) the exit portal returns to the hub")
	await _enter(main, "GateOverworld")
	ow = main.current_area
	guards = _guards(main)
	_check(guards.size() == 9, "(E) 9 guards after clearing DungeonA (got %d)" % guards.size())
	_check(_near(guards, ow.get_node("GateNormal").global_position, 200.0) == 0, "(E) the cleared DungeonA entrance has no guards")
	_check(_near(guards, ow.get_node("GateRed").global_position, 160.0) == 2, "(E) the uncleared DungeonB entrance keeps its guards")
	await _enter(main, "GateHub")
	_check(main.current_area.name == "Hub", "(E) overworld GateHub -> Hub")
	_check(get_nodes_in_group("enemies").size() == 0, "(E) leaving the overworld frees its guards")

	# (F) death restart forgets cleared dungeons
	p.apply_damage(9999)
	for i in 600:
		await process_frame
		if current_scene != main and current_scene != null:
			break
	var fresh: Node = current_scene
	_check(fresh != main and fresh.current_area.name == "Hub", "(F) death restarts the run in the hub")
	_check(fresh.cleared_dungeons.is_empty(), "(F) cleared dungeons reset with the run")
	fresh.enter_overworld()
	await _frames(3)
	_check(_guards(fresh).size() == 11, "(F) every entrance is guarded again (got %d)" % _guards(fresh).size())
