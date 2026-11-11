extends SceneTree
var pl: Player
func _initialize() -> void: _run.call_deferred()
func _wait(sec: float) -> void:
	var n := int(sec / 0.1)
	for i in n:
		if pl != null and is_instance_valid(pl): pl.hp = pl.max_hp
		await create_timer(0.1).timeout
func _run() -> void:
	var main: Node = load('res://game/core/main.tscn').instantiate()
	root.add_child(main)
	current_scene = main
	for i in 3: await physics_frame
	var loader: AreaLoader = main.area_loader
	pl = main.get_node('Player')
	var panel: Node = main.travel.get_node('FastTravelPanel')
	print('DEMO hub: FAST TRAVEL button visible = ', panel.get_node('OpenTravel').visible)
	await _wait(2.0)
	loader.enter_overworld()
	var region := loader.region_for(&'dungeon_a')
	pl.global_position = region.arrival
	await _wait(2.0)
	print('DEMO before clear: button visible = ', panel.get_node('OpenTravel').visible)
	for e in get_nodes_in_group('enemies'): e.queue_free()
	await _wait(0.5)
	for n in region.layout.get_children():
		if n.has_method('is_active') and n.call('is_active'):
			print('DBG active node ', n.name, ' ', n.get_script().resource_path)
			n.set('_active', false)
	loader.complete_encounter(&'dungeon_a')
	await _wait(0.5)
	main.travel.refresh()
	print('DBG enc=', loader.has_active_encounter())
	print('DEMO after clearing dungeon_a, standing in region: button visible = ', panel.get_node('OpenTravel').visible)
	await _wait(3.5)
	loader._load_hub()
	await _wait(0.5)
	main.travel.refresh()
	print('DEMO back in hub with cleared dungeon: button visible = ', panel.get_node('OpenTravel').visible)
	await _wait(2.5)
	quit(0)
