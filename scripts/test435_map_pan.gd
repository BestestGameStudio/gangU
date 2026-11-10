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

func _run() -> void:
	Bestiary.save_path = "user://test435_bestiary.cfg"
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await _frames()
	main.enter_overworld()
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

	# Non-overworld areas: no bounds, no panning.
	panel.close()
	main._load_hub()
	await _frames()
	panel.open()
	await _frames()
	_check(c.pan_bounds.size == Vector2.ZERO, "outside the overworld there is no pan bounds")
	var h := c.center
	_btn(c, mid, MOUSE_BUTTON_MIDDLE, true)
	_move(c, mid + Vector2(30, 0), Vector2(30, 0), MOUSE_BUTTON_MASK_MIDDLE)
	_btn(c, mid, MOUSE_BUTTON_MIDDLE, false)
	_check(c.center == h and not c.is_panning(), "middle drag is inert where the area has no bounds")

	print("test435 done: %d checks, %d failures" % [_checks, _fails])
	print("RESULT: ALL PASS" if _fails == 0 else "RESULT: FAIL")
	quit(0 if _fails == 0 else 1)
