class_name Gate
extends Area2D
## #7: gate object. Normal and red gates are distinct in code (gate_type) and
## visuals (tint + label). Entering a gate transports the player to its dungeon.
## Red-gate lock-in rules themselves are #9 scope; this is transport + typing only.

enum GateType { NORMAL, RED }

@export var gate_type: GateType = GateType.NORMAL
@export var target_dungeon: PackedScene

signal entered(gate: Gate)

const NORMAL_TINT := Color(0.15, 0.6, 0.9)
const RED_TINT := Color(0.85, 0.15, 0.15)
const PORTAL_RX := 24.0
const PORTAL_RY := 34.0
const PORTAL_POINTS := 48
const HALO_SPREAD := 12.0
const SWIRL_STEPS := 24

var _anim_t := 0.0

func _ready() -> void:
	add_to_group("gates")
	body_entered.connect(_on_body_entered)
	var label: Label = $TypeLabel
	var tint := RED_TINT if gate_type == GateType.RED else NORMAL_TINT
	label.text = "RED" if gate_type == GateType.RED else "NORMAL"
	# The hidden ColorRect is the gate's footprint and tint record: label
	# placement measures neighbor gates by it.
	($ColorRect as ColorRect).color = tint
	_build_portal(tint)

static func ellipse_points(rx: float, ry: float, count: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in count:
		var a := TAU * i / count
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	return pts

## Fills a Polygon2D with the band between two concentric ellipses, colored
## per ring so the GPU blends inner_color to outer_color across it. An inner
## radius of zero makes a radial-gradient disc.
static func _fill_band(poly: Polygon2D, inner: Vector2, inner_color: Color, outer: Vector2, outer_color: Color) -> void:
	var pts := ellipse_points(inner.x, inner.y, PORTAL_POINTS)
	pts.append_array(ellipse_points(outer.x, outer.y, PORTAL_POINTS))
	var colors := PackedColorArray()
	for i in PORTAL_POINTS:
		colors.append(inner_color)
	for i in PORTAL_POINTS:
		colors.append(outer_color)
	var quads: Array = []
	for i in PORTAL_POINTS:
		var j := (i + 1) % PORTAL_POINTS
		quads.append(PackedInt32Array([i, j, PORTAL_POINTS + j, PORTAL_POINTS + i]))
	poly.polygon = pts
	poly.vertex_colors = colors
	poly.polygons = quads

func _build_portal(tint: Color) -> void:
	var rim_color := tint.lightened(0.6)
	_fill_band($Halo, Vector2(PORTAL_RX, PORTAL_RY), Color(tint, 0.45),
		Vector2(PORTAL_RX + HALO_SPREAD, PORTAL_RY + HALO_SPREAD), Color(tint, 0.0))
	_fill_band($Body, Vector2.ZERO, tint.darkened(0.85), Vector2(PORTAL_RX, PORTAL_RY), tint)

	# The swirl is drawn as a circle and squashed by its pivot, so spinning
	# it keeps it inside the ellipse.
	var pivot: Node2D = $SwirlPivot
	pivot.scale = Vector2(1.0, PORTAL_RY / PORTAL_RX)
	var swirl: Line2D = $SwirlPivot/Swirl
	var r := PORTAL_RX * 0.8
	var arm := PackedVector2Array()
	for i in range(SWIRL_STEPS, -1, -1):
		var t := float(i) / SWIRL_STEPS
		arm.append(Vector2.from_angle(t * TAU * 0.9) * r * t)
	for i in range(1, SWIRL_STEPS + 1):
		var t := float(i) / SWIRL_STEPS
		arm.append(Vector2.from_angle(PI + t * TAU * 0.9) * r * t)
	swirl.points = arm
	swirl.default_color = Color(tint.lightened(0.4), 0.55)

	var rim: Line2D = $Rim
	rim.points = ellipse_points(PORTAL_RX, PORTAL_RY, PORTAL_POINTS)
	rim.default_color = rim_color

	var light: PointLight2D = $Light
	light.color = tint

	var particles: CPUParticles2D = $Particles
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	particles.emission_points = ellipse_points(PORTAL_RX, PORTAL_RY, PORTAL_POINTS)
	particles.color = rim_color
	var fade := Gradient.new()
	fade.set_color(0, Color.WHITE)
	fade.set_color(1, Color(1, 1, 1, 0))
	particles.color_ramp = fade
	particles.emitting = true

func _process(delta: float) -> void:
	_anim_t += delta
	var pulse := sin(_anim_t * 2.4)
	($SwirlPivot/Swirl as Line2D).rotation = _anim_t * 1.6
	($Rim as Line2D).width = 2.5 + 0.8 * pulse
	($Light as PointLight2D).energy = 0.9 + 0.15 * pulse
	_update_label_placement()

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		entered.emit(self)

## #106: the label stays ATTACHED to its own gate. The earlier #50/#84/#87
## contract kept the label clear of the HUD plate and inside the viewport at
## all costs, which DETACHED it from its gate (plate-edge escapes ~150px
## away) and clamped it mid-screen when the gate left the viewport - Colin's
## 2026-11-07 report: moving around, the HUD pushes the gate texts around.
## The plate is translucent: the gate body already renders dimmed under it,
## so the label simply rides with its gate and dims the same way. A gate
## fully outside the viewport HIDES its label instead of clamping it into
## view. Adjacent-candidate avoidance (#84 bodies, #87 labels) is retained
## so neighboring gates never stack labels.
@onready var _type_label: Label = $TypeLabel

## #87: this gate's placed label screen rect, published immediately each
## frame for the other gates' second-tier label avoidance. Invalid while
## the label is hidden (off-screen gate): hidden labels push nothing.
var _label_screen_rect := Rect2()
var _label_screen_rect_valid := false

const LABEL_GAP := 6.0

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
	# #84: keep clear of OTHER gates' projected body rects (read live).
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
	# only from live group members (1-frame lag on the transient only).
	var other_label_rects: Array[Rect2] = []
	for g in get_tree().get_nodes_in_group("gates"):
		if g == self or not (g is Gate):
			continue
		if (g as Gate)._label_screen_rect_valid:
			other_label_rects.append((g as Gate)._label_screen_rect)
	# #106: attached candidates only - above (original), below, right, left
	# of THIS gate. No plate exclusion and no viewport containment: the
	# label moves WITH its gate - sliding under the translucent plate or
	# partly off-screen exactly like the gate body does.
	var candidates := [
		gate_screen + Vector2(-label_size.x / 2.0, -10.0),
		gate_screen + Vector2(-label_size.x / 2.0, 36.0 + LABEL_GAP),
		gate_screen + Vector2(26.0 + LABEL_GAP, -label_size.y / 2.0),
		gate_screen + Vector2(-label_size.x - 26.0 - LABEL_GAP, -label_size.y / 2.0),
	]
	var pool: Array[Vector2] = []
	for tl in candidates:
		if _clear_of_gates(Rect2(tl, label_size), other_gate_rects):
			pool.append(tl)
	if pool.is_empty():
		pool.append(candidates[0])
	var chosen: Vector2 = pool[0]
	for tl in pool:
		if _clear_of_labels(Rect2(tl, label_size), other_label_rects):
			chosen = tl
			break
	# #106: visibility follows the gate BODY: any on-screen part shows the
	# label; a fully off-screen gate hides it (never clamped mid-screen).
	var my_body: ColorRect = get_node_or_null("ColorRect")
	var body_rect := Rect2(gate_screen - Vector2(26, 36), Vector2(52, 72))
	if my_body != null:
		var my_tl: Vector2 = canvas * (global_position + my_body.position)
		body_rect = Rect2(my_tl, my_body.size * my_body.scale)
	var on_screen := body_rect.intersects(Rect2(Vector2.ZERO, view_size))
	_type_label.visible = on_screen
	# #87: publish this frame's placed rect immediately (deterministic tree
	# order; settles to a fixed point instead of oscillating).
	_label_screen_rect = Rect2(chosen, label_size)
	_label_screen_rect_valid = on_screen
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
