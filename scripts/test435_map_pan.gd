extends SceneTree
## #435 harness: the overworld map pans by MIDDLE-drag or Space+LMB-drag,
## clamped to the overworld bounds, and snaps back to the player when the
## player moves or the map is reopened. Plain LMB tools and RMB erase are
## unchanged (Daniel, 2026-11-09).

var _fails := 0
var _checks := 0

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("[435] ", label, " -> ", "PASS" if ok else "FAIL")

func _view_in_poly(c: Vector2, half: Vector2, poly: PackedVector2Array) -> bool:
	var r := PackedVector2Array([c + Vector2(-half.x, -half.y), c + Vector2(half.x, -half.y), c + half, c + Vector2(-half.x, half.y)])
	if not Geometry2D.clip_polygons(r, poly).is_empty():
		return false
	# Independent sample check: every corner and 7 points along each edge.
	for i in 4:
		for k in 8:
			if not Geometry2D.is_point_in_polygon(r[i].lerp(r[(i + 1) % 4], k / 8.0), poly):
				return false
	return true

func _initialize() -> void:
	_run.call_deferred()

func _frames(n := 3) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _btn(c: MapCanvas, pos: Vector2, b: MouseButton, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = b
	ev.pressed = pressed
	ev.position = pos
	c._gui_input(ev)

func _move(c: MapCanvas, pos: Vector2, rel: Vector2, mask: int) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.relative = rel
	ev.button_mask = mask
	c._gui_input(ev)

## Native routing: events go through root.push_input and the GUI's own hit-test
## and mouse-focus logic (as in a real session), not straight into _gui_input.
func _vp_pos(c: MapCanvas, local: Vector2) -> Vector2:
	return c.get_global_transform_with_canvas() * local

func _vp_button(c: MapCanvas, local: Vector2, b: MouseButton, pressed: bool, mask: int) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = b
	ev.pressed = pressed
	ev.button_mask = mask
	ev.position = _vp_pos(c, local)
	ev.global_position = ev.position
	root.push_input(ev, true)

func _vp_motion(c: MapCanvas, from_local: Vector2, to_local: Vector2, mask: int) -> void:
	var ev := InputEventMouseMotion.new()
	ev.button_mask = mask
	ev.position = _vp_pos(c, to_local)
	ev.global_position = ev.position
	ev.relative = to_local - from_local
	root.push_input(ev, true)

## Real key state: Input.parse_input_event updates Input.is_physical_key_pressed.
func _space(down: bool) -> void:
	var k := InputEventKey.new()
	k.physical_keycode = KEY_SPACE
	k.keycode = KEY_SPACE
	k.pressed = down
	Input.parse_input_event(k)
	Input.flush_buffered_events()

func _native(main: Node, wm: WorldMap, panel: MapPanel, c: MapCanvas) -> void:
	var id: StringName = wm.area_id
	panel.open()
	await _frames()
	var mid := c.size * 0.5
	var from := c.center
	# Middle button, real routing.
	_vp_button(c, mid, MOUSE_BUTTON_MIDDLE, true, MOUSE_BUTTON_MASK_MIDDLE)
	_check(c.is_panning(), "native: middle press pans through real GUI routing")
	_vp_motion(c, mid, mid + Vector2(0, 60), MOUSE_BUTTON_MASK_MIDDLE)
	_vp_button(c, mid + Vector2(0, 60), MOUSE_BUTTON_MIDDLE, false, 0)
	_check(c.center.y < from.y and not c.is_panning(), "native: middle drag down moved the view up and released")
	# Space held for real, then LMB.
	panel.close()
	panel.open()
	await _frames()
	from = c.center
	_check(not c._space_down(), "native: Space is not held yet")
	_space(true)
	_check(c._space_down() and not c.space_override, "native: a real Space key event is seen as held (no test seam)")
	_vp_button(c, mid, MOUSE_BUTTON_LEFT, true, MOUSE_BUTTON_MASK_LEFT)
	_check(c.is_panning(), "native: Space + LMB pans")
	_vp_motion(c, mid, mid + Vector2(0, 60), MOUSE_BUTTON_MASK_LEFT)
	_vp_button(c, mid + Vector2(0, 60), MOUSE_BUTTON_LEFT, false, 0)
	_check(c.center.y < from.y and wm.strokes(id).is_empty(), "native: Space + LMB drag pans and draws no ink")
	_space(false)
	_check(not c._space_down(), "native: Space released")
	# Plain buttons, real routing, Space up.
	_vp_button(c, mid, MOUSE_BUTTON_LEFT, true, MOUSE_BUTTON_MASK_LEFT)
	_vp_motion(c, mid, mid + Vector2(25, 0), MOUSE_BUTTON_MASK_LEFT)
	_vp_button(c, mid + Vector2(25, 0), MOUSE_BUTTON_LEFT, false, 0)
	_check(wm.strokes(id).size() == 1 and not c.is_panning(), "native: plain LMB still draws")
	var cc := c.center
	panel.set_tool(MapCanvas.Tool.MARKER)
	_vp_button(c, mid + Vector2(80, 40), MOUSE_BUTTON_LEFT, true, MOUSE_BUTTON_MASK_LEFT)
	_vp_button(c, mid + Vector2(80, 40), MOUSE_BUTTON_LEFT, false, 0)
	_check(wm.markers(id).size() == 1 and c.center == cc, "native: Marker tool places a marker, no pan")
	panel.set_tool(MapCanvas.Tool.ERASE)
	_vp_button(c, mid + Vector2(80, 40), MOUSE_BUTTON_LEFT, true, MOUSE_BUTTON_MASK_LEFT)
	_vp_button(c, mid + Vector2(80, 40), MOUSE_BUTTON_LEFT, false, 0)
	_check(wm.markers(id).is_empty() and c.center == cc, "native: Erase tool erases the marker, no pan")
	panel.set_tool(MapCanvas.Tool.DRAW)
	_vp_button(c, mid + Vector2(5, 0), MOUSE_BUTTON_RIGHT, true, MOUSE_BUTTON_MASK_RIGHT)
	_vp_button(c, mid + Vector2(5, 0), MOUSE_BUTTON_RIGHT, false, 0)
	_check(wm.strokes(id).is_empty() and c.center == cc, "native: RMB erases the stroke, no pan")
	# LMB fast-travel site pick.
	var site_pos := c.screen_to_world(mid + Vector2(-100, 30))
	wm.set_sites(id, {&"dungeon_a": site_pos})
	wm.cleared_rule = func(_d): return true
	c.queue_redraw()
	await _frames()
	_vp_button(c, mid + Vector2(-100, 30), MOUSE_BUTTON_LEFT, true, MOUSE_BUTTON_MASK_LEFT)
	_vp_button(c, mid + Vector2(-100, 30), MOUSE_BUTTON_LEFT, false, 0)
	_check(c.selected_site == &"dungeon_a" and not c.is_panning() and wm.strokes(id).is_empty(), "native: LMB on a cleared site still selects it for fast travel")
	wm.cleared_rule = Callable()
	wm.set_sites(id, {})

func _run() -> void:
	Bestiary.save_path = "user://test435_bestiary.cfg"
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await _frames()
	main.area_loader.enter_overworld()
	await _frames()
	var wm: WorldMap = main.get_node("WorldMap")
	var panel: MapPanel = main.get_node("MapPanel")
	var c := panel.canvas
	var player: Node2D = main.get_node("Player")
	var id: StringName = wm.area_id

	panel.open()
	await _frames()
	var b := wm.pan_bounds()
	_check(b.size.x > 0.0 and b.size.y > 0.0, "overworld has pan bounds")
	_check(c.pan_bounds == b, "canvas uses the overworld bounds")
	var real_outline := c.pan_outline
	var real_bounds := c.pan_bounds
	_check(real_outline.size() >= 3 and c.pan_outline == wm.pan_outline(), "canvas uses the overworld outline")
	_check(c.center.is_equal_approx(c.clamp_center(player.global_position)), "opens centered on the player (kept inside bounds)")
	var mid := c.size * 0.5

	# Middle-drag pans: dragging right moves the view left.
	var start := c.center
	_btn(c, mid, MOUSE_BUTTON_MIDDLE, true)
	_check(c.is_panning(), "middle press starts a pan")
	_move(c, mid + Vector2(30, 0), Vector2(30, 0), MOUSE_BUTTON_MASK_MIDDLE)
	var moved := c.center
	_check(moved.x < start.x and is_equal_approx(moved.y, start.y), "middle drag right pans the view left")
	_check(is_equal_approx(start.x - moved.x, 30.0 / c.map_scale) or c.clamp_center(start - Vector2(30.0 / c.map_scale, 0)) == moved, "pan distance matches the drag at this scale (or the bound)")
	_btn(c, mid, MOUSE_BUTTON_MIDDLE, false)
	_check(not c.is_panning(), "middle release ends the pan")
	_check(wm.strokes(id).is_empty() and wm.markers(id).is_empty(), "panning draws nothing")

	# Space + LMB pans.
	var before := c.center
	c.space_override = true
	_btn(c, mid, MOUSE_BUTTON_LEFT, true)
	_check(c.is_panning(), "Space + LMB starts a pan")
	_move(c, mid + Vector2(0, 20), Vector2(0, 20), MOUSE_BUTTON_MASK_LEFT)
	_check(c.center.y < before.y, "Space + LMB drag down pans the view up")
	_btn(c, mid, MOUSE_BUTTON_LEFT, false)
	c.space_override = false
	_check(not c.is_panning() and wm.strokes(id).is_empty(), "Space + LMB pans and draws no ink")

	# Clamp: a huge drag never shows beyond the bounds.
	_btn(c, mid, MOUSE_BUTTON_MIDDLE, true)
	for i in 40:
		_move(c, mid, Vector2(-5000, -5000), MOUSE_BUTTON_MASK_MIDDLE)
	_btn(c, mid, MOUSE_BUTTON_MIDDLE, false)
	var half := c.size * 0.5 / c.map_scale
	var view := Rect2(c.center - half, half * 2.0)
	_check(view.position.x >= b.position.x - 0.01 or half.x * 2.0 > b.size.x, "no empty space past the left edge")
	_check(view.end.x <= b.end.x + 0.01 or half.x * 2.0 > b.size.x, "no empty space past the right edge")
	_check(view.end.y <= b.end.y + 0.01 or half.y * 2.0 > b.size.y, "no empty space past the bottom edge")
	_check(view.position.y >= b.position.y - 0.01 or half.y * 2.0 > b.size.y, "no empty space past the top edge")
	_btn(c, mid, MOUSE_BUTTON_MIDDLE, true)
	for i in 40:
		_move(c, mid, Vector2(5000, 5000), MOUSE_BUTTON_MASK_MIDDLE)
	_btn(c, mid, MOUSE_BUTTON_MIDDLE, false)
	view = Rect2(c.center - half, half * 2.0)
	if c.outline_fits_view():
		# (#440 review) With a land outline that fits the view, the near end of
		# the pan is the outline's own edge, not the bounding-rect corner.
		_check(_view_in_poly(c.center, half, c.pan_outline), "reaches the outline's near edge but never past it")
	else:
		_check(view.position.x <= b.position.x + 0.01 and view.position.y <= b.position.y + 0.01, "reaches the near corner but never past it")

	# Snap back when the player moves.
	player.global_position += Vector2(80, 0)
	await _frames()
	_check(c.center.is_equal_approx(c.clamp_center(player.global_position)), "player move snaps the view back onto the player")

	# Snap back on close and reopen.
	_btn(c, mid, MOUSE_BUTTON_MIDDLE, true)
	_move(c, mid, Vector2(-200, 0), MOUSE_BUTTON_MASK_MIDDLE)
	_btn(c, mid, MOUSE_BUTTON_MIDDLE, false)
	_check(not c.center.is_equal_approx(c.clamp_center(player.global_position)), "view is panned away before closing")
	panel.close()
	panel.open()
	await _frames()
	_check(c.center.is_equal_approx(c.clamp_center(player.global_position)), "reopen recenters on the player")

	# Existing controls unchanged.
	_btn(c, mid, MOUSE_BUTTON_LEFT, true)
	_move(c, mid + Vector2(20, 0), Vector2(20, 0), MOUSE_BUTTON_MASK_LEFT)
	_btn(c, mid, MOUSE_BUTTON_LEFT, false)
	_check(wm.strokes(id).size() == 1 and not c.is_panning(), "plain LMB still draws with the Draw tool")
	var cc := c.center
	_btn(c, mid, MOUSE_BUTTON_RIGHT, true)
	_move(c, mid + Vector2(20, 0), Vector2(20, 0), MOUSE_BUTTON_MASK_RIGHT)
	_btn(c, mid, MOUSE_BUTTON_RIGHT, false)
	_check(c.center == cc, "RMB erase does not pan")

	await _native(main, wm, panel, c)

	# Non-overworld areas: no bounds, no panning.
	panel.close()
	main.area_loader._load_hub()
	await _frames()
	panel.open()
	await _frames()
	_check(c.pan_bounds.size == Vector2.ZERO, "outside the overworld there is no pan bounds")
	var h := c.center
	_btn(c, mid, MOUSE_BUTTON_MIDDLE, true)
	_move(c, mid + Vector2(30, 0), Vector2(30, 0), MOUSE_BUTTON_MASK_MIDDLE)
	_btn(c, mid, MOUSE_BUTTON_MIDDLE, false)
	_check(c.center == h and not c.is_panning(), "middle drag is inert where the area has no bounds")

	# (#440 review) Outline clamp: the whole view stays inside the land polygon,
	# not just inside its bounding rect. Synthetic wobbled ellipse at the #439
	# radii so this runs the same on any base; the real outline follows.
	var syn := PackedVector2Array()
	for i in 64:
		var a := TAU * i / 64.0
		var wob := 1.0 + (float((i * 37) % 11) / 11.0 - 0.5) * 0.12
		syn.append(Vector2(576, -150) + Vector2(cos(a) * 2400.0 * wob, sin(a) * 2100.0 * wob))
	var sb := Rect2(syn[0], Vector2.ZERO)
	for p in syn:
		sb = sb.expand(p)
	c.map_scale = 0.375
	c.pan_bounds = sb
	c.pan_outline = syn
	_check(c.outline_fits_view(), "synthetic outline has a center where the whole view fits")
	var vhalf := c.size * 0.5 / c.map_scale
	var worst_rect := 0.0
	var all_inside := true
	var rect_corners_exposed := 0
	for dir in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1), Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var far: Vector2 = sb.get_center() + Vector2(dir.x * sb.size.x, dir.y * sb.size.y)
		var got := c.clamp_center(far)
		if not _view_in_poly(got, vhalf, syn):
			all_inside = false
		# What the old bbox-only clamp gave for the same drag.
		var lo := sb.position + vhalf
		var hi := sb.end - vhalf
		var old := Vector2(clampf(far.x, lo.x, hi.x), clampf(far.y, lo.y, hi.y))
		if not _view_in_poly(old, vhalf, syn):
			rect_corners_exposed += 1
	_check(all_inside, "every extreme drag keeps the whole view inside the outline polygon")
	_check(rect_corners_exposed >= 4, "the old bounding-rect clamp WOULD expose outside space at the corners (%d of 8 directions)" % rect_corners_exposed)
	# A center already inside is untouched; the rect-corner center is pulled in.
	var ok_c := c.clamp_center(sb.get_center())
	_check(_view_in_poly(ok_c, vhalf, syn) and c.clamp_center(ok_c).is_equal_approx(ok_c), "a fitting center is left alone")
	var corner := Vector2(sb.end.x - vhalf.x, sb.end.y - vhalf.y)
	_check(not _view_in_poly(corner, vhalf, syn) and _view_in_poly(c.clamp_center(corner), vhalf, syn), "the exact old-rect corner center is rejected and pulled inside")
	# Dragging step by step into the corner never leaves the polygon.
	c.center = ok_c
	var stepped_ok := true
	for i in 400:
		c.center = c.clamp_center(c.center - Vector2(30, 30) / c.map_scale)
		if not _view_in_poly(c.center, vhalf, syn):
			stepped_ok = false
	_check(stepped_ok, "a long drag toward the corner stays inside the polygon at every step")
	# Too small for the view (zoomed way out): no center fits, rect clamp only.
	c.map_scale = 0.1
	_check(not c.outline_fits_view(), "when the view cannot fit at all, no fitting center is claimed")
	c.map_scale = 0.375
	# The real overworld outline on this base.
	c.pan_bounds = real_bounds
	c.pan_outline = real_outline
	var fits := c.outline_fits_view()
	var real_ok := true
	for dir in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var got := c.clamp_center(real_bounds.get_center() + Vector2(dir.x * real_bounds.size.x, dir.y * real_bounds.size.y))
		if fits and not _view_in_poly(got, c.size * 0.5 / c.map_scale, real_outline):
			real_ok = false
	print("[435] real overworld outline fits the default view: ", fits)
	_check(real_ok, "real outline: extreme drags stay inside the polygon whenever the view fits at all")

	print("test435 done: %d checks, %d failures" % [_checks, _fails])
	print("RESULT: ALL PASS" if _fails == 0 else "RESULT: FAIL")
	quit(0 if _fails == 0 else 1)
