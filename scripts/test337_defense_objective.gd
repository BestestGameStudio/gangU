extends SceneTree
## #337 harness: DEFENSE objective - defend a DefenseCore through a fixed
## number of periodic waves; enemies use a mix of behaviour.
## Run: godot --headless --path . -s scripts/test337_defense_objective.gd
##
## Legs:
##   (A) dungeon_e.tscn: root DungeonE, PlayerSpawn, DefenseCore, WaveSpawns.
##   (B) overworld GateDefense -> DungeonE (NORMAL gate, label DEFENSE).
##   (C) production flow: DEFENSE objective dungeon_e mounted, no enemies before
##       the first wave, wave 1 spawns by itself after first_wave_delay with
##       wave_size(1) enemies, half of them aimed at the core (mixed).
##   (D) mixed targeting: a core attacker resolves the core, turns on the player
##       inside objective_aggro_range; a player hunter resolves the player.
##       A core attacker walks to the core and damages it.
##   (E) periodic: clearing a wave early brings the next after clear_break;
##       clearing every wave completes the objective (fixed count, no timer)
##       and the HUD row reads DEFEND n/n then COMPLETE; no wave beyond count.
##   (F) failure: core destroyed -> objective_failed, waves stop, never
##       completes, exit portal open, HUD reads FAILED.

var failures := 0

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[337] ", name, " -> PASS")
	else:
		failures += 1
		print("[337] ", name, " -> FAIL")

func _physics(n: int) -> void:
	for i in n:
		await physics_frame

func _initialize() -> void:
	Bestiary.save_path = "user://test337_bestiary.cfg"
	_leg_area()
	await _leg_overworld()
	await _leg_flow()
	await _leg_failure()
	print("[337] DONE failures=", failures)
	print("RESULT: ALL PASS" if failures == 0 else "RESULT: FAIL")
	quit(failures)

func _leg_area() -> void:
	var a: Node = (load("res://scenes/dungeon_e.tscn") as PackedScene).instantiate()
	_check(a.name == "DungeonE", "(A) root is named DungeonE")
	_check(a.get_node_or_null("PlayerSpawn") is Marker2D, "(A) PlayerSpawn marker")
	_check(a.get_node_or_null("DefenseCore") is DefenseCore, "(A) DefenseCore node")
	_check(a.get_node("WaveSpawns").get_child_count() >= 4, "(A) >= 4 wave spawn markers")
	_check(a.get_node_or_null("SpawnData") == null, "(A) no SpawnData: enemies come from waves")
	a.free()

func _leg_overworld() -> void:
	var ow: Node = (load("res://scenes/overworld.tscn") as PackedScene).instantiate()
	root.add_child(ow)
	await process_frame
	var g := ow.get_node_or_null("GateDefense") as Gate
	_check(g != null and g.gate_type == Gate.GateType.NORMAL and g.target_dungeon != null \
		and g.target_dungeon.resource_path == "res://scenes/dungeon_e.tscn", "(B) GateDefense is a NORMAL gate to DungeonE")
	if g != null:
		_check((g.get_node("TypeLabel") as Label).text == "DEFENSE", "(B) gate label reads DEFENSE")
		var ok := true
		for c in ow.get_children():
			if c != g and c is Gate and (c as Node2D).position.distance_to(g.position) < 200.0:
				ok = false
		_check(ok, "(B) >= 200px from every other gate")
		_check((ow.get_node("Ground") as OverworldGround).covers(g.position), "(B) overworld ground covers it")
	ow.queue_free()
	await process_frame

func _enter_defense(main: Node) -> void:
	main.enter_overworld()
	await _physics(4)
	var gate := main.current_area.get_node("GateDefense") as Gate
	gate._on_body_entered(main.get_node("Player"))
	await _physics(4)

func _wave_enemies(area: Node) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for e in get_nodes_in_group(&"enemies"):
		if e.get_parent() == area and (e as Enemy).hp > 0:
			out.append(e)
	return out

func _kill_all(area: Node) -> void:
	for e in _wave_enemies(area):
		e.apply_damage(99999)
	await _physics(2)

