extends SceneTree
## Gate portal look: oval body and rim, tinted light, tinted additive
## particles, unchanged 52x72 collision, distinct NORMAL vs RED palettes.

var fails := 0
var frames := 0
var normal: Gate
var red: Gate

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/gate.tscn")
	normal = packed.instantiate()
	red = packed.instantiate()
	red.gate_type = Gate.GateType.RED
	root.add_child(normal)
	root.add_child(red)

func _check(label: String, ok: bool) -> void:
	if not ok:
		fails += 1
	print("[189] ", label, " -> ", "PASS" if ok else "FAIL")

func _near(a: Vector2, b: Vector2) -> bool:
	return a.distance_to(b) < 0.01

func _color_eq(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.001 and absf(a.g - b.g) < 0.001 and absf(a.b - b.b) < 0.001 and absf(a.a - b.a) < 0.001

func _check_gate(g: Gate, where: String, tint: Color, glow: Color) -> void:
	var rim: Line2D = g.get_node_or_null("Rim")
	_check(where + ": rim is a closed 48-point ellipse 24 wide-radius x 34 tall-radius",
		rim != null and rim.closed and rim.points.size() == 48
		and _near(rim.points[0], Vector2(24, 0)) and _near(rim.points[12], Vector2(0, 34))
		and _near(rim.points[24], Vector2(-24, 0)) and _near(rim.points[36], Vector2(0, -34)))
	_check(where + ": rim glows in the light tint", rim != null and _color_eq(rim.default_color, glow))
	var body: Polygon2D = g.get_node_or_null("Body")
	_check(where + ": body is an oval disc, dark core fading to the tint at the 24x34 edge",
		body != null and body.polygon.size() == 96 and body.polygons.size() == 48
		and _near(body.polygon[0], Vector2.ZERO) and _near(body.polygon[48], Vector2(24, 0))
		and _near(body.polygon[60], Vector2(0, 34))
		and _color_eq(body.vertex_colors[48], tint) and _color_eq(body.vertex_colors[0], tint.darkened(0.85)))
	var light: PointLight2D = g.get_node_or_null("Light")
	_check(where + ": light at gate center in the tint with a radial texture",
		light != null and light.enabled and light.position == Vector2.ZERO
		and _color_eq(light.color, tint) and light.energy > 0.5 and light.energy < 1.2
		and light.texture is GradientTexture2D
		and (light.texture as GradientTexture2D).fill == GradientTexture2D.FILL_RADIAL)
	var particles: CPUParticles2D = g.get_node_or_null("Particles")
	_check(where + ": particles emit from the 48 rim points in the light tint, additive",
		particles != null and particles.emitting and particles.amount == 28
		and particles.emission_shape == CPUParticles2D.EMISSION_SHAPE_POINTS
		and particles.emission_points.size() == 48 and _near(particles.emission_points[12], Vector2(0, 34))
		and _color_eq(particles.color, glow)
		and particles.material is CanvasItemMaterial
		and (particles.material as CanvasItemMaterial).blend_mode == CanvasItemMaterial.BLEND_MODE_ADD)
	var cs: CollisionShape2D = g.get_node_or_null("CollisionShape2D")
	_check(where + ": collision still a 52x72 rectangle at the gate origin",
		cs != null and cs.position == Vector2.ZERO and cs.shape is RectangleShape2D
		and (cs.shape as RectangleShape2D).size == Vector2(52, 72))
	_check(where + ": old rectangular decor is gone",
		g.get_node_or_null("HeaderBar") == null and g.get_node_or_null("ChevronTop") == null
		and g.get_node_or_null("ChevronBottom") == null)
	var rect: ColorRect = g.get_node_or_null("ColorRect")
	_check(where + ": footprint ColorRect hidden and carries the tint",
		rect != null and not rect.visible and _color_eq(rect.color, tint))

func _process(_delta: float) -> bool:
	frames += 1
	if frames < 3:
		return false
	_check_gate(normal, "NORMAL", Color(0.15, 0.6, 0.9), Color(0.66, 0.84, 0.96))
	_check_gate(red, "RED", Color(0.85, 0.15, 0.15), Color(0.94, 0.66, 0.66))
	var nl: PointLight2D = normal.get_node("Light")
	var rl: PointLight2D = red.get_node("Light")
	_check("NORMAL and RED light colors differ", not _color_eq(nl.color, rl.color))
	var np: CPUParticles2D = normal.get_node("Particles")
	var rp: CPUParticles2D = red.get_node("Particles")
	_check("NORMAL and RED particle colors differ", not _color_eq(np.color, rp.color))
	if fails == 0:
		print("[189] ALL PASS")
	print("[189] DONE fails=", fails)
	quit(1 if fails > 0 else 0)
	return true
