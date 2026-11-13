extends SceneTree
## Core production movement contract: actual input crosses a hub TRAVEL
## passage and a region's physical doorway. Dungeon entry never swaps scenes
## or reconstructs the persistent player. No callback-only movement proof.
var failures := 0
func _check(ok: bool, text: String) -> void:
	if not ok: failures += 1
	print('[movement] ', text, ': ', ok)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var main: Node = load('res://game/core/main.tscn').instantiate()
	root.add_child(main)
	current_scene = main
	for i in 3: await physics_frame
	var p: Player = main.get_node('Player')
	var hub: Node = main.area_loader.current_area
	Input.action_press(&'move_up')
	for i in 120:
		await physics_frame
		if main.area_loader.current_area != hub: break
	Input.action_release(&'move_up')
	_check(main.area_loader.current_area.name == &'Overworld', 'actual input traverses hub TRAVEL passage')
	var ow: Node = main.area_loader.current_area
	var id := p.get_instance_id()
	_check(main.area_loader.regions.is_empty(), 'overworld mounts no dungeon regions (#643)')
	# Position only establishes the start of the walk, not its outcome.
	p.global_position = ow.get_node('PlayerSpawn').global_position
	var start := p.global_position
	Input.action_press(&'move_up')
	for i in 50: await physics_frame
	Input.action_release(&'move_up')
	_check(p.global_position.distance_to(start) > 96, 'actual input walks the overworld')
	_check(main.area_loader.current_area == ow and p.get_instance_id() == id, 'overworld walk does not swap world/player')
	_check(ow.find_children('*','ExitPortal',true,false).is_empty(), 'no dungeon exit portal in folded world')
	main.queue_free()
	await process_frame
	print('RESULT: ALL PASS' if failures == 0 else 'RESULT: FAIL')
	quit(1 if failures else 0)
