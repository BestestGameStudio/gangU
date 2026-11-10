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

func _move(canvas: MapCanvas, pos: Vector2, mask: int = 0) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.button_mask = mask
	canvas._gui_input(ev)

## --- real viewport routing (PR #355 review): events go through root.push_input
## and the GUI's own hit-test / mouse-focus logic, not straight into _gui_input.
func _vp_pos(canvas: MapCanvas, local: Vector2) -> Vector2:
	return canvas.get_global_transform_with_canvas() * local

func _vp_button(canvas: MapCanvas, local: Vector2, button: MouseButton, pressed: bool, mask: int) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.button_mask = mask
	ev.position = _vp_pos(canvas, local)
	ev.global_position = ev.position
	root.push_input(ev, true) # already in viewport (content) coords; headless window is 64x64 stretched

func _vp_motion(canvas: MapCanvas, from_local: Vector2, to_local: Vector2, mask: int) -> void:
	var ev := InputEventMouseMotion.new()
	ev.button_mask = mask
	ev.position = _vp_pos(canvas, to_local)
	ev.global_position = ev.position
	ev.relative = to_local - from_local
	root.push_input(ev, true)

func _stroke_len(wm: WorldMap, id: StringName, i: int) -> int:
	var s: Array = wm.strokes(id)
	return (s[i] as PackedVector2Array).size() if i < s.size() else -1

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
	_check(not wm.reveal_rule.is_valid(), "bare WorldMap ships no rule (production wires it at mount)")
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
	_check(wm.reveal_rule.is_valid(), "production wires a reveal rule (Colin: terrain appears as you explore)")
	_check(wm.reveal_rule.get_method() == &"explore_rule", "the production rule is WorldMap.explore_rule")
	# Explore reveal in production: the player's own hub cell (and its
	# vision circle) is explored after ticks; far cells stay fogged.
	for i in 3:
		await physics_frame
	var hub_player := (_main.get_node("Player") as Node2D).global_position
	_check(wm.is_explored(&"Hub", WorldMap.world_to_cell(hub_player)), "player's own cell explored by the explore rule")
	_check(not wm.is_explored(&"Hub", WorldMap.world_to_cell(hub_player) + Vector2i(WorldMap.EXPLORE_RADIUS_CELLS + 3, 0)), "cells beyond the vision circle stay fogged")
	_check(InputMap.has_action(MapPanel.ACTION) and not panel.visible, "M action registered, map starts closed")

	_press_key(KEY_M)
	await process_frame
	_check(panel.visible and panel.is_in_group("modal_ui"), "M opens the map (modal_ui: clicks never cast)")

	await _shot("347_production_explore_reveal") # production explore reveal: vision circle explored
	# A second explored patch further out, as if the player had walked there.
	var player := _main.get_node("Player") as Player
	wm.reveal_cells(&"Hub", WorldMap.radius_cells(player.global_position + Vector2(64 * 8, 0), WorldMap.EXPLORE_RADIUS_CELLS))
	await _shot("347_map_explored_unmarked")

	var c := panel.canvas
	c.size = MapPanel.MAP_SIZE
	_check(c.screen_to_world(c.world_to_screen(Vector2(123, 456))).distance_to(Vector2(123, 456)) < 0.01, "canvas screen<->world round-trips")
	# Details are NOT auto-shown: gates exist in the hub but WorldMap holds no marks.
	_check(wm.markers(&"Hub").is_empty() and wm.strokes(&"Hub").is_empty(), "hub gates are not auto-marked")

	# Draw a freehand loop around the overworld gate.
	var gate := (_main.area_loader.current_area.get_node("GateOverworld") as Node2D).global_position
	panel.set_tool(MapCanvas.Tool.DRAW)
	var center := c.world_to_screen(gate)
	_click(c, center + Vector2(40, 0), MOUSE_BUTTON_LEFT, true)
	for k in range(1, 25):
		var a := TAU * k / 24.0
		_move(c, center + Vector2(cos(a), sin(a)) * 40.0, MOUSE_BUTTON_MASK_LEFT)
	_click(c, center + Vector2(40, 0), MOUSE_BUTTON_LEFT, false)
	_check(wm.strokes(&"Hub").size() == 1 and (wm.strokes(&"Hub")[0] as PackedVector2Array).size() > 20, "LMB drag with Draw makes one freehand stroke")
	_move(c, center)
	_check((wm.strokes(&"Hub")[0] as PackedVector2Array).size() == 25, "mouse motion after release does not extend the stroke")

	# Markers: X on the overworld gate, star on the shop, triangle on the spawn.
	panel.set_symbol(WorldMap.Symbol.CROSS)
	_check(c.tool == MapCanvas.Tool.MARKER, "picking a symbol selects the Marker tool")
	_click(c, c.world_to_screen((_main.area_loader.current_area.get_node("GateOverworld") as Node2D).global_position), MOUSE_BUTTON_LEFT, true)
	_click(c, Vector2.ZERO, MOUSE_BUTTON_LEFT, false)
	panel.set_symbol(WorldMap.Symbol.STAR)
	_click(c, c.world_to_screen((_main.area_loader.current_area.get_node("ShopVendor") as Node2D).global_position), MOUSE_BUTTON_LEFT, true)
	_click(c, Vector2.ZERO, MOUSE_BUTTON_LEFT, false)
	panel.set_symbol(WorldMap.Symbol.TRIANGLE)
	var tri_pos := c.world_to_screen(Vector2(576, 600))
	_click(c, tri_pos, MOUSE_BUTTON_LEFT, true)
	_click(c, tri_pos, MOUSE_BUTTON_LEFT, false)
	_check(wm.markers(&"Hub").size() == 3, "LMB with Marker places symbol markers")
	var oworld := (_main.area_loader.current_area.get_node("GateOverworld") as Node2D).global_position
	_check((wm.markers(&"Hub")[0]["pos"] as Vector2).distance_to(oworld) < 1.0 and wm.markers(&"Hub")[0]["symbol"] == WorldMap.Symbol.CROSS, "marker stored at the clicked world position with its symbol")
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
	_main.area_loader._swap(preload("res://scenes/dungeon_a.tscn").instantiate())
	await physics_frame
	_check(wm.area_id == &"DungeonA" and wm.markers(&"DungeonA").is_empty(), "dungeon has its own empty map")
	_main.area_loader._swap(preload("res://scenes/hub.tscn").instantiate())
	await physics_frame
	_check(wm.area_id == &"Hub" and wm.markers(&"Hub").size() == 2 and wm.explored_cells(&"Hub").size() > 0, "hub marks + exploration survive leaving and returning")
	panel.open()
	_press_key(KEY_ESCAPE)
	await process_frame
	_check(not panel.visible, "Esc closes the map")

	await _routed_interaction(wm, panel)
	await _death_reset(wm)

