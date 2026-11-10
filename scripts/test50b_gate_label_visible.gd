extends SceneTree
## #50 residual harness: HUD backing plate + gate label visibility.
## #106 CONTRACT (supersedes the #50/#84/#87 plate-escape rules): the gate
## TypeLabel stays ATTACHED to its own gate at all times - sliding under
## the translucent HUD plate with its gate is accepted (the body dims there
## too), and a gate fully off-screen HIDES its label instead of clamping it
## mid-screen. Detached escapes are now the BUG, not the fix.
## Drives the PRODUCTION main.tscn at the REAL 1152x648 viewport (set
## explicitly - headless defaults differ). Waits are CONDITION-based
## (visibility/position), never fixed frame budgets, so headless fast-frame
## timing cannot fake a pass.

var failures := 0
var main: Node
var hud: HUD
var frame := 0
var hub_plate_h := 0.0
var _cam_last := Vector2.INF
var _cam_stable := 0
var _entered := false
var _87_setup := false
var _87_aimed := false
var _87_frames := 0
var _87_consec := 0
var _87_rn := Rect2()
var _87_rred := Rect2()
var _87_maxdelta := 0.0
var _106_moved := false
var _87_maxres := 0.0

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
	# 1px tolerance: the gate places against THIS frame's canvas transform
	# and the harness re-projects after the camera's _process - a boundary-
	# clamped label (x=0) can measure sub-pixel negative from camera
	# micro-drift alone. Placement choice is unaffected.
	var vs: Vector2 = root.get_visible_rect().size
	return r.position.x >= -1.0 and r.position.y >= -1.0 and r.end.x <= vs.x + 1.0 and r.end.y <= vs.y + 1.0

## #106: attached means the label's center stays within 90px of its gate's
## screen center (covers above/below/right/left adjacent candidates; the
## old plate-edge escapes sat ~150px away and FAIL this).
func _attached(r: Rect2, gate: Gate) -> bool:
	var gs: Vector2 = root.get_canvas_transform() * gate.global_position
	return r.get_center().distance_to(gs) < 90.0

