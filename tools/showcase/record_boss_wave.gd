extends SceneTree
## RECORDING-ONLY showcase driver for #368 (not a test, not loaded by the game).
## Boots main.tscn, enters GateDefense (or GateMaze with --maze), clears the
## waves before the boss wave instantly, then spawns the boss wave and lets
## the Siege Brute march on the core with its wave. God-mode player, parked
## beside the core so the boss, its HP bar and the HUD wave bar are on screen.
## Usage:
##   godot --path . --write-movie out.png --fixed-fps 30 --quit-after 240 \
##         --script res://tools/showcase/record_boss_wave.gd [-- --maze]

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _initialize() -> void:
	var maze := "--maze" in OS.get_cmdline_user_args()
	if maze:
		MazeDefenseDungeon.forced_seed = 7
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	var p: Player = main.get_node("Player")
	p.max_hp = 100000
	p.hp = 100000
	main.enter_overworld()
	await _frames(4)
	var gate := main.current_area.get_node("GateMaze" if maze else "GateDefense") as Gate
	gate._on_body_entered(p)
	await _frames(4)
	var area: Node = main.current_area
	var obj := area.get_node("DungeonObjective") as DungeonObjective
	while obj.waves_spawned() < obj.total_waves() - 1:
		obj.spawn_next_wave()
		await _frames(1)
		for e in get_nodes_in_group(&"enemies"):
			if e.get_parent() == area:
				e.apply_damage(99999)
		await _frames(1)
	var core := obj.core()
	p.global_position = core.global_position + Vector2(90, 70)
	obj.spawn_next_wave()
	await _frames(int(obj.wave_boss_delay * 60.0) + 2) # 60 physics ticks/s
	print("[rec] boss wave %d spawned, bosses: %d" % [obj.waves_spawned(), obj.wave_bosses().size()])
	for b in obj.wave_bosses():
		b.apply_damage(60) # show a partly drained boss HP bar
	for i in 8:
		await _frames(30)
		for b in obj.wave_bosses():
			print("[rec] boss at ", b.global_position, " hp ", b.hp)
