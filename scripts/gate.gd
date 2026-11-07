class_name Gate
extends Area2D
## #7: gate object. Normal and red gates are distinct in code (gate_type) and
## visuals (tint + label). Entering a gate transports the player to its dungeon.
## Red-gate lock-in rules themselves are #9 scope; this is transport + typing only.

enum GateType { NORMAL, RED }

@export var gate_type: GateType = GateType.NORMAL
@export var target_dungeon: PackedScene

signal entered(gate: Gate)

func _ready() -> void:
	add_to_group("gates")
	body_entered.connect(_on_body_entered)
	var tint: ColorRect = $ColorRect
	var label: Label = $TypeLabel
	if gate_type == GateType.RED:
		tint.color = Color(0.85, 0.15, 0.15)
		label.text = "RED"
	else:
		tint.color = Color(0.15, 0.6, 0.9)
		label.text = "NORMAL"

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		entered.emit(self)

## #50: keep the world TypeLabel clear of the HUD's reserved plate and the
## viewport edge. The camera is unbounded (FollowCamera), so without this a
## gate can slide under the translucent HUD zone while the player walks.
## Per frame: project the label's screen rect through the canvas transform;
## if it intersects HUD.reserved_rect() or exits the viewport, flip the
## label below (then right) and clamp inside the viewport. The label stays
## adjacent to ITS OWN gate - displaced, never detached.
@onready var _type_label: Label = $TypeLabel

## #87: this gate's placed label screen rect, published immediately each
## frame for the other gates' second-tier label avoidance.
var _label_screen_rect := Rect2()
var _label_screen_rect_valid := false

const LABEL_GAP := 6.0

func _process(_delta: float) -> void:
	_update_label_placement()

func _update_label_placement() -> void:
	if _type_label == null:
		return
	var viewport := get_viewport()
	if viewport == null or viewport.get_camera_2d() == null:
		return
	var canvas := viewport.get_canvas_transform()
	var gate_screen: Vector2 = canvas * global_position
	var label_size := Vector2(52, 23)
	var font := _type_label.get_theme_font("font")
	var fs := _type_label.get_theme_font_size("font_size")
	if font != null and _type_label.text != "":
		var ts := font.get_string_size(_type_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		label_size = Vector2(maxf(52.0, ts.x), maxf(23.0, ts.y))
	var view_size := viewport.get_visible_rect().size
	var reserved := Rect2()
	var hud := get_tree().root.find_child("HUD", true, false)
	if hud != null and hud.has_method("reserved_rect"):
		reserved = hud.reserved_rect()
	# #84: an escaped label must also keep clear of OTHER gates' projected
	# body rects (live residual: NORMAL's plate-edge escape clipped by RED's
	# sprite). Read each live gate's actual body ColorRect, no hardcoded size.
	var other_gate_rects: Array[Rect2] = []
	for g in get_tree().get_nodes_in_group("gates"):
		if g == self or not (g is Gate):
			continue
		var body: ColorRect = (g as Gate).get_node_or_null("ColorRect")
		if body == null:
			continue
		var btl: Vector2 = canvas * ((g as Gate).global_position + body.position)
		other_gate_rects.append(Rect2(btl, body.size * body.scale))
	# #87: other gates' current LABEL screen rects are a SECOND tier, read
	# only from live group members. Each gate publishes its rect immediately
	# when it places, so a gate later in tree order sees this frame's rect
	# and a gate earlier in order sees last frame's (1-frame lag only on the
	# transient, never on the settled placement).
	var other_label_rects: Array[Rect2] = []
	for g in get_tree().get_nodes_in_group("gates"):
		if g == self or not (g is Gate):
			continue
		if (g as Gate)._label_screen_rect_valid:
			other_label_rects.append((g as Gate)._label_screen_rect)
	# Candidate top-left positions in preference order: centered on the gate
	# (original), below the gate, right of the gate.
	var candidates := [
		gate_screen + Vector2(-label_size.x / 2.0, -10.0),
		gate_screen + Vector2(-label_size.x / 2.0, 36.0 + LABEL_GAP),
		gate_screen + Vector2(26.0 + LABEL_GAP, -label_size.y / 2.0),
		gate_screen + Vector2(-label_size.x - 26.0 - LABEL_GAP, -label_size.y / 2.0),
	]
	var chosen: Vector2 = candidates[0]
	var found := false
	# #87: collect the body-clear pool in preference order, then prefer the
	# first placement that ALSO clears the other gates' labels. If none
	# does, the body-clear order wins unchanged - a label overlap is the
	# accepted last resort, never a body or plate overlap.
	var pool: Array[Vector2] = []
	for tl in candidates:
		var r := Rect2(tl, label_size)
		var inside := r.position.x >= 0.0 and r.position.y >= 0.0 and r.end.x <= view_size.x and r.end.y <= view_size.y
		var clear := reserved.get_area() <= 0.0 or not r.intersects(reserved)
		if inside and clear and _clear_of_gates(r, other_gate_rects):
			pool.append(tl)
	if pool.is_empty() and reserved.get_area() > 0.0:
		# Plate-edge escapes, tried only after every adjacent candidate
		# failed: right of the plate at the gate's own row, below the plate
		# at the gate's own column. A clamped edge placement is accepted only
		# when it stays clear of the plate - an inside-plate placement is
		# never chosen while an edge placement fits the viewport.
		var edge_candidates := [
			Vector2(reserved.end.x + LABEL_GAP, gate_screen.y - label_size.y / 2.0),
			Vector2(gate_screen.x - label_size.x / 2.0, reserved.end.y + LABEL_GAP),
		]
		# Rejection order prefers the plate side AWAY from a neighboring gate:
		# an edge escape overlapping another gate is refused, so the next edge
		# (the other side of the plate) wins instead.
		for tl in edge_candidates:
			var cl: Vector2 = tl.clamp(Vector2.ZERO, view_size - label_size)
			var r := Rect2(cl, label_size)
			if not r.intersects(reserved) and _clear_of_gates(r, other_gate_rects):
				pool.append(cl)
	if not pool.is_empty():
		chosen = pool[0]
		found = true
		for tl in pool:
			if _clear_of_labels(Rect2(tl, label_size), other_label_rects):
				chosen = tl
				break
	if not found:
		# Every viewport-fitting placement intersects the plate or a
		# neighboring gate (reserved zone plus neighbors leave no room). Keep
		# the label below its own gate, clamped inside the viewport: readable
		# on the plate backing, still tied to its gate.
		chosen = candidates[1].clamp(Vector2.ZERO, view_size - label_size)
	# #87: publish this frame's placed rect immediately. Deterministic tree
	# order lets the later-processed gate defer to its next candidate while
	# the earlier keeps the shared point, so placements settle to a fixed
	# point instead of oscillating (asserted in test50b's #87 leg).
	_label_screen_rect = Rect2(chosen, label_size)
	_label_screen_rect_valid = true
	var world_tl: Vector2 = canvas.affine_inverse() * chosen
	_type_label.position = world_tl - global_position

## #84: true when r intersects no other gate's projected body rect.
func _clear_of_gates(r: Rect2, other_gate_rects: Array[Rect2]) -> bool:
	for ogr in other_gate_rects:
		if r.intersects(ogr):
			return false
	return true

## #87: true when r intersects no other gate's current label rect.
func _clear_of_labels(r: Rect2, other_label_rects: Array[Rect2]) -> bool:
	for olr in other_label_rects:
		if r.intersects(olr):
			return false
	return true
