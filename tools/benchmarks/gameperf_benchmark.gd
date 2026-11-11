extends SceneTree
## Identical tool overlay on either commit. Not a gameplay test or perf gate.
const Probe = preload("res://game/core/game_perf_probe.gd")
var options := {}
var meta := {}
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair := arg.split("=", true, 1)
		if pair.size() == 2:
			options[pair[0]] = pair[1]
	_run.call_deferred()
func _frames(count: int) -> void:
	for i in count:
		await physics_frame
func _run() -> void:
	var selected := str(options.get("--workload", "A"))
	var seed_value := int(options.get("--seed", "548"))
	seed(seed_value)
	meta = Probe.metadata_from_args()
	meta.seed = seed_value
	meta.frame_schedule = "fixed-fps60: boot3 physics ticks; warm30; capture180; snapshot every30 process callbacks"
	meta["simulation_fixed_fps"] = 60
	meta["workload"] = selected
	meta["tool_overlay"] = "same benchmark/probe bytes copied to isolated project copies by runner"
	Bestiary.save_path = "user://gameperf_bestiary.cfg"
	var scope: Node
	var loader: Node = null
	var player: Player
	if selected == "A" or selected == "OFF" or selected == "ON":
		scope = load("res://game/core/main.tscn").instantiate()
		root.add_child(scope)
		current_scene = scope
		await _frames(3)
		loader = scope.get("area_loader")
		player = scope.get_node("Player")
		if selected == "OFF" or selected == "ON":
			meta["frame_schedule"] = "fixed-fps60: normal Main boot3 physics ticks, inspect opt-in bootstrap; no workload manipulation"
			var found := scope.get_node_or_null("GamePerfProbe") != null
			var result := {"metadata": meta, "probe_node_present": found, "probe_export_exists": FileAccess.file_exists("user://gameperf.json"), "main_child_names": []}
			for child in scope.get_children():
				result.main_child_names.append(str(child.name))
			if selected == "ON":
				if found:
					scope.get_node("GamePerfProbe").finish()
				print("GAMEPERF_ON_JSON ", JSON.stringify(result))
				quit(0 if found else 1)
			else:
				print("GAMEPERF_OFF_JSON ", JSON.stringify(result))
				quit(1 if found or result.probe_export_exists else 0)
			return
		loader.enter_overworld()
		meta["comparability"] = "A same arrival schedule but different entity counts/layouts; not matched combat; global seed does not override production-local RNG randomize() calls"
	else:
		scope = Node2D.new()
		scope.name = "IsolatedCommonSystems"
		root.add_child(scope)
		current_scene = scope
		player = load("res://game/player/player.tscn").instantiate()
		player.name = "Player"
		# Identical fixture endurance, not a change to production player stats.
		player.max_hp = 100000
		player.position = Vector2(576, 324)
		scope.add_child(player)
		player.damage_rng.seed = seed_value
		for i in 8:
			var enemy: Enemy = load("res://game/enemies/enemy.tscn").instantiate()
			enemy.name = "Enemy%d" % i
			enemy.player_path = NodePath("../Player")
			enemy.position = player.position + Vector2.RIGHT.rotated(TAU * i / 8.0) * 64.0
			scope.add_child(enemy)
			enemy.damage_rng.seed = seed_value + i + 1
		meta["comparability"] = "B isolated8 identical production contact enemies, no terrain, stationary production player with100000 fixture HP; same assets/positions/local damage RNG seeds. Not folded activation or representative browser combat. No kills/skips or performance assertion."
	await _frames(30)
	var hp_before := player.hp
	var probe := Probe.new()
	probe.name = "GamePerfProbe"
	scope.add_child(probe)
	probe.start(scope, loader, meta, 0)
	await _frames(180)
	meta["player_hp_before_capture"] = hp_before
	meta["player_hp_after_capture"] = player.hp
	probe.metadata = meta
	probe.finish()
	scope.queue_free()
	await process_frame
	quit()
