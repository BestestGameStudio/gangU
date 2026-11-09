extends SceneTree
## #368 harness: DEFENSE boss waves.
## Run: godot --headless --path . -s scripts/test368_boss_waves.gd
##
## Legs:
##   (A) defense_wave_boss.tscn: an Enemy with a BossHealthBar, a definition
##       far tougher than a regular wave enemy, and a bestiary boss entry.
##   (B) production DungeonE: the final wave is the boss wave (skull on the
##       HUD bar); waves before it spawn no boss.
##   (C) the boss wave spawns wave_size(n) enemies + one boss that walks in
##       wave_boss_delay later (inside the arena), joins the "boss" group,
##       goes for the core and is announced via boss_spawned.
##   (D) the boss marches on the core and damages it.
##   (E) the boss wave is not cleared while its boss lives; the boss kill
##       clears it and completes the defense.
##   (F) maze defense: the boss gets the area's FlowNav.
##   (G) no wave_boss_scene: a marked wave only marks (no boss spawns).
##   (H) killing a boss wave's regulars before the boss arrives does not
##       clear the wave; the boss kill does.

var failures := 0

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[368] ", name, " -> PASS")
	else:
		failures += 1
		print("[368] ", name, " -> FAIL")

func _physics(n: int) -> void:
	for i in n:
		await physics_frame

func _initialize() -> void:
	Bestiary.save_path = "user://test368_bestiary.cfg"
	await _leg_scene()
	await _leg_flow()
	await _leg_maze()
	await _leg_marker_only()
	await _leg_early_clear()
	print("[368] DONE failures=", failures)
	print("RESULT: ALL PASS" if failures == 0 else "RESULT: FAIL")
	quit(failures)

func _area_enemies(area: Node) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for e in get_nodes_in_group(&"enemies"):
		if e.get_parent() == area and (e as Enemy).hp > 0:
			out.append(e)
	return out

func _leg_scene() -> void:
	var b := (load("res://scenes/defense_wave_boss.tscn") as PackedScene).instantiate() as Enemy
	_check(b != null, "(A) defense_wave_boss.tscn root is an Enemy")
	if b == null:
		return
	root.add_child(b)
	await process_frame
	var regular := (load("res://scenes/enemy.tscn") as PackedScene).instantiate() as Enemy
	_check(b.get_node_or_null("HealthBar") is BossHealthBar, "(A) boss carries a BossHealthBar")
	_check(b.definition != null and b.max_hp >= regular.max_hp * 5, "(A) boss HP %d >> regular %d" % [b.max_hp, regular.max_hp])
	_check(b.contact_damage > regular.contact_damage, "(A) boss hits harder than a regular enemy")
	_check(b.definition.reward_table != null, "(A) boss drops from its definition table")
	var entry := Bestiary.catalog_entry(Bestiary.id_for_scene(b.scene_file_path))
	_check(not entry.is_empty() and entry.get("boss", false), "(A) bestiary lists the Siege Brute as a boss")
	regular.free()
	b.queue_free()
	await process_frame

func _enter(main: Node, gate_name: String) -> void:
	main.enter_overworld()
	await _physics(4)
	var gate := main.current_area.get_node(gate_name) as Gate
	gate._on_body_entered(main.get_node("Player"))
	await _physics(4)

func _new_main() -> Node:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	var p: Player = main.get_node("Player")
	p.max_hp = 100000
	p.hp = 100000
	return main

func _leg_flow() -> void:
	var main: Node = await _new_main()
	await _enter(main, "GateDefense")
	var area: Node = main.current_area
	var obj := area.get_node_or_null("DungeonObjective") as DungeonObjective
	_check(area.name == "DungeonE" and obj != null, "(B) GateDefense enters DungeonE with an objective")
	if obj == null:
		main.queue_free()
		await process_frame
		return
	var last := obj.total_waves()
	_check(obj.wave_boss_scene != null, "(B) Main sets a wave boss scene")
	_check(obj.boss_waves == [last], "(B) boss_waves = [%d] (final wave)" % last)
	await _physics(30)
	var bar := main.find_child("HUD", true, false).get_node("DefenseWaveBar") as DefenseWaveBar
	_check(bar.icon_kind(last) == "skull" and bar.icon_kind(1) == "enemy", "(B) HUD bar shows a skull on the final wave only")

	var spawned: Array = []
	obj.boss_spawned.connect(func(b: Node) -> void: spawned.append(b))
	# Clear waves 1..last-1 one by one: none of them brings a boss.
	var boss_early := false
	for w in range(1, last):
		obj.spawn_next_wave()
		await _physics(2)
		boss_early = boss_early or not obj.wave_bosses().is_empty()
		for e in _area_enemies(area):
			e.apply_damage(999999)
		await _physics(2)
	_check(not boss_early and spawned.is_empty(), "(B) waves 1..%d spawn no boss" % (last - 1))
	_check(obj.progress().x == last - 1, "(B) %d waves cleared before the boss wave" % (last - 1))

	# (C) the boss wave. The boss walks in wave_boss_delay after its wave.
	obj.spawn_next_wave()
	await _physics(2)
	_check(obj.wave_bosses().is_empty() and obj.pending_bosses() == 1, "(C) boss pending right after the wave starts")
	await _physics(int(obj.wave_boss_delay * 60.0) + 4)
	var all := _area_enemies(area)
	var bosses := obj.wave_bosses()
	_check(all.size() == obj.wave_size(last) + 1, "(C) boss wave: %d regular + 1 boss (got %d)" % [obj.wave_size(last), all.size()])
	_check(bosses.size() == 1 and spawned.size() == 1 and spawned[0] == bosses[0], "(C) one boss, announced through boss_spawned")
	if bosses.is_empty():
		main.queue_free()
		await process_frame
		return
	var boss := bosses[0]
	_check(boss.scene_file_path == "res://scenes/defense_wave_boss.tscn", "(C) boss is the Siege Brute")
	_check(boss.objective_target == obj.core(), "(C) boss goes for the core")
	var arena := Rect2(150, 84, 852, 572) # DungeonE's frame
	_check(arena.has_point(boss.position), "(C) boss arrived inside the arena at %s" % boss.position)

	# (E) regulars dead, boss alive -> wave not cleared.
	for e in _area_enemies(area):
		if e != boss:
			e.apply_damage(999999)
	await _physics(2)
	_check(obj.progress().x == last - 1 and not obj.is_cleared(), "(E) boss wave not cleared while the boss lives")

	# (D) the boss (alone now) walks to the core and hurts it. Keep the player
	# out of its aggro range so it sticks to the core.
	var p: Player = main.get_node("Player")
	p.global_position = obj.core().global_position + Vector2(0, 2000)
	var core := obj.core()
	var d0 := boss.global_position.distance_to(core.global_position)
	var hp0 := core.hp
	var hit := false
	for i in 900:
		await physics_frame
		if core.hp < hp0:
			hit = true
			break
	var d1 := boss.global_position.distance_to(core.global_position)
	_check(d1 < d0, "(D) boss closed in on the core (%.0f -> %.0f px)" % [d0, d1])
	_check(hit and hp0 - core.hp == boss.contact_damage, "(D) boss hit the core for its contact damage (%d -> %d)" % [hp0, core.hp])
	_check(not obj.is_failed() and not obj.is_cleared(), "(D) defense still running while the boss lives")
	_check(arena.has_point(boss.position), "(D) boss stayed inside the arena")
	boss.apply_damage(999999)
	await _physics(2)
	_check(obj.progress().x == last and obj.is_cleared(), "(E) boss kill clears the wave and completes the defense")
	main.queue_free()
	current_scene = null
	await process_frame

