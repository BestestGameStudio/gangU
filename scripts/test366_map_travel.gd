extends SceneTree
## #366: the map marks cleared dungeons and offers fast travel to a selected
## one. Production Main/areas; enemy kills are synthetic, travel goes through
## the real MapPanel -> Main path.
var failures := 0

func _check(ok: bool, label: String) -> void:
	print("[366 map travel] ", label, " -> ", "PASS" if ok else "FAIL")
	if not ok:
		failures += 1

func _frames(count: int = 3) -> void:
	for i in count:
		await physics_frame

func _initialize() -> void:
	_run.call_deferred()

func _click(canvas: MapCanvas, local: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = local
	canvas._gui_input(ev)
	var up := ev.duplicate() as InputEventMouseButton
	up.pressed = false
	canvas._gui_input(up)

func _kill_all() -> void:
	for i in 8: # A may roll RED and spawn the Warlord after its mobs die; #392 slimes split
		var alive := get_nodes_in_group("enemies").filter(func(n): return is_instance_valid(n) and not n.is_queued_for_deletion())
		if alive.is_empty() and i >= 2:
			break
		for enemy in alive:
			enemy.apply_damage(99999)
		await _frames()

func _run() -> void:
	Bestiary.save_path = "user://test366_bestiary.cfg"
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await _frames()
	var wm: WorldMap = main.get_node("WorldMap")
	var panel: MapPanel = main.get_node("MapPanel")
	var canvas := panel.canvas

	_check(FastTravelRoutes.id_for_scene("res://scenes/dungeon_a.tscn") == &"dungeon_a" and FastTravelRoutes.id_for_scene("res://scenes/hub.tscn") == &"", "scene -> dungeon id lookup")

	main.area_loader.enter_overworld()
	await _frames()
	var ow: StringName = main.area_loader.current_area.name
	var sites := wm.sites(ow)
	_check(sites.has(&"dungeon_a") and sites.has(&"dungeon_e") and sites.size() == 6, "overworld entrances recorded for the 6 catalog dungeons")
	_check((sites[&"dungeon_a"] as Vector2) == (main.area_loader.current_area.get_node("GateNormal") as Node2D).global_position, "site sits at its gate")
	_check((sites[&"dungeon_maze"] as Vector2) == (main.area_loader.current_area.get_node("GateMaze") as Node2D).global_position, "GateMaze site sits at its gate (#367)")
	_check(wm.cleared_sites(ow).is_empty(), "nothing cleared -> nothing marked (uncleared stays hidden)")
	panel.open()
	_check(canvas.site_at(canvas.world_to_screen(sites[&"dungeon_a"])) == &"", "uncleared entrance not selectable")
	panel.close()

	main.area_loader._on_gate_entered(main.area_loader.current_area.get_node("GateNormal"))
	await _frames()
	_check(not main.travel.can_map_travel_to(&"dungeon_a"), "uncleared dungeon not a destination")
	await _kill_all()
	_check(main.area_loader.is_cleared(&"dungeon_a"), "DungeonA cleared")
	_check(wm.cleared_sites(ow).keys() == [&"dungeon_a"], "cleared DungeonA now marked on the overworld map")
	_check(not main.travel.can_map_travel_to(&"dungeon_a"), "cannot map-travel to the dungeon you are in")

	# Go to an uncleared dungeon: map travel must not escape it.
	main.area_loader.enter_overworld()
	await _frames()
	main.area_loader._on_gate_entered(main.area_loader.current_area.get_node("GateBoss"))
	await _frames()
	_check(main.area_loader.current_area.name == "DungeonC", "in uncleared DungeonC")
	_check(not main.travel.can_map_travel_to(&"dungeon_a"), "origin inside an uncleared dungeon is refused")
	main.travel._request_map_travel(&"dungeon_a")
	await _frames()
	_check(main.area_loader.current_area.name == "DungeonC", "forced request from uncleared dungeon is rechecked and denied")

	main.area_loader._load_hub()
	await _frames()
	_check(main.area_loader.current_area.name == "Hub", "back in Hub")
	panel.open()
	_check(canvas.view() == &"Hub", "map opens on current area")
	_check(panel.world_view_id() == ow and panel._world_button.visible, "World toggle offered from the Hub")
	panel.toggle_world_view()
	_check(canvas.view() == ow, "World view shows the overworld")
	await process_frame
	var a_screen := canvas.world_to_screen(sites[&"dungeon_a"])
	_check(Rect2(Vector2.ZERO, canvas.size).has_point(a_screen), "marked DungeonA is on screen in World view")
	_click(canvas, a_screen)
	_check(canvas.selected_site == &"dungeon_a", "clicking the mark selects the dungeon")
	_check(wm.markers(ow).is_empty(), "selecting does not drop a tool mark")
	_check(panel._travel_button.visible and not panel._travel_button.disabled, "Travel enabled for the selection")
	var player: Player = main.get_node("Player")
	var hp := player.hp
	panel.request_travel()
	_check(not panel.visible, "Travel closes the map")
	await _frames()
	_check(main.area_loader.current_area.name == "DungeonA", "map travel mounts DungeonA")
	_check(main.get_node("Player") == player and player.hp == hp, "same Player and HP")
	_check(not main.area_loader.current_area.get_node("DungeonObjective").is_cleared(), "re-entry gets a fresh objective (same as #349)")

	# PR #371 review fix 1: map travel keeps the #349 Hub-spoke policy.
	# (a) No direct dungeon -> dungeon hop, even from a cleared dungeon.
	main.area_loader._load_hub()
	await _frames()
	main.area_loader.enter_overworld()
	await _frames()
	main.area_loader._on_gate_entered(main.area_loader.current_area.get_node("GateDefense"))
	await _frames()
	var defense := main.area_loader.current_area.get_node("DungeonObjective") as DungeonObjective
	while defense.waves_spawned() < defense.wave_count:
		defense.spawn_next_wave()
	await _frames(int(defense.wave_boss_delay * 60.0) + 4) # #368: final-wave boss arrives
	await _kill_all()
	_check(main.area_loader.is_cleared(&"dungeon_e"), "DungeonE cleared")
	_check(wm.cleared_sites(ow).size() == 2, "both cleared dungeons marked")
	_check(not main.travel.can_map_travel_to(&"dungeon_a"), "cleared dungeon -> other cleared dungeon refused (no direct hop)")
	main.travel._request_map_travel(&"dungeon_a")
	await _frames()
	_check(main.area_loader.current_area.name == "DungeonE", "forced dungeon -> dungeon request denied at commit")
	_check(main.travel.can_fast_return(), "#349 return-to-Hub path from a cleared dungeon still offered")

	# (b) No escape from the guarded, spawn-capable overworld.
	main.area_loader._load_hub()
	await _frames()
	main.area_loader.enter_overworld()
	await _frames()
	_check(not get_nodes_in_group("enemies").is_empty(), "overworld has live entrance guards")
	panel.open()
	_check(canvas.view() == ow and panel.world_view_id() == &"", "on the overworld, the map already shows the marks (no World toggle)")
	var rect := Rect2(Vector2.ZERO, canvas.size)
	var on_screen := true
	for d: StringName in wm.cleared_sites(ow):
		on_screen = on_screen and rect.has_point(canvas.world_to_screen(wm.cleared_sites(ow)[d]))
	on_screen = on_screen and rect.has_point(canvas.world_to_screen(main.get_node("Player").global_position))
	_check(on_screen and canvas.map_scale <= MapPanel.DEFAULT_SCALE, "view zooms out so every mark and the player fit")
	panel.select_dungeon(&"dungeon_e")
	_check(not panel.can_travel_selected() and panel._travel_button.disabled, "overworld -> DungeonE refused: Travel greyed out")
	var emitted := [0]
	var count_emit := func(_id: StringName) -> void: emitted[0] += 1
	panel.travel_requested.connect(count_emit)
	panel.request_travel()
	_check(emitted[0] == 0 and panel.visible, "Travel click from the overworld is refused at click time")
	panel.close()
	main.travel._request_map_travel(&"dungeon_e")
	await _frames()
	_check(main.area_loader.current_area.name == ow, "forced overworld -> dungeon request denied at commit")

	# (c) Click-time revalidation: a selection valid when made is re-asked on
	# the click, and the commit rechecks again.
	main.area_loader._load_hub()
	await _frames()
	panel.open()
	panel.toggle_world_view()
	panel.select_dungeon(&"dungeon_e")
	_check(panel.can_travel_selected(), "Hub -> DungeonE allowed")
	main.area_loader.cleared_dungeons.erase(&"dungeon_e") # synthetic invalidation after selecting
	panel.request_travel()
	_check(emitted[0] == 0 and panel.visible, "stale selection refused on the Travel click")
	_check(panel._travel_button.visible, "selection row still shown after refusal")
	panel._refresh()
	_check(panel._travel_button.disabled, "stale selection greys out Travel")
	panel.close()
	main.travel._request_map_travel(&"dungeon_e")
	await _frames()
	_check(main.area_loader.current_area.name == "Hub", "stale forced request denied at commit")
	panel.travel_requested.disconnect(count_emit)

	# PR #371 review fix 2: the World view draws the VIEWED area's terrain.
	main.area_loader.enter_overworld()
	await _frames()
	var probe := WorldMap.world_to_cell(main.get_node("Player").global_position)
	_check(wm.is_explored(ow, probe), "overworld probe cell explored")
	var ow_color := wm.cell_color(ow, probe)
	var ow_cells := {}
	for cell: Vector2i in wm.explored_cells(ow):
		ow_cells[cell] = wm.cell_color(ow, cell)
	main.area_loader._on_gate_entered(main.area_loader.current_area.get_node("GateGenerated"))
	await _frames()
	var gen_terrain := main.area_loader.current_area.get_node_or_null("Terrain") as TerrainMap
	_check(gen_terrain != null, "generated dungeon has a TerrainMap")
	var gen_color := WorldMap.terrain_color(gen_terrain, probe)
	_check(gen_color != ow_color, "generated dungeon colours that cell differently (test is meaningful)")
	panel.open()
	panel.toggle_world_view()
	_check(canvas.view() == ow, "World view from the generated dungeon shows the overworld")
	_check(wm.cell_color(ow, probe) == ow_color, "World view cell keeps the overworld's own colour")
	var same := true
	for cell: Vector2i in wm.explored_cells(ow):
		same = same and wm.cell_color(ow, cell) == ow_cells[cell]
	_check(same, "every explored overworld cell keeps its own colour in World view")
	panel.close()
	main.area_loader._load_hub()
	await _frames()
	_check(wm.cell_color(ow, probe) == ow_color, "overworld colours survive the generated dungeon being freed")

	main.area_loader.cleared_dungeons.clear()
	_check(wm.cleared_sites(ow).is_empty(), "marks follow the canonical clear record")

	main.queue_free()
	await _frames()
	var fresh: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(fresh)
	current_scene = fresh
	await _frames()
	var fwm: WorldMap = fresh.get_node("WorldMap")
	_check(fwm.areas_with_cleared_sites().is_empty(), "fresh run: no marked dungeons")

	print("[366 map travel] failures=", failures)
	print("RESULT: ALL PASS" if failures == 0 else "RESULT: FAIL")
	quit(1 if failures else 0)
