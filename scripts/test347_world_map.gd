extends SceneTree
## #347 harness: the M map. Explored terrain shows automatically (WorldMap
## explored set), details are never auto-shown (only player marks), and the
## map is drawable: freehand strokes, symbol markers, erase, provisional caps.
## Reveal TIMING is Colin's open call (ARCHITECTURE.md O7): production must
## ship with no reveal rule, and the harness drives the reveal seam itself.
##
## Optional: `-- --shots /tmp/ci/shots347` renders evidence PNGs (needs a
## real renderer, i.e. xvfb + opengl3, not --headless).

var _fails := 0
var _checks := 0
var _main: Node
var _shots_dir := ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		_shots_dir = args[i + 1]
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("[347] ", label, " -> ", "PASS" if ok else "FAIL")

func _click(canvas: MapCanvas, pos: Vector2, button: MouseButton, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = pos
	canvas._gui_input(ev)

func _move(canvas: MapCanvas, pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	canvas._gui_input(ev)

func _press_key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = true
	root.push_input(ev)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	root.push_input(up)

func _shot(name: String) -> void:
	if _shots_dir == "":
		return
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_shots_dir)
	img.save_png(_shots_dir.path_join(name + ".png"))
	print("[347] saved ", name)

func _finish() -> void:
	if is_instance_valid(_main):
		_main.queue_free()
		await process_frame
	print("test347 done: %d checks, %d failures" % [_checks, _fails])
	print("RESULT: ALL PASS" if _fails == 0 else "RESULT: FAIL")
	quit(0 if _fails == 0 else 1)

func _run() -> void:
	print("test347: overworld map reveal + player marks (#347)")
	_unit()
	await _production()
	await _finish()

## --- 1. WorldMap data contract, no tree ---
func _unit() -> void:
	var wm := WorldMap.new()
	var id := &"Area"
	_check(wm.explored_cells(id).is_empty() and wm.markers(id).is_empty() and wm.strokes(id).is_empty(), "fresh area is unexplored and unmarked")
	_check(not wm.reveal_rule.is_valid(), "no reveal rule by default (O7 open)")
	var cells := WorldMap.radius_cells(Vector2(96, 96), 2)
	_check(cells.has(Vector2i(1, 1)) and cells.has(Vector2i(3, 1)) and not cells.has(Vector2i(3, 3)), "radius_cells helper is a circle around the cell")
	_check(wm.reveal_cells(id, cells) == cells.size(), "reveal_cells adds new cells")
	_check(wm.reveal_cells(id, cells) == 0, "re-revealing is a no-op")
	_check(wm.is_explored(id, Vector2i(1, 1)) and not wm.is_explored(&"Other", Vector2i(1, 1)), "explored set is per area")
	# Reveal seam: a rule installed by whoever owns the decision is polled.
	wm.area_id = id
	var p := Node2D.new()
	p.position = Vector2(64 * 20 + 1, 1)
	wm.player = p
	wm.reveal_rule = func(pos: Vector2, _cs: int) -> Array: return [WorldMap.world_to_cell(pos)]
	wm._physics_process(0.0)
	_check(wm.is_explored(id, Vector2i(20, 0)), "an installed reveal_rule is applied each physics tick")
	wm.reveal_rule = Callable()
	# Markers + cap
	_check(wm.add_marker(id, Vector2(10, 10), WorldMap.Symbol.STAR), "marker placed")
	for i in WorldMap.MAX_MARKERS - 1:
		wm.add_marker(id, Vector2(1000 + i * 40, 1000), WorldMap.Symbol.CROSS)
	_check(wm.markers(id).size() == WorldMap.MAX_MARKERS and not wm.add_marker(id, Vector2(0, 0), WorldMap.Symbol.CROSS), "marker cap refuses extra markers")
	# Strokes + cap
	var s := wm.begin_stroke(id, Vector2(-500, -500))
	_check(s == 0 and wm.extend_stroke(id, s, Vector2(-400, -500)), "stroke started and extended")
	for i in WorldMap.MAX_STROKE_POINTS:
		wm.extend_stroke(id, s, Vector2(-400 + i, -500))
	_check((wm.strokes(id)[s] as PackedVector2Array).size() == WorldMap.MAX_STROKE_POINTS, "stroke point cap holds")
	for i in WorldMap.MAX_STROKES - 1:
		wm.begin_stroke(id, Vector2(5000, 5000 + i * 50))
	_check(wm.begin_stroke(id, Vector2(0, 9000)) == -1, "stroke cap refuses extra strokes")
	# Erase: hits a marker and a stroke segment (not just its points)
	_check(wm.erase_near(id, Vector2(12, 12), 5.0) == 1 and wm.markers(id).size() == WorldMap.MAX_MARKERS - 1, "erase removes the nearby marker only")
	_check(wm.erase_near(id, Vector2(-450, -498), 4.0) == 1 and wm.strokes(id).size() == WorldMap.MAX_STROKES - 1, "erase removes a stroke by segment proximity")
	_check(wm.erase_near(id, Vector2(-9999, -9999), 5.0) == 0, "erase with nothing near is a no-op")
	p.free()
	wm.free()

## --- 2. Production composition ---
func _production() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	for i in 3:
		await physics_frame
	var wm := _main.get_node_or_null("WorldMap") as WorldMap
	var panel := _main.get_node_or_null("MapPanel") as MapPanel
	_check(wm != null and panel != null, "main mounts WorldMap + MapPanel")
	if wm == null or panel == null:
		return
	_check(wm.area_id == &"Hub" and wm.player == _main.get_node("Player"), "WorldMap tracks the current area and player")
	_check(not wm.reveal_rule.is_valid() and wm.explored_cells(&"Hub").is_empty(), "production ships NO reveal rule: nothing auto-reveals (O7 open)")
	_check(InputMap.has_action(MapPanel.ACTION) and not panel.visible, "M action registered, map starts closed")

	_press_key(KEY_M)
	await process_frame
	_check(panel.visible and panel.is_in_group("modal_ui"), "M opens the map (modal_ui: clicks never cast)")

	# Stand-in reveal for evidence only (the rule itself is not decided):
	# reveal a patch around the hub spawn.
	var player := _main.get_node("Player") as Player
	wm.reveal_cells(&"Hub", WorldMap.radius_cells(player.global_position, 5))
	await _shot("347_map_explored_unmarked")

	var c := panel.canvas
	c.size = MapPanel.MAP_SIZE
	_check(c.screen_to_world(c.world_to_screen(Vector2(123, 456))).distance_to(Vector2(123, 456)) < 0.01, "canvas screen<->world round-trips")
	# Details are NOT auto-shown: gates exist in the hub but WorldMap holds no marks.
	_check(wm.markers(&"Hub").is_empty() and wm.strokes(&"Hub").is_empty(), "hub gates are not auto-marked")

	# Draw a freehand loop around the NORMAL gate.
	var gate := (_main.current_area.get_node("GateNormal") as Node2D).global_position
	panel.set_tool(MapCanvas.Tool.DRAW)
	var center := c.world_to_screen(gate)
	_click(c, center + Vector2(40, 0), MOUSE_BUTTON_LEFT, true)
	for k in range(1, 25):
		var a := TAU * k / 24.0
		_move(c, center + Vector2(cos(a), sin(a)) * 40.0)
	_click(c, center + Vector2(40, 0), MOUSE_BUTTON_LEFT, false)
	_check(wm.strokes(&"Hub").size() == 1 and (wm.strokes(&"Hub")[0] as PackedVector2Array).size() > 20, "LMB drag with Draw makes one freehand stroke")
	_move(c, center)
	_check((wm.strokes(&"Hub")[0] as PackedVector2Array).size() == 25, "mouse motion after release does not extend the stroke")

	# Markers: X on the red gate, star on the boss gate, triangle on the spawn.
	panel.set_symbol(WorldMap.Symbol.CROSS)
	_check(c.tool == MapCanvas.Tool.MARKER, "picking a symbol selects the Marker tool")
	_click(c, c.world_to_screen((_main.current_area.get_node("GateRed") as Node2D).global_position), MOUSE_BUTTON_LEFT, true)
	_click(c, Vector2.ZERO, MOUSE_BUTTON_LEFT, false)
	panel.set_symbol(WorldMap.Symbol.STAR)
	_click(c, c.world_to_screen((_main.current_area.get_node("GateBoss") as Node2D).global_position), MOUSE_BUTTON_LEFT, true)
	_click(c, Vector2.ZERO, MOUSE_BUTTON_LEFT, false)
	panel.set_symbol(WorldMap.Symbol.TRIANGLE)
	var tri_pos := c.world_to_screen(Vector2(576, 600))
	_click(c, tri_pos, MOUSE_BUTTON_LEFT, true)
	_click(c, tri_pos, MOUSE_BUTTON_LEFT, false)
	_check(wm.markers(&"Hub").size() == 3, "LMB with Marker places symbol markers")
	var red := (_main.current_area.get_node("GateRed") as Node2D).global_position
	_check((wm.markers(&"Hub")[0]["pos"] as Vector2).distance_to(red) < 1.0 and wm.markers(&"Hub")[0]["symbol"] == WorldMap.Symbol.CROSS, "marker stored at the clicked world position with its symbol")
	await _shot("347_map_player_marks")

	# RMB erases with any tool; Erase tool on LMB too.
	_click(c, tri_pos, MOUSE_BUTTON_RIGHT, true)
	_click(c, tri_pos, MOUSE_BUTTON_RIGHT, false)
	_check(wm.markers(&"Hub").size() == 2, "RMB erases a marker")
	panel.set_tool(MapCanvas.Tool.ERASE)
	_click(c, center + Vector2(-40, 0), MOUSE_BUTTON_LEFT, true)
	_click(c, center + Vector2(-40, 0), MOUSE_BUTTON_LEFT, false)
	_check(wm.strokes(&"Hub").is_empty(), "Erase tool removes the stroke")
	await _shot("347_map_after_erase")

	# Close with M; marks are per-area and survive a trip.
	_check(panel.visible, "map stays open while drawing")
	_press_key(KEY_M)
	await process_frame
	_check(not panel.visible and not panel.is_in_group("modal_ui"), "M closes the map")
	_main._swap(preload("res://scenes/dungeon_a.tscn").instantiate())
	await physics_frame
	_check(wm.area_id == &"DungeonA" and wm.markers(&"DungeonA").is_empty(), "dungeon has its own empty map")
	_main._swap(preload("res://scenes/hub.tscn").instantiate())
	await physics_frame
	_check(wm.area_id == &"Hub" and wm.markers(&"Hub").size() == 2 and wm.explored_cells(&"Hub").size() > 0, "hub marks + exploration survive leaving and returning")
	panel.open()
	_press_key(KEY_ESCAPE)
	await process_frame
	_check(not panel.visible, "Esc closes the map")
