extends SceneTree
## Core hub-spoke travel contract after physical folding: cleared-route
## travel arrives in the existing overworld, never instantiates a dungeon.
## Cached region contents and player state survive hub round trips.
var failures := 0
func _check(ok: bool, text: String) -> void:
	if not ok: failures += 1
	print('[travel] ', text, ': ', ok)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var main: Node = load('res://game/core/main.tscn').instantiate()
	root.add_child(main)
	current_scene = main
	for i in 3: await physics_frame
	var loader: AreaLoader = main.area_loader
	var travel: TravelService = main.travel
	var p: Player = main.get_node('Player')
	_check(not travel.can_map_travel_to(&'dungeon_a'), 'uncleared route refused from hub')
	loader.enter_overworld()
	var ow := loader.current_area
	var region := loader.region_for(&'dungeon_a')
	var marker := Node.new()
	region.layout.add_child(marker)
	loader.complete_encounter(&'dungeon_a')
	_check(not travel.can_map_travel_to(&'dungeon_a'), 'map travel remains hub-origin only')
	p.global_position = region.arrival
	_check(travel.can_fast_return(), 'cleared physical region can return to hub')
	p.hp = 77
	var caster := p.get_node('SpellCaster')
	travel._commit_fast_return()
	_check(loader.current_area.name == &'Hub', 'cleared region returns to hub')
	_check(travel.can_map_travel_to(&'dungeon_a'), 'cleared route available from hub')
	travel._commit_map_travel(&'dungeon_a')
	_check(loader.current_area == ow and is_instance_valid(marker), 'route restores same world and region contents')
	_check(p.global_position == region.arrival, 'route lands at physical region arrival')
	_check(p.hp == 77 and p.get_node('SpellCaster') == caster, 'route preserves HP and spell caster')
	_check(loader.current_area.find_children('*','ExitPortal',true,false).is_empty(), 'physical routes create no exit portal')
	main.queue_free()
	await process_frame
	print('RESULT: ALL PASS' if failures == 0 else 'RESULT: FAIL')
	quit(1 if failures else 0)