## --- 3. Viewport-routed drag lifecycle (PR #355 review: ghost stroke) ---
func _routed_interaction(wm: WorldMap, panel: MapPanel) -> void:
	var c := panel.canvas
	var L := MOUSE_BUTTON_MASK_LEFT
	var R := MOUSE_BUTTON_MASK_RIGHT
	# Headless has no OS cursor, so tell the root window the mouse is inside it
	# (what DisplayServer does on a real desktop) or the GUI ignores the mouse.
	root.notification(Window.NOTIFICATION_WM_MOUSE_ENTER)
	panel.open()
	await process_frame
	_check(c.get_global_rect().has_point(_vp_pos(c, Vector2(300, 200))), "canvas is laid out where routed clicks land")
	panel.set_tool(MapCanvas.Tool.DRAW)
	var n0 := wm.strokes(&"Hub").size()

	# Positive control: a real held drag draws through the viewport.
	_vp_button(c, Vector2(100, 100), MOUSE_BUTTON_LEFT, true, L)
	_vp_motion(c, Vector2(100, 100), Vector2(160, 100), L)
	_vp_button(c, Vector2(160, 100), MOUSE_BUTTON_LEFT, false, 0)
	await process_frame
	_check(wm.strokes(&"Hub").size() == n0 + 1 and _stroke_len(wm, &"Hub", n0) == 2, "routed held drag draws a 2-point stroke")
	_vp_motion(c, Vector2(160, 100), Vector2(260, 160), 0)
	await process_frame
	_check(_stroke_len(wm, &"Hub", n0) == 2, "routed hover after release does not extend")

	# Reviewer repro: press, move, M while held, release while hidden, reopen, hover.
	_vp_button(c, Vector2(300, 200), MOUSE_BUTTON_LEFT, true, L)
	_vp_motion(c, Vector2(300, 200), Vector2(340, 200), L)
	await process_frame
	var ghost := n0 + 1
	_check(_stroke_len(wm, &"Hub", ghost) == 2 and c.is_interacting(), "repro: stroke in progress with LMB held")
	_press_key(KEY_M)
	await process_frame
	_check(not panel.visible and not c.is_interacting(), "closing mid-drag drops the drag state")
	_vp_button(c, Vector2(340, 200), MOUSE_BUTTON_LEFT, false, 0)
	await process_frame
	_press_key(KEY_M)
	await process_frame
	_check(panel.visible, "map reopened")
	_vp_motion(c, Vector2(340, 200), Vector2(530, 290), 0)
	await process_frame
	_check(_stroke_len(wm, &"Hub", ghost) == 2 and wm.strokes(&"Hub").size() == n0 + 2, "repro: hover after close/release/reopen adds NO phantom segment")
	await _shot("347_repro_no_phantom_segment")
	# Even a held-button motion with no fresh press must not resume the old stroke.
	_vp_motion(c, Vector2(530, 290), Vector2(560, 300), L)
	await process_frame
	_check(_stroke_len(wm, &"Hub", ghost) == 2, "held motion without a new press does not resume the old stroke")

	# Missed release while still open: motion whose mask lacks LMB ends the drag.
	_vp_button(c, Vector2(100, 300), MOUSE_BUTTON_LEFT, true, L)
	await process_frame
	var lost := n0 + 2
	_vp_motion(c, Vector2(100, 300), Vector2(200, 300), 0)
	_vp_motion(c, Vector2(200, 300), Vector2(260, 330), L)
	await process_frame
	_check(_stroke_len(wm, &"Hub", lost) == 1 and not c.is_interacting(), "motion without the drag's button cancels it (no draw)")

	# Erasing: markers to aim at, then hover/ghost attempts, then a positive control.
	panel.set_symbol(WorldMap.Symbol.CIRCLE)
	for p in [Vector2(600, 100), Vector2(700, 100), Vector2(800, 100)]:
		_vp_button(c, p, MOUSE_BUTTON_LEFT, true, L)
		_vp_button(c, p, MOUSE_BUTTON_LEFT, false, 0)
	await process_frame
	var m0 := wm.markers(&"Hub").size()
	var s0 := wm.strokes(&"Hub").size()
	panel.set_tool(MapCanvas.Tool.ERASE)
	_vp_motion(c, Vector2(560, 100), Vector2(600, 100), 0)
	await process_frame
	_check(wm.markers(&"Hub").size() == m0, "Erase tool: plain hover over a marker erases nothing")
	# LMB erase drag, closed mid-drag, released hidden, reopened, hovered.
	_vp_button(c, Vector2(600, 250), MOUSE_BUTTON_LEFT, true, L)
	await process_frame
	_press_key(KEY_M)
	await process_frame
	_vp_button(c, Vector2(600, 250), MOUSE_BUTTON_LEFT, false, 0)
	_press_key(KEY_M)
	await process_frame
	_vp_motion(c, Vector2(600, 250), Vector2(600, 100), 0)
	await process_frame
	_check(wm.markers(&"Hub").size() == m0, "LMB erase: close/release/reopen hover erases nothing")
	# RMB erase drag (any tool), same lifecycle.
	panel.set_tool(MapCanvas.Tool.DRAW)
	_vp_button(c, Vector2(700, 250), MOUSE_BUTTON_RIGHT, true, R)
	await process_frame
	_press_key(KEY_M)
	await process_frame
	_vp_button(c, Vector2(700, 250), MOUSE_BUTTON_RIGHT, false, 0)
	_press_key(KEY_M)
	await process_frame
	_vp_motion(c, Vector2(700, 250), Vector2(700, 100), 0)
	await process_frame
	_check(wm.markers(&"Hub").size() == m0 and wm.strokes(&"Hub").size() == s0, "RMB erase: close/release/reopen hover erases and draws nothing")
	# Positive control: a real held RMB drag does erase through the viewport.
	_vp_button(c, Vector2(800, 250), MOUSE_BUTTON_RIGHT, true, R)
	_vp_motion(c, Vector2(800, 250), Vector2(800, 100), R)
	_vp_button(c, Vector2(800, 100), MOUSE_BUTTON_RIGHT, false, 0)
	await process_frame
	_check(wm.markers(&"Hub").size() == m0 - 1, "routed held RMB drag erases the marker it reaches")

	# Area change mid-drag: the drag belongs to the old area and must end.
	var hub_s := wm.strokes(&"Hub").size()
	_vp_button(c, Vector2(150, 400), MOUSE_BUTTON_LEFT, true, L)
	await process_frame
	_check(wm.strokes(&"Hub").size() == hub_s + 1 and c.is_interacting(), "area-change: stroke started in Hub")
	_main.area_loader._swap(preload("res://scenes/dungeon_a.tscn").instantiate())
	await physics_frame
	_check(wm.area_id == &"DungeonA" and not c.is_interacting(), "area swap mid-drag drops the drag state")
	_vp_motion(c, Vector2(150, 400), Vector2(300, 420), L)
	await process_frame
	_check(_stroke_len(wm, &"Hub", hub_s) == 1 and wm.strokes(&"DungeonA").is_empty(), "held motion after the swap draws in neither area")
	_vp_button(c, Vector2(300, 420), MOUSE_BUTTON_LEFT, false, 0)
	_main.area_loader._swap(preload("res://scenes/hub.tscn").instantiate())
	await physics_frame
	panel.close()
	await process_frame

