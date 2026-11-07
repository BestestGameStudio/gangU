extends SceneTree
## #50 residual harness: HUD backing plate + gate label visibility.
## Drives the PRODUCTION main.tscn at the REAL 1152x648 viewport (set
## explicitly - headless defaults differ) with the camera settled at spawn.
## Gate TypeLabels must render clear of the plate and inside the viewport
## while staying tied to their own gate (same row or column when displaced
## to a plate edge). Waits are CONDITION-based (visibility/position), never
## fixed frame budgets, so headless fast-frame timing cannot fake a pass.

var failures := 0
var main: Node
var hud: HUD
var frame := 0
var hub_plate_h := 0.0
var _cam_last := Vector2.INF
var _cam_stable := 0
var _entered := false

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[50b] ", name, " -> PASS")
	else:
		failures += 1
		print("[50b] ", name, " -> FAIL")

func _cam_settled() -> bool:
	var cam := root.get_camera_2d()
	if cam == null:
		return false
	var p: Vector2 = cam.global_position
	if p.distance_to(_cam_last) < 0.5:
		_cam_stable += 1
	else:
		_cam_stable = 0
	_cam_last = p
	return _cam_stable >= 3

## The label's actual rendered screen rect: placement position + the same
## font-metrics size gate.gd uses (never the control's stale minimum).
func _label_screen_rect(gate: Gate) -> Rect2:
	var canvas := root.get_canvas_transform()
	var lbl: Label = gate.get_node("TypeLabel")
	var size := Vector2(52, 23)
	var font := lbl.get_theme_font("font")
	var fs := lbl.get_theme_font_size("font_size")
	if font != null and lbl.text != "":
		var ts := font.get_string_size(lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		size = Vector2(maxf(52.0, ts.x), maxf(23.0, ts.y))
	var tl: Vector2 = canvas * (gate.global_position + lbl.position)
	return Rect2(tl, size)

func _inside_viewport(r: Rect2) -> bool:
	var vs: Vector2 = root.get_visible_rect().size
	return r.position.x >= 0.0 and r.position.y >= 0.0 and r.end.x <= vs.x and r.end.y <= vs.y

## Row or column tie to the gate's own screen position.
func _tied(r: Rect2, gate: Gate) -> bool:
	var gs: Vector2 = root.get_canvas_transform() * gate.global_position
	var c := r.get_center()
	return absf(c.y - gs.y) < 30.0 or absf(c.x - gs.x) < 40.0

func _initialize() -> void:
	# REAL launch viewport, host-independent: window resize works windowed but
	# headless ignores it (its window stays 1152x1152), so force the LOGICAL
	# viewport via content scale - identical measured rect in both modes.
	root.size = Vector2i(1152, 648)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_size = Vector2i(1152, 648)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)

