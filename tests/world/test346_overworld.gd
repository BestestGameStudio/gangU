extends SceneTree
## Core folded-world contract: physical entries, one instance per run,
## parked hub isolation, explicit Player wiring and bounded activation.
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
	var hub: Node = loader.current_area
	var gate := hub.get_node('GateOverworld') as Gate
	_check(gate.gate_type == Gate.GateType.TRAVEL, 'hub retains TRAVEL passage')
	gate._on_body_entered(p)
	await _frames(3)
	var ow := loader.current_area
	_check(ow.name == &'Overworld' and loader.regions.size() == FastTravelRoutes.DUNGEONS.size()+1, 'catalog physical regions and generated content mounted')
	var map := ow.get_node('Terrain') as TerrainMap
	for region in loader.regions:
		_check(region.layout != null and region.layout.get_node_or_null('ExitPortal') == null, 'region has layout, no exit portal: '+String(region.encounter_id))
		_check(map.is_walkable_at(region.entry), 'physical doorway is passable: '+String(region.encounter_id))
		for other in loader.regions:
			if other != region:
				_check(not region.bounds.intersects(other.bounds), 'region geometry does not overlap')
		p.global_position = region.entry
		loader.activation.update_now()
		_check(region.active, 'nearby region wakes: '+String(region.encounter_id))
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
	loader._load_hub()
	await _frames(2)
	_check(is_instance_valid(ow) and not (ow as Node2D).visible, 'hub parks existing overworld')
	var collisions_off := true
	for n in ow.find_children('*','CollisionObject2D',true,false):
		if n.collision_layer != 0 or n.collision_mask != 0: collisions_off = false
	_check(collisions_off, 'parked overworld has no collisions in hub')
	loader.enter_overworld()
	await _frames(2)
	_check(loader.current_area == ow and ow.get_node_or_null('RetainedRunMarker') == marker, 'hub trip retains exact region instances')
	_check(p.get_instance_id() == player_id and p.hp == 77, 'hub trip preserves player and HP')
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
	_check(active_count < loader.regions.size(), 'activation bounds awake regions near hub')
	_check(eligible > 0 and ticking * 2 <= eligible, 'most distant actors do not tick')
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
	_check(fresh != main and fresh.area_loader.current_area.name == &'Hub', 'full reset returns fresh run to hub')
	_check(not is_instance_id_valid(old_id) and fresh.area_loader.regions.is_empty(), 'full reset destroys cached world and region state')
	fresh.queue_free()
	await process_frame
	print('[world] ', checks, ' checks, failures=', failures)
	print('RESULT: ALL PASS' if failures == 0 else 'RESULT: FAIL')
	quit(1 if failures else 0)