## --- 4. Death resets the map (owner's full-reset decision includes it) ---
func _death_reset(wm: WorldMap) -> void:
	_check(wm.area_id == &"Hub" and wm.markers(&"Hub").size() > 0 and wm.strokes(&"Hub").size() > 0 and wm.explored_cells(&"Hub").size() > 0, "before death: same-run hub map has exploration + marks")
	var panel := _main.get_node("MapPanel") as MapPanel
	panel.open() # die with the map open: modal_ui must not leak across the reload
	var old_main := _main
	(_main.get_node("Player") as Player).apply_damage(1000000)
	var t := 0.0
	while t < 6.0 and (current_scene == old_main or current_scene == null):
		await create_timer(0.1).timeout
		t += 0.1
	for i in 3:
		await physics_frame
	_main = current_scene
	_check(_main != old_main and is_instance_valid(_main), "death reloads the run")
	var wm2 := _main.get_node_or_null("WorldMap") as WorldMap
	var panel2 := _main.get_node_or_null("MapPanel") as MapPanel
	_check(wm2 != null and panel2 != null and not panel2.visible, "fresh WorldMap + closed MapPanel after death")
	if wm2 == null:
		return
	var empty := true
	for id: StringName in [&"Hub", &"DungeonA"]:
		empty = empty and wm2.markers(id).is_empty() and wm2.strokes(id).is_empty()
	empty = empty and wm2.explored_cells(&"DungeonA").is_empty()
	# The fresh map re-reveals only around the player's spawn (fresh state, not carried over).
	var spawn_cell := (_main.get_node("Player") as Player).global_position
	var fresh: Array = WorldMap.radius_cells(spawn_cell, WorldMap.EXPLORE_RADIUS_CELLS)
	var got := wm2.explored_cells(&"Hub")
	empty = empty and got.size() == fresh.size()
	for cell: Vector2i in fresh:
		empty = empty and got.has(cell)
	_check(empty, "death clears exploration, markers and strokes in every area")
	_check(get_nodes_in_group("modal_ui").is_empty(), "no modal_ui leak after dying with the map open")