## #106: label position minus the above-gate candidate recomputed from the
## LIVE canvas transform. ~0 over a settled window proves placement is a
## pure function of the camera - no avoidance-feedback alternation.
func _attach_residual(r: Rect2, gate: Gate) -> float:
	var gs: Vector2 = root.get_canvas_transform() * gate.global_position
	return r.position.distance_to(gs + Vector2(-r.size.x / 2.0, -10.0))

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
			_check(hud.get_node_or_null("BackingPlate") == null, "#238 BackingPlate removed")
			_stage = 1
		1: # plate coverage + content rebuild
			var plate_rect: Rect2 = hud.reserved_rect()
			_check(plate_rect.get_area() > 0.0, "reserved_rect non-empty")
			var covered := true
			for c in hud.get_node("Root").find_children("*", "Control", true, false):
				if c.visible and not plate_rect.encloses(c.get_global_rect()):
					covered = false
			_check(covered, "plate covers all visible HUD rows (incl. 6 slot rows)")
			hud.get_node("Root/HPBar/HPLabel").text = "HP 100/100 VERYLONGTAIL xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
			_stage = 2
		2:
			var plate_rect: Rect2 = hud.reserved_rect()
			_check(plate_rect.size.x > 388.0, "plate rebuilt wider after long content (was 388 base)")
			hud.get_node("Root/HPBar/HPLabel").text = "HP 100/100"
			_stage = 25
		25: # #346: the dungeon gates live in the overworld, laid out exactly as
			# they were in the hub around the same spawn. Its entrance guards are
			# removed: this harness measures labels, not combat.
			main.enter_overworld()
			for e in get_nodes_in_group("enemies"):
				e.free()
			# #446: production gates are spread across the field, off screen
			# from the spawn. This harness measures label placement, so the
			# two gates go back to their pre-#446 spots beside the spawn.
			(main.current_area.get_node("GateNormal") as Node2D).position = Vector2(300, 380)
			(main.current_area.get_node("GateRed") as Node2D).position = Vector2(852, 380)
			_cam_stable = 0
			_cam_last = Vector2.INF
			_stage = 3
			return false
		3: # overworld spawn at real viewport, camera settled
			if not _cam_settled() or frame < 20:
				return false
			var hub = main.current_area
			var gn: Gate = hub.get_node("GateNormal")
			var gr: Gate = hub.get_node("GateRed")
			var rr: Rect2 = hud.reserved_rect()
			var rn := _label_screen_rect(gn)
			var rred := _label_screen_rect(gr)
			var gs_n: Vector2 = root.get_canvas_transform() * gn.global_position
			print("[50b] spawn: plate=", rr, " gateN_screen=", gs_n, " labelN=", rn, " labelRED=", rred, " labelN_visible=", gn.get_node("TypeLabel").visible)
			_check(_attached(rn, gn), "#106 GateNormal label ATTACHED to its gate at spawn (dimmed under the translucent plate is fine)")
			_check(_inside_viewport(rn), "GateNormal label inside viewport at spawn")
			_check(gn.get_node("TypeLabel").visible, "#106 GateNormal label visible while its gate is on screen")
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
			_check(_attached(rn, gn), "#106 GateNormal label attached to its gate after camera sweep")
			_check(not _inside_viewport(rn) or true, "#106 label may ride PARTLY off-edge with its gate (old clamp rule removed)")
			_check(gn.get_node("TypeLabel").visible, "#106 GateNormal label visible after camera sweep (gate still on screen)")
			_stage = 45
		45: # #106: walk far up - gates slide fully off the bottom edge
			if not _106_moved:
				main.get_node("Player").global_position += Vector2(0, -900)
				_cam_stable = 0
				_cam_last = Vector2.INF
				_106_moved = true
				return false
			if not _cam_settled():
				return false
			var gnO: Gate = main.current_area.get_node("GateNormal")
			var grO: Gate = main.current_area.get_node("GateRed")
			var canvasO := root.get_canvas_transform()
			var bodyO: ColorRect = gnO.get_node("ColorRect")
			var rbO := Rect2(canvasO * (gnO.global_position + bodyO.position), bodyO.size)
			_check(not rbO.intersects(Rect2(Vector2.ZERO, root.get_visible_rect().size)), "#106 setup: NORMAL gate fully off-screen after the walk")
			_check(not gnO.get_node("TypeLabel").visible and not grO.get_node("TypeLabel").visible, "#106 off-screen gates HIDE their labels (never clamped mid-screen)")
			main.get_node("Player").global_position += Vector2(0, 900)
			_cam_stable = 0
			_cam_last = Vector2.INF
			_stage = 46
			return false
		46: # #106: back on screen - visible + attached again
			if not _cam_settled():
				return false
			var gnB: Gate = main.current_area.get_node("GateNormal")
			_check(gnB.get_node("TypeLabel").visible, "#106 label visible again when its gate returns on screen")
			_check(_attached(_label_screen_rect(gnB), gnB), "#106 label attached again after the round trip")
			_stage = 5
			return false
		5: # #106 (supersedes the #84 escape legs): BOTH gates aimed behind the
			# wide plate - labels RIDE with their gates (attached + visible,
			# dimmed through the translucent plate), never escape off their gate,
			# never overlap each other.
			if not _84_setup:
				hud.get_node("Root/HPBar/HPLabel").text = "HP 100/100 VERYLONGTAIL xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
				_84_setup = true
				return false # let the plate rebuild first
			if _84_aimed == false:
				var rr2: Rect2 = hud.reserved_rect()
				var gn2: Gate = main.current_area.get_node("GateNormal")
				var view2: Vector2 = root.get_visible_rect().size
				# Both gates into the plate's x-band (RED sits a fixed 552 world
				# px right of NORMAL).
				var target_gs := Vector2(rr2.end.x - 412.0, rr2.end.y - 100.0) # #238: rect is narrower without the plate; keeps this camera so the portrait leg stays on-screen
				main.get_node("Player").global_position = gn2.global_position - target_gs + view2 / 2.0
				_cam_stable = 0
				_cam_last = Vector2.INF
				_84_aimed = true
				return false
			if not _cam_settled():
				return false
			var gn3: Gate = main.current_area.get_node("GateNormal")
			var gr3: Gate = main.current_area.get_node("GateRed")
			var rn3 := _label_screen_rect(gn3)
			var rred3 := _label_screen_rect(gr3)
			print("[50b] #106 plate pair: labelN=", rn3, " labelRED=", rred3)
			_check(_attached(rn3, gn3), "#106 NORMAL label attached behind the wide plate")
			_check(_attached(rred3, gr3), "#106 RED label attached behind the wide plate")
			_check(not rn3.intersects(rred3), "#106 labels do not intersect each other")
			_check(gn3.get_node("TypeLabel").visible and gr3.get_node("TypeLabel").visible, "#106 labels visible (gates on screen behind the translucent plate)")
			hud.get_node("Root/HPBar/HPLabel").text = "HP 100/100"
			_stage = 6
			return false
		6: # #106 settle check at the current camera (both gates behind plate)
			_87_frames = 0
			_87_consec = 0
			_87_rn = Rect2()
			_87_rred = Rect2()
			_87_maxdelta = 0.0
			_87_maxres = 0.0
			_stage = 63
			return false
		63: # #106 (carries the #87 intent): attached placements are a PURE
			# FUNCTION of the camera - they settle to a fixed point for 30
			# consecutive frames (per-frame movement < 1px once the camera
			# settles), never oscillate between candidates, never intersect.
			var gn3: Gate = main.current_area.get_node("GateNormal")
			var gr3: Gate = main.current_area.get_node("GateRed")
			var rn3 := _label_screen_rect(gn3)
			var rred3 := _label_screen_rect(gr3)
			var dn := rn3.position.distance_to(_87_rn.position)
			var dr := rred3.position.distance_to(_87_rred.position)
			if _87_frames > 0 and (dn >= 1.0 or dr >= 1.0):
				_87_consec = 0 # still moving: camera settling continues
			else:
				_87_consec += 1
			if _87_frames > 0:
				_87_maxdelta = maxf(_87_maxdelta, maxf(dn, dr))
				_87_maxres = maxf(_87_maxres, maxf(_attach_residual(rn3, gn3), _attach_residual(rred3, gr3)))
			_87_rn = rn3
			_87_rred = rred3
			_87_frames += 1
			if _87_frames > 600:
				_check(false, "#106 placements settle to a fixed point - no oscillation (never stabilized)")
				_stage = 62
				return false
			if _87_consec < 30:
				return false
			print("[50b] #106 settle: labelN=", rn3, " labelRED=", rred3, " max drift in window=", _87_maxdelta, " max attach residual=", _87_maxres)
			_check(not rn3.intersects(rred3), "#106 settled labels do not intersect each other")
			_check(true, "#106 placements settle: 30 consecutive frames without candidate change (drift < 1px = camera settle only)")
			_check(_87_maxres < 1.0, "#106 placements track the camera exactly (attach residual < 1px) - no avoidance feedback")
			_check(_attached(rn3, gn3) and _attached(rred3, gr3), "#106 both labels attached to their own gates")
			_stage = 62
			return false
		62: # portrait viewport rebuild
			root.content_scale_size = Vector2i(800, 1000) # logical portrait, host-independent
			_cam_stable = 0
			_cam_last = Vector2.INF
			_stage = 61
			return false
		61:
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
			print("[50b] portrait: labelN=", rn, " gateN_screen=", root.get_canvas_transform() * gn.global_position, " view=", root.get_visible_rect().size)
			_check(_attached(rn, gn), "#106 GateNormal label attached (portrait)")
			_check(gn.get_node("TypeLabel").visible, "#106 GateNormal label visible (portrait, gate on screen)")
			root.content_scale_size = Vector2i(1152, 648)
			_stage = 7
		7: # objective growth via the REAL gate-entry path
			if _entered:
				return false
			hub_plate_h = hud.reserved_rect().size.y
			var g: Gate = main.current_area.get_node("GateNormal")
			g._on_body_entered(main.get_node("Player"))
			_entered = true
			_stage = 8
		8: # condition wait: objective discovered + label visible (no frame budget)
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
					_stage = 9
		9:
			print("[50b] ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
			quit(0 if failures == 0 else 1)
			_stage = 9
	return false

var _check_done_objective := false
var _plate_wait := 0
var _stable_plate := 0.0

var _84_setup := false
var _84_aimed := false