func _leg_maze() -> void:
	MazeDefenseDungeon.forced_seed = 7
	var main: Node = await _new_main()
	await _enter(main, "GateMaze")
	var area: Node = main.current_area
	var obj := area.get_node_or_null("DungeonObjective") as DungeonObjective
	_check(area.name == "DungeonMaze" and obj != null and obj.boss_waves == [obj.total_waves()], "(F) maze defense has a final boss wave")
	if obj != null:
		while obj.waves_spawned() < obj.total_waves():
			obj.spawn_next_wave()
		await _physics(int(obj.wave_boss_delay * 60.0) + 4)
		var bosses := obj.wave_bosses()
		_check(bosses.size() == 1 and bosses[0].nav != null and bosses[0].nav == obj.wave_nav, "(F) maze boss steers with the area's FlowNav")
	MazeDefenseDungeon.forced_seed = -1
	main.queue_free()
	current_scene = null
	await process_frame

func _leg_marker_only() -> void:
	var area := Node2D.new()
	area.name = "Area"
	var core := DefenseCore.new()
	core.name = "DefenseCore"
	area.add_child(core)
	var obj := DungeonObjective.new()
	obj.objective_type = DungeonObjective.ObjectiveType.DEFENSE
	obj.wave_count = 2
	obj.wave_base_size = 2
	obj.wave_size_growth = 0
	obj.first_wave_delay = 999.0
	obj.wave_enemy_scene = load("res://scenes/enemy.tscn")
	var bw: Array[int] = [1]
	obj.boss_waves = bw
	var pts: Array[Vector2] = [Vector2(300, 0)]
	obj.wave_spawn_points = pts
	area.add_child(obj)
	root.add_child(area)
	await process_frame
	obj.spawn_next_wave()
	await _physics(2)
	_check(_area_enemies(area).size() == 2 and obj.wave_bosses().is_empty() and obj.pending_bosses() == 0, "(G) marked wave without wave_boss_scene spawns no boss")
	area.queue_free()
	await process_frame

## (H) a boss wave cannot read cleared before its boss has arrived.
func _leg_early_clear() -> void:
	var area := Node2D.new()
	area.name = "Area"
	var core := DefenseCore.new()
	core.name = "DefenseCore"
	area.add_child(core)
	var obj := DungeonObjective.new()
	obj.objective_type = DungeonObjective.ObjectiveType.DEFENSE
	obj.wave_count = 1
	obj.wave_base_size = 2
	obj.first_wave_delay = 999.0
	obj.wave_enemy_scene = load("res://scenes/enemy.tscn")
	obj.wave_boss_scene = load("res://scenes/defense_wave_boss.tscn")
	var bw: Array[int] = [1]
	obj.boss_waves = bw
	var pts: Array[Vector2] = [Vector2(300, 0), Vector2(-300, 0)]
	obj.wave_spawn_points = pts
	area.add_child(obj)
	root.add_child(area)
	await process_frame
	obj.spawn_next_wave()
	await _physics(2)
	for e in _area_enemies(area):
		e.apply_damage(999999)
	await _physics(2)
	_check(not obj.is_cleared() and obj.pending_bosses() == 1, "(H) regulars dead before the boss arrives -> wave not cleared")
	await _physics(int(obj.wave_boss_delay * 60.0) + 4)
	var bosses := obj.wave_bosses()
	_check(bosses.size() == 1 and obj.pending_bosses() == 0, "(H) boss arrives after wave_boss_delay")
	for b in bosses:
		b.apply_damage(999999)
	await _physics(2)
	_check(obj.is_cleared(), "(H) boss kill then clears the wave")
	area.queue_free()
	await process_frame