func _leg_flow() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	var p: Player = main.get_node("Player")
	p.max_hp = 100000
	p.hp = 100000
	await _enter_defense(main)
	var area: Node = main.current_area
	_check(area.name == "DungeonE", "(C) GateDefense enters DungeonE (got %s)" % area.name)
	var obj := area.get_node_or_null("DungeonObjective") as DungeonObjective
	_check(obj != null and obj.objective_type == DungeonObjective.ObjectiveType.DEFENSE and obj.dungeon_id == &"dungeon_e",
		"(C) DEFENSE objective dungeon_e mounted")
	if obj == null:
		main.queue_free()
		return
	var core := obj.core()
	_check(core != null and core.hp == core.max_hp and core.max_hp >= 500, "(C) core wired with a big HP pool (%d)" % (core.max_hp if core else -1))
	_check(obj.progress() == Vector2i(0, obj.wave_count) and obj.wave_count >= 3, "(C) progress 0/%d waves" % obj.wave_count)
	var portal := area.get_node_or_null("ExitPortal") as ExitPortal
	_check(portal != null and not portal.locked, "(C) normal gate: exit portal unlocked (retreat anytime)")
	_check(_wave_enemies(area).is_empty(), "(C) no enemies before the first wave")
	var hud := main.find_child("HUD", true, false)
	# Wave 1 arrives by itself after first_wave_delay.
	await _physics(int(obj.first_wave_delay * 60.0) + 10)
	var wave1 := _wave_enemies(area)
	_check(obj.waves_spawned() == 1 and wave1.size() == obj.wave_size(1), "(C) wave 1 spawned on its own with %d enemies (got %d)" % [obj.wave_size(1), wave1.size()])
	var attackers := wave1.filter(func(e: Enemy) -> bool: return e.objective_target == core)
	var hunters := wave1.filter(func(e: Enemy) -> bool: return e.objective_target == null)
	_check(attackers.size() >= 1 and hunters.size() >= 1, "(C) mixed wave: %d core attackers, %d player hunters" % [attackers.size(), hunters.size()])
	if hud != null:
		var label: Label = hud.get_node("Root/ObjectiveLabel")
		_check(label.visible and label.text.begins_with("Objective: DEFEND 0/%d" % obj.wave_count), "(C) HUD row: '%s'" % label.text)

	# (D) targeting
	if not attackers.is_empty() and not hunters.is_empty():
		var a: Enemy = attackers[0]
		var h: Enemy = hunters[0]
		p.global_position = Vector2(576, 2000) # far away
		_check(a._resolve_target() == core, "(D) core attacker targets the core")
		_check(h._resolve_target() == p, "(D) player hunter targets the player")
		p.global_position = a.global_position + Vector2(40, 0)
		_check(a._resolve_target() == p, "(D) core attacker turns on a nearby player")
		p.global_position = Vector2(576, 2000)
		_check(a._resolve_target() == core, "(D) ...and back to the core once the player leaves")
		# Let the attacker walk in and hit (no other enemies interfering).
		for e in wave1:
			if e != a:
				e.process_mode = Node.PROCESS_MODE_DISABLED
		var hp0 := core.hp
		await _physics(600)
		_check(core.hp < hp0, "(D) core attacker reaches and damages the core (%d -> %d)" % [hp0, core.hp])
		_check(a.global_position.distance_to(core.global_position) >= core.contact_radius - 4.0, "(D) attacker stops at the core rim")
		for e in wave1:
			e.process_mode = Node.PROCESS_MODE_INHERIT

	# (E) waves: clear early -> next after clear_break; fixed count.
	await _kill_all(area)
	_check(obj.progress().x == 1, "(E) clearing wave 1 counts 1 wave (got %d)" % obj.progress().x)
	await _physics(int(obj.clear_break * 60.0) + 10)
	_check(obj.waves_spawned() == 2 and _wave_enemies(area).size() == obj.wave_size(2), "(E) wave 2 follows after clear_break, bigger (%d)" % obj.wave_size(2))
	# periodic: without clearing, the next wave still comes after wave_interval
	await _physics(int(obj.wave_interval * 60.0) + 10)
	_check(obj.waves_spawned() == 3, "(E) wave 3 arrives on the periodic timer while wave 2 lives")
	while obj.waves_spawned() < obj.wave_count:
		obj.spawn_next_wave()
	# #368: the final wave's boss walks in wave_boss_delay after its wave.
	await _physics(int(obj.wave_boss_delay * 60.0) + 4)
	_check(not obj.is_cleared(), "(E) not complete while wave enemies live")
	await _kill_all(area)
	_check(obj.is_cleared() and not obj.is_failed(), "(E) all %d waves cleared -> objective complete" % obj.wave_count)
	_check(main.cleared_dungeons.has(&"dungeon_e"), "(E) dungeon_e recorded as cleared")
	await _physics(int(obj.wave_interval * 60.0) + 10)
	_check(obj.waves_spawned() == obj.wave_count and _wave_enemies(area).is_empty(), "(E) no wave beyond the fixed count")
	await _physics(20)
	if hud != null:
		_check((hud.get_node("Root/ObjectiveLabel") as Label).text == "Objective: COMPLETE", "(E) HUD row reads COMPLETE")
	main.queue_free()
	current_scene = null
	await process_frame

func _leg_failure() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	var p: Player = main.get_node("Player")
	p.max_hp = 100000
	p.hp = 100000
	# Enter as RED so the portal mounts locked: failure must still open it.
	main._entry_gate_type = Gate.GateType.RED
	main._swap((load("res://scenes/dungeon_e.tscn") as PackedScene).instantiate())
	main._entry_gate_type = Gate.GateType.RED
	await _physics(2)
	var area: Node = main.current_area
	var obj := area.get_node("DungeonObjective") as DungeonObjective
	var portal := area.get_node("ExitPortal") as ExitPortal
	_check(portal.locked, "(F) RED entry: portal locked while defending")
	obj.spawn_next_wave()
	await _physics(2)
	var failed := [false]
	obj.objective_failed.connect(func(_id: StringName) -> void: failed[0] = true)
	obj.core().apply_damage(999999)
	await _physics(30)
	_check(failed[0] and obj.is_failed() and obj.core().is_destroyed(), "(F) core destroyed -> objective_failed")
	_check(not portal.locked, "(F) failure opens the exit portal (no soft-lock)")
	var spawned := obj.waves_spawned()
	await _physics(int(obj.wave_interval * 60.0) + 10)
	_check(obj.waves_spawned() == spawned, "(F) no more waves after failure")
	await _kill_all(area)
	_check(not obj.is_cleared() and not main.cleared_dungeons.has(&"dungeon_e"), "(F) a failed defense never completes")
	var hud := main.find_child("HUD", true, false)
	if hud != null:
		_check((hud.get_node("Root/ObjectiveLabel") as Label).text.begins_with("Objective: FAILED"), "(F) HUD row reads FAILED")
	main.queue_free()
	current_scene = null
	await process_frame
