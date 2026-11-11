extends SceneTree
## Core defense integration contract, replacing the retired portal/objective
## assertions: physical location starts region-local waves, preserves mixed
## targeting and maze navigation, and finishes on waves or core destruction.
var failures := 0
func _check(ok: bool, text: String) -> void:
	if not ok: failures += 1
	print('[defense] ',text,': ',ok)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	for id in [&'dungeon_e', &'dungeon_maze']:
		var main: Node = load('res://game/core/main.tscn').instantiate()
		root.add_child(main)
		current_scene = main
		await process_frame
		var loader: AreaLoader = main.area_loader
		loader.enter_overworld()
		var region := loader.region_for(id)
		var host := region.layout.get_node('RegionEncounterHost') as RegionEncounterHost
		var d := host.defense
		_check(not d.is_active() and d.waves_spawned() == 0, 'idle before location entry: '+String(id))
		loader.player.global_position = region.arrival
		loader.activation.update_now()
		for i in 5: await physics_frame
		_check(d.is_active() and host.doors.all(func(door): return door.is_locked()), 'physical location starts and locks: '+String(id))
		d.set_physics_process(false) # deterministic wave timing, not disabled gameplay coverage
		d.spawn_next_wave()
		var wave := d._owned_enemies.duplicate()
		var attackers := 0
		for enemy in wave:
			if enemy.objective_target == d.defense_core: attackers += 1
		_check(wave.size() == d.wave_size(1) and attackers > 0 and attackers < wave.size(), 'wave composition and mixed targets')
		_check(wave.all(func(enemy): return enemy.terrain == region.terrain and enemy.get_node_or_null(enemy.player_path) == loader.player), 'shared physical terrain and explicit player wiring')
		_check(id != &'dungeon_maze' or wave.all(func(enemy): return enemy.nav == d.wave_nav and d.wave_nav != null), 'maze keeps existing FlowNav')
		for e in wave: e.apply_damage(999999)
		await process_frame
		_check(not loader.is_cleared(id), 'first wave does not clear full defense')
		for n in range(2,d.total_waves()+1):
			d.spawn_next_wave()
			d._tick_pending_bosses(d.wave_boss_delay + 1.0)
			for enemy in d._owned_enemies.duplicate():
				if is_instance_valid(enemy) and enemy.hp > 0: enemy.apply_damage(999999)
			await process_frame
		_check(d.is_cleared() and loader.is_cleared(id) and not host.is_active(), 'all waves and final bosses clear once')
		_check(host.doors.all(func(door): return not door.is_locked()), 'success opens physical doors')
		loader._load_hub()
		loader.enter_overworld()
		_check(region == loader.region_for(id) and not d.start(loader.player), 'same-run hub trip cannot restart completed defense')
		main.queue_free()
		await process_frame
	# A fresh run core failure is not a victory and cannot restart.
	var main: Node = load('res://game/core/main.tscn').instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	main.area_loader.enter_overworld()
	var r: OverworldRegion = main.area_loader.region_for(&'dungeon_e')
	var h := r.layout.get_node('RegionEncounterHost') as RegionEncounterHost
	main.area_loader.player.global_position = r.arrival
	main.area_loader.activation.update_now()
	for i in 5: await physics_frame
	h.defense.defense_core.apply_damage(999999)
	_check(h.defense.is_failed() and not h.is_active() and not main.area_loader.is_cleared(&'dungeon_e'), 'destroyed core ends without clear')
	_check(h.doors.all(func(door): return not door.is_locked()) and not h.defense.start(main.area_loader.player), 'core failure opens doors, stays inert')
	main.queue_free()
	await process_frame
	print('RESULT: ALL PASS' if failures == 0 else 'RESULT: FAIL')
	quit(1 if failures else 0)
