extends SceneTree
## #106 harness: gate labels stay ATTACHED while the player MOVES - the bug
## Colin reported 2026-11-07 ("moving around, the HUD pushes the normal and
## red text around"). Drives production main.tscn at the real 1152x648
## logical viewport and walks the player continuously in four directions.
## EVERY frame, for each hub gate:
##   gate body on screen   => label VISIBLE and ATTACHED (center within
##                            90px of the gate's screen center)
##   gate body off screen  => label HIDDEN (never clamped mid-screen)
## FAIL-when-broken on pre-fix main (1a4756e): the #50/#84/#87 contract
## escapes the label ~150px right of the plate (attach FAIL) and clamps
## labels mid-screen for off-screen gates (hidden FAIL).
## Movement is DIRECT player repositioning in small per-frame steps (the
## camera follows through its real lerp) - not real input proof.

const ATTACH_MAX := 90.0
const STEP := 3.0

var failures := 0
var violations := 0
var frames_checked := 0
var offscreen_frames := 0
var main: Node
var frame := 0
var stage := 0
var dir := Vector2.UP
var steps_left := 0

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[106] ", name, " -> PASS")
	else:
		failures += 1
		print("[106] ", name, " -> FAIL")

func _gate_body_rect(gate: Gate) -> Rect2:
	var canvas := root.get_canvas_transform()
	var body: ColorRect = gate.get_node("ColorRect")
	return Rect2(canvas * (gate.global_position + body.position), body.size * body.scale)

func _label_rect(gate: Gate) -> Rect2:
	var canvas := root.get_canvas_transform()
	var lbl: Label = gate.get_node("TypeLabel")
	var size := Vector2(52, 23)
	var font := lbl.get_theme_font("font")
	var fs := lbl.get_theme_font_size("font_size")
	if font != null and lbl.text != "":
		var ts := font.get_string_size(lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		size = Vector2(maxf(52.0, ts.x), maxf(23.0, ts.y))
	return Rect2(canvas * (gate.global_position + lbl.position), size)

var _prev_body := {}

func _sweep_frame() -> void:
	var p: Player = main.get_node("Player") as Player
	p.global_position += dir * STEP
	frames_checked += 1
	var view := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	# Timing: this MainLoop _process runs BEFORE the gates' node _process, so
	# the label state readable here was placed with LAST frame's canvas.
	# Visibility is asserted against LAST frame's body rect (same canvas the
	# gate used). The attach distance is canvas-invariant (gates are static
	# and the transform is translate-only), so it uses the live label offset.
	for gname in ["GateNormal", "GateRed"]:
		var gate: Gate = main.current_area.get_node(gname)
		var lbl: Label = gate.get_node("TypeLabel")
		if _prev_body.has(gname):
			var prev: Rect2 = _prev_body[gname]
			var gs: Vector2 = root.get_canvas_transform() * gate.global_position
			var d: float = _label_rect(gate).get_center().distance_to(gs)
			if prev.intersects(view):
				if not lbl.visible or d > ATTACH_MAX:
					violations += 1
					if violations <= 3:
						print("[106] VIOLATION frame ", frames_checked, " ", gname, " visible=", lbl.visible, " attach_dist=", d)
			else:
				offscreen_frames += 1
				if lbl.visible:
					violations += 1
					if violations <= 3:
						print("[106] VIOLATION frame ", frames_checked, " ", gname, " label visible while gate off-screen")
		_prev_body[gname] = _gate_body_rect(gate)

func _initialize() -> void:
	root.size = Vector2i(1152, 648)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_size = Vector2i(1152, 648)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	frame += 1
	if main.current_area == null or main.current_area.get_node_or_null("GateNormal") == null:
		if frame > 600:
			print("[106] hub never mounted -> FAIL")
			quit(1)
		return false
	match stage:
		0:
			if frame < 30:
				return false # camera settle
			_check(true, "setup: hub mounted with both gates")
			dir = Vector2.UP
			steps_left = 300 # 900px up: gates exit the bottom edge
			stage = 1
		1:
			_sweep_frame()
			steps_left -= 1
			if steps_left <= 0:
				dir = Vector2.DOWN
				steps_left = 400 # 1200px down, past spawn: gates exit the top edge
				stage = 2
		2:
			_sweep_frame()
			steps_left -= 1
			if steps_left <= 0:
				dir = Vector2.RIGHT
				steps_left = 300
				stage = 3
		3:
			_sweep_frame()
			steps_left -= 1
			if steps_left <= 0:
				dir = Vector2.LEFT
				steps_left = 300
				stage = 4
		4:
			_sweep_frame()
			steps_left -= 1
			if steps_left <= 0:
				stage = 5
		5:
			print("[106] frames checked=", frames_checked, " off-screen gate frames=", offscreen_frames, " violations=", violations)
			_check(frames_checked >= 1000, "moving sweep covered 1000+ frames")
			_check(offscreen_frames > 50, "sweep actually pushed gates off-screen (hidden leg has teeth)")
			_check(violations == 0, "EVERY moving frame: labels attached while gate on screen, hidden while off")
			print("[106] DONE failures=", failures)
			quit(failures)
	return false