var _stage := 0
func _process(_d: float) -> bool:
	frame += 1
	if hud == null:
		hud = root.find_child("HUD", true, false) as HUD
		if frame > 600:
			print("[50b] HUD never mounted -> FAIL")
			quit(1)
		return false
	match _stage:
		0: # static plate structure
			if frame < 3:
				return false
			_check(root.get_visible_rect().size == Vector2(1152, 648), "viewport is the real 1152x648 (not headless default)")
			_check(hud != null, "HUD mounted")
			var plate: ColorRect = hud.get_node_or_null("BackingPlate")
			_check(plate != null, "BackingPlate exists")
			_check(plate != null and plate.mouse_filter == Control.MOUSE_FILTER_IGNORE, "plate click-through (mouse_filter IGNORE)")
			_check(plate != null and plate.visible, "plate visible")
			_stage = 1
		1: # plate coverage + content rebuild
			var plate_rect: Rect2 = hud.reserved_rect()
			_check(plate_rect.get_area() > 0.0, "reserved_rect non-empty")
			var covered := true
			for c in hud.get_node("Root").find_children("*", "Control", true, false):
				if c.visible and not plate_rect.encloses(c.get_global_rect()):
					covered = false
			_check(covered, "plate covers all visible HUD rows (incl. 6 slot rows)")
			hud.get_node("Root/HPLabel").text = "HP 100/100 VERYLONGTAIL xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
			_stage = 2
		2:
			var plate_rect: Rect2 = hud.reserved_rect()
			_check(plate_rect.size.x > 388.0, "plate rebuilt wider after long content (was 388 base)")
			hud.get_node("Root/HPLabel").text = "HP 100/100"
			_stage = 3
		3: # hub spawn at real viewport, camera settled
			if not _cam_settled() or frame < 20:
				return false
			var hub = main.current_area
			var gn: Gate = hub.get_node("GateNormal")
			var gr: Gate = hub.get_node("GateRed")
			var rr: Rect2 = hud.reserved_rect()
			var rn := _label_screen_rect(gn)
			var rred := _label_screen_rect(gr)
			var gs_n: Vector2 = root.get_canvas_transform() * gn.global_position
			print("[50b] spawn: plate=", rr, " gateN_screen=", gs_n, " labelN=", rn, " labelRED=", rred)
			_check(not rn.intersects(rr), "GateNormal label clear of plate at spawn")
			_check(_inside_viewport(rn), "GateNormal label inside viewport at spawn")
			_check(_tied(rn, gn), "GateNormal label tied to own gate (row/column) at spawn")
			var default_tl: Vector2 = (root.get_canvas_transform() * gr.global_position) + Vector2(-26, -10)
			_check(rred.position.distance_to(default_tl) < 2.0, "GateRed label keeps default placement when clear")
			main.get_node("Player").global_position = Vector2(876, 324)
			_cam_stable = 0
			_cam_last = Vector2.INF
			_stage = 4
		4: # camera sweep: gate slides under the plate zone
			if not _cam_settled():
				return false
			var gn: Gate = main.current_area.get_node("GateNormal")
			var rr: Rect2 = hud.reserved_rect()
			var rn := _label_screen_rect(gn)
			print("[50b] sweep: plate=", rr, " gateN_screen=", root.get_canvas_transform() * gn.global_position, " labelN=", rn)
			_check(not rn.intersects(rr), "GateNormal label clear of plate after camera sweep")
			_check(_inside_viewport(rn), "GateNormal label inside viewport after camera sweep")
			_check(_tied(rn, gn), "GateNormal label tied to own gate after camera sweep")
			root.content_scale_size = Vector2i(800, 1000) # logical portrait, host-independent
			_cam_stable = 0
			_cam_last = Vector2.INF
			_stage = 5
		5: # portrait viewport rebuild
			if not _cam_settled():
				return false
			var rr: Rect2 = hud.reserved_rect()
			var covered := true
			for c in hud.get_node("Root").find_children("*", "Control", true, false):
				if c.visible and not rr.encloses(c.get_global_rect()):
					covered = false
			_check(covered, "plate still covers HUD rows after viewport change")
			var gn: Gate = main.current_area.get_node("GateNormal")
			var rn := _label_screen_rect(gn)
			_check(_inside_viewport(rn), "GateNormal label inside viewport (portrait)")
			root.content_scale_size = Vector2i(1152, 648)
			_stage = 6
		6: # objective growth via the REAL gate-entry path
			if _entered:
				return false
			hub_plate_h = hud.reserved_rect().size.y
			var g: Gate = main.current_area.get_node("GateNormal")
			g._on_body_entered(main.get_node("Player"))
			_entered = true
			_stage = 7
		7: # condition wait: objective discovered + label visible (no frame budget)
			if main.current_area.name == "DungeonA" and not _check_done_objective:
				var lbl: Label = hud.get_node("Root/ObjectiveLabel")
				if lbl.visible:
					_check(main.current_area.name == "DungeonA", "entered DungeonA via real gate")
					_check(true, "objective row became visible after real entry")
					_check_done_objective = true
					_stable_plate = hud.reserved_rect().size.y
					_plate_wait = 0
				elif frame > 1200:
					_check(false, "objective row became visible after real entry (timed out)")
					_check_done_objective = true
					_plate_wait = 99
			if _check_done_objective:
				_plate_wait += 1
				if _plate_wait >= 4: # let the container sort settle, then read the plate
					var plate_h: float = hud.reserved_rect().size.y
					print("[50b] objective growth: hub plate_h=", hub_plate_h, " dungeon plate_h=", plate_h)
					_check(plate_h > hub_plate_h, "plate grew with objective row in DungeonA (%.0f -> %.0f)" % [hub_plate_h, plate_h])
					var portal = main.current_area.get_node_or_null("ExitPortal")
					_check(portal != null, "exit portal mounted (regression)")
					_stage = 8
		8:
			print("[50b] ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
			quit(0 if failures == 0 else 1)
			_stage = 9
	return false

var _check_done_objective := false
var _plate_wait := 0
var _stable_plate := 0.0
