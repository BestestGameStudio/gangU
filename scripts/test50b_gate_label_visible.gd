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
var _87_setup := false
var _87_aimed := false
var _87_frames := 0
var _87_consec := 0
var _87_rn := Rect2()
var _87_rred := Rect2()
var _87_zn := ""
var _87_zr := ""
var _87_zflips := 0
var _87_maxdelta := 0.0
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

## #87: which placement ZONE a label rect is in, relative to the plate -
## distinguishes a changed candidate choice from sub-pixel camera drift.
func _zone_of(r: Rect2, plate: Rect2) -> String:
	if r.position.x >= plate.end.x - 1.0:
		return "edge-right"
	if r.position.y >= plate.end.y - 1.0:
		return "below-plate"
	return "adjacent"

## #87: position minus the zone's driving input (plate edge or gate screen
## position through the canvas transform). ~0 over the window proves the
## within-zone position is a pure function of camera/plate inputs - camera
## subtraction that excludes avoidance-feedback alternation.
func _zone_residual(r: Rect2, zone: String, gate: Gate, plate: Rect2) -> float:
	var gs: Vector2 = root.get_canvas_transform() * gate.global_position
	if zone == "edge-right":
		return (r.position - Vector2(plate.end.x + Gate.LABEL_GAP, gs.y - r.size.y / 2.0)).length()
	if zone == "below-plate":
		return (r.position - Vector2(gs.x - r.size.x / 2.0, plate.end.y + Gate.LABEL_GAP)).length()
	return 0.0 # adjacent zones are not asserted here

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
			_stage = 5
		5: # #84: an escaped label must clear the OTHER gate's projected body
			# Widen the plate with real long HUD content, then place the player
			# (computed from the LIVE plate rect, not hardcoded) so NORMAL sits
			# behind the plate with RED's body exactly in the right-edge escape
			# path - the LIVE residual pair from the #84 frames.
			if not _84_setup:
				hud.get_node("Root/HPLabel").text = "HP 100/100 VERYLONGTAIL xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
				_84_setup = true
				return false # let the plate rebuild first
			if _84_aimed == false:
				var rr2: Rect2 = hud.reserved_rect()
				var gn2: Gate = main.current_area.get_node("GateNormal")
				var view2: Vector2 = root.get_visible_rect().size
				# Gate target: behind the plate, in the x-band where the
				# plate-right-edge escape lands exactly on RED's body
				# (RED sits a fixed 552 world px right of NORMAL).
				var target_gs := Vector2(rr2.end.x - 520.0, rr2.end.y - 100.0) # deep enough that below-adjacent stays inside the plate, forcing the escape
				main.get_node("Player").global_position = gn2.global_position - target_gs + view2 / 2.0
				_cam_stable = 0
				_cam_last = Vector2.INF
				_84_aimed = true
				return false
			if not _cam_settled():
				return false
			var rr3: Rect2 = hud.reserved_rect()
			var gn3: Gate = main.current_area.get_node("GateNormal")
			var gr3: Gate = main.current_area.get_node("GateRed")
			var canvas3 := root.get_canvas_transform()
			var rn3 := _label_screen_rect(gn3)
			var red_body: ColorRect = gr3.get_node("ColorRect")
			var rb3 := Rect2(canvas3 * (gr3.global_position + red_body.position), red_body.size)
			print("[50b] #84: plate=", rr3, " gateN_screen=", canvas3 * gn3.global_position, " labelN=", rn3, " RED_body=", rb3)
			_check(not rn3.intersects(rb3), "#84 escaped GateNormal label clear of RED gate body (swept)")
			_check(_inside_viewport(rn3), "#84 escaped GateNormal label inside viewport")
			_check(_tied(rn3, gn3), "#84 escaped GateNormal label tied to own gate (row/column)")
			hud.get_node("Root/HPLabel").text = "HP 100/100"
			_stage = 6
			return false
		6: # #87: BOTH gates behind the wide plate - labels must not collide
			# Both hub gates share the world row (y=380), 552 px apart. Aimed
			# so BOTH sit behind the wide plate, each label escapes to the SAME
			# plate-right-edge point on unpatched code (a02ab51 FAILS here).
			if not _87_setup:
				hud.get_node("Root/HPLabel").text = "HP 100/100 VERYLONGTAIL xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
				_87_setup = true
				return false # let the plate rebuild first
			if not _87_aimed:
				var rr2: Rect2 = hud.reserved_rect()
				var gn2: Gate = main.current_area.get_node("GateNormal")
				var view2: Vector2 = root.get_visible_rect().size
				var target_gs := Vector2(rr2.end.x - 900.0, rr2.end.y - 100.0) # both gates inside the plate's x-range
				main.get_node("Player").global_position = gn2.global_position - target_gs + view2 / 2.0
				_cam_stable = 0
				_cam_last = Vector2.INF
				_87_aimed = true
				return false
			if not _cam_settled():
				return false
			_87_frames = 0
			_87_consec = 0
			_stage = 63
			return false
		63: # #87 assertions + settle/no-oscillation: placements must become
			# constant and STAY constant for 10 consecutive frames, however long
			# the post-sweep transient takes (condition-based, no frame budget).
			var gn3: Gate = main.current_area.get_node("GateNormal")
			var gr3: Gate = main.current_area.get_node("GateRed")
			var rn3 := _label_screen_rect(gn3)
			var rred3 := _label_screen_rect(gr3)
			var rr3p: Rect2 = hud.reserved_rect()
			var zn := _zone_of(rn3, rr3p)
			var zr := _zone_of(rred3, rr3p)
			print("[50b] #87 frame ", _87_frames, ": labelN=", rn3.position, " zone=", zn, " labelRED=", rred3.position, " zone=", zr)
			var zone_flip := false
			if _87_frames == 0:
				_87_zn = zn
				_87_zr = zr
			elif zn != _87_zn or zr != _87_zr:
				_87_zflips += 1
				zone_flip = true
				_87_zn = zn
				_87_zr = zr
			var dn := rn3.position.distance_to(_87_rn.position)
			var dr := rred3.position.distance_to(_87_rred.position)
			if _87_frames > 0 and (zone_flip or dn >= 1.0 or dr >= 1.0):
				_87_consec = 0 # still moving: transient continues
			else:
				_87_consec += 1
				if _87_frames > 0:
					_87_maxdelta = maxf(_87_maxdelta, maxf(dn, dr))
					_87_maxres = maxf(_87_maxres, maxf(
						_zone_residual(rn3, zn, gn3, rr3p),
						_zone_residual(rred3, zr, gr3, rr3p)))
			_87_rn = rn3
			_87_rred = rred3
			_87_frames += 1
			if _87_frames > 120:
				_check(false, "#87 placements settle to a fixed point - no oscillation (never stabilized)")
				_check(not rn3.intersects(rred3), "#87 escaped gate labels do not intersect each other (both behind wide plate)")
				hud.get_node("Root/HPLabel").text = "HP 100/100"
				_stage = 62
				return false
			if _87_consec < 30:
				return false
			# 30 consecutive frames: no zone/candidate change, per-frame movement
			# under 1px. Long window separates camera-lerp drift (continuous,
			# decaying, zone-stable) from feedback alternation (zone flips,
			# which reset the counter and never reach 30).
			print("[50b] #87: labelN=", rn3, " labelRED=", rred3, " zone flips during transient=", _87_zflips, " max per-frame drift in window=", _87_maxdelta, " max zone residual=", _87_maxres)
			_check(not rn3.intersects(rred3), "#87 escaped gate labels do not intersect each other (both behind wide plate)")
			_check(true, "#87 placements settle: no zone/candidate change over 30 consecutive frames (max per-frame drift < 1px = camera settling, not alternation)")
			_check(_87_maxres < 1.0, "#87 within-zone positions track camera/plate exactly (residual < 1px) - feedback alternation excluded by subtraction")
			_check(_tied(rn3, gn3) and _tied(rred3, gr3), "#87 both labels tied to their own gate (row/column)")
			_check(_inside_viewport(rn3) and _inside_viewport(rred3), "#87 both labels inside viewport")
			var rr3b: Rect2 = hud.reserved_rect()
			_check(not rn3.intersects(rr3b) and not rred3.intersects(rr3b), "#87 both labels still clear of the plate")
			hud.get_node("Root/HPLabel").text = "HP 100/100"
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
			_check(_inside_viewport(rn), "GateNormal label inside viewport (portrait)")
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
