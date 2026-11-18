extends SceneTree
## Core folded-world contract: physical entries, one instance per run,
## outdoor hub services, explicit Player wiring and bounded activation.
## The performance sample is repeatable diagnostic output, not a claim
## about browser FPS on a developer laptop. Structural tick-budget guards
## are stable across CI machines; browser frame times are PR evidence.
var failures := 0
var checks := 0
func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print('[world] ', label, ' -> ', 'PASS' if ok else 'FAIL')
func _initialize() -> void:
	_run.call_deferred()
func _frames(n: int) -> void:
	for i in n: await physics_frame
func _run() -> void:
	Bestiary.save_path = 'user://world_contract_bestiary.cfg'
	var main: Node = load('res://game/core/main.tscn').instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(3)
	var loader: AreaLoader = main.area_loader
	var p: Player = main.get_node('Player')
	var player_id := p.get_instance_id()
	var ow := loader.current_area
	var hub := ow.get_node("HubServices") as HubServices
	_check(hub.contains_player(p.global_position), 'run starts beside the outdoor hub services')
	_check(ow.get_node_or_null("GateHub") == null and hub.get_node_or_null("GateOverworld") == null, 'hub has no teleport passage')
	_check(ow.name == &'Overworld' and loader.regions.is_empty(), 'overworld mounts no dungeon regions (#643)')
	var map := ow.get_node('Terrain') as TerrainMap
	# Walk each flight both ways using the same displacement checks as the player.
	for ends: Vector4 in [Vector4(1264, 1136, 1264, 976), Vector4(1392, 912, 1392, 752),
			Vector4(-656, 688, -656, 528)]:
		var lower := Vector2(ends.x, ends.y)
		var upper := Vector2(ends.z, ends.w)
		_check(TerrainMotion.clamp_displacement(map, lower, upper, false) == upper
			and TerrainMotion.clamp_displacement(map, upper, lower, false) == lower,
			'stairs at %s connect both landings' % lower)
		var foot := lower - Vector2(64, 0)
		_check(TerrainMotion.clamp_displacement(map, foot, upper - Vector2(64, 0), false).y > upper.y,
			'cliff beside %s blocks the climb' % lower)
	var enemy: Enemy
	for n in get_nodes_in_group('enemies'):
		if n is Enemy and ow.is_ancestor_of(n):
			enemy = n
			break
	_check(enemy != null and enemy.get_node_or_null(enemy.player_path) == p and enemy.terrain == map, 'spawn explicit player path and shared physical terrain')
	var marker := Node2D.new()
	marker.name = 'RetainedRunMarker'
	ow.add_child(marker)
	p.hp = 77
	var start := p.global_position
	Input.action_press("move_down")
	await _frames(50)
	Input.action_release("move_down")
	_check(p.global_position.y > start.y + 170.0 and not hub.contains_player(p.global_position), 'player walks out of the service clearing')
	_check(not main.travel._is_hub_area(), 'hub travel is unavailable outdoors')
	Input.action_press("move_up")
	await _frames(50)
	Input.action_release("move_up")
	_check(hub.contains_player(p.global_position) and main.travel._is_hub_area(), 'walking back inside restores hub travel')
	_check(loader.current_area == ow and ow.get_node_or_null('RetainedRunMarker') == marker, 'walking through hub retains exact world instance')
	_check(p.get_instance_id() == player_id and p.hp == 77, 'hub visit preserves player and HP')
	_check(hub.get_node_or_null("ShopVendor") != null and hub.get_node_or_null("SpellDirectory") != null and hub.get_node_or_null("BestiaryStation") != null, 'all three services share the outdoor clearing')
	p.global_position = ow.get_node('PlayerSpawn').global_position
	loader.activation.update_now()
	var active_count := 0
	var eligible := 0
	var ticking := 0
	for r in loader.regions:
		if r.active: active_count += 1
	for n in get_nodes_in_group('enemies'):
		if ow.is_ancestor_of(n):
			eligible += 1
			if n.can_process(): ticking += 1
	_check(active_count == 0, 'no regions to wake (#643)')
	_check(eligible > 0 and ticking == eligible, 'always-on overworld cast ticks (#643)')
	print('[world-perf] nodes=', get_node_count(), ' enemies=', eligible, ' ticking=', ticking, ' regions_awake=', active_count)
	var samples: Array[int] = []
	var last := Time.get_ticks_usec()
	for i in 120:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(now-last)
		last = now
	samples.sort()
	print('[world-perf] frame-cadence-us p50=', samples[60], ' p90=', samples[108], ' headless, not browser FPS')
	# Full reload is the death-reset path. No cached region may survive it.
	var old_id := ow.get_instance_id()
	reload_current_scene()
	await _frames(5)
	var fresh := current_scene
	_check(fresh != main and fresh.area_loader.current_area.name == &'Overworld' and fresh.area_loader.current_area.get_node('HubServices').contains_player(fresh.get_node('Player').global_position), 'full reset returns fresh run to hub')
	_check(not is_instance_id_valid(old_id) and fresh.area_loader.regions.is_empty(), 'full reset destroys cached world and region state')
	fresh.queue_free()
	await process_frame
	print('[world] ', checks, ' checks, failures=', failures)
	print('RESULT: ALL PASS' if failures == 0 else 'RESULT: FAIL')
	quit(1 if failures else 0)
