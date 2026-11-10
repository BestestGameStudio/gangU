extends SceneTree
## #204 acceptance driver (headless, production composition via main.tscn).
## RED DungeonB exit-portal look: the locked gate and the exit gate are the
## same ExitPortal in its two states, so both get the #195 portal look behind
## the red_portal_look flag. Legs:
##   flat    - flag OFF (standalone instance, the default for every non-RED
##             mount): flat decor untouched, no portal nodes built/shown
##   locked  - real red-gate entry into DungeonB: portal mounted locked with
##             the look ON - desaturated gray 48-point portal, LOCKED text,
##             dimmed gray particles, hidden flat decor, 52x72 collision,
##             entry blocked while locked
##   unlock  - killing DungeonB's 3 mobs + the warlord they gate
##             (apply_damage shortcut, not natural combat) completes the
##             production objective: EXIT text, RED portal tint, entry
##             allowed, the portal look persists
## Gate use follows the test9/test91 direct _on_body_entered idiom - NOT
## real-input movement proof.

const RED_TINT := Color(0.85, 0.15, 0.15)
const GRAY_TINT := Color(0.4, 0.4, 0.45)

var scene: Node
var p: CharacterBody2D
var portal: ExitPortal
var phase := 0
var t := 0.0
var fails := 0
var entered_emitted := false

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene

func _check(label: String, ok: bool) -> void:
	if not ok:
		fails += 1
	print("[204] ", label, " -> ", "PASS" if ok else "FAIL")

func _near(a: Vector2, b: Vector2) -> bool:
	return a.distance_to(b) < 0.01

func _color_eq(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.001 and absf(a.g - b.g) < 0.001 and absf(a.b - b.b) < 0.001 and absf(a.a - b.a) < 0.001

func _check_flat_leg() -> void:
	var flat: ExitPortal = load("res://scenes/exit_portal.tscn").instantiate()
	root.add_child(flat)
	_check("flat: flag defaults OFF", not flat.red_portal_look)
	var tint: ColorRect = flat.get_node_or_null("ColorRect")
	_check("flat: ColorRect visible with the unlocked purple tint",
		tint != null and tint.visible and _color_eq(tint.color, Color(0.5, 0.2, 0.8)))
	var arrow: Polygon2D = flat.get_node_or_null("ExitArrow")
	_check("flat: ExitArrow visible", arrow != null and arrow.visible)
	var halo: Polygon2D = flat.get_node_or_null("Halo")
	var rim: Line2D = flat.get_node_or_null("Rim")
	_check("flat: no portal geometry built or shown",
		halo != null and halo.polygon.is_empty() and not halo.visible
		and rim != null and rim.points.is_empty() and not rim.visible)
	var light: PointLight2D = flat.get_node_or_null("Light")
	var particles: CPUParticles2D = flat.get_node_or_null("Particles")
	_check("flat: light and particles stay off",
		light != null and not light.visible
		and particles != null and not particles.emitting and not particles.visible)
	_check("flat: StateLabel EXIT", (flat.get_node("StateLabel") as Label).text == "EXIT")
	flat.queue_free()

func _check_portal_geometry(tint: Color, where: String) -> void:
	var glow := tint.lightened(0.6)
	var rim: Line2D = portal.get_node_or_null("Rim")
	_check(where + ": rim is a visible closed 48-point 24x34 ellipse in the tint glow",
		rim != null and rim.visible and rim.closed and rim.points.size() == 48
		and _near(rim.points[0], Vector2(24, 0)) and _near(rim.points[12], Vector2(0, 34))
		and _color_eq(rim.default_color, glow))
	var body: Polygon2D = portal.get_node_or_null("Body")
	_check(where + ": body is a visible oval band, dark core to tint edge",
		body != null and body.visible and body.polygon.size() == 96 and body.polygons.size() == 48
		and _color_eq(body.vertex_colors[48], tint) and _color_eq(body.vertex_colors[0], tint.darkened(0.85)))
	var halo: Polygon2D = portal.get_node_or_null("Halo")
	_check(where + ": halo band fades the tint outward",
		halo != null and halo.visible and halo.polygon.size() == 96
		and _color_eq(halo.vertex_colors[0], Color(tint, 0.45)))
	var light: PointLight2D = portal.get_node_or_null("Light")
	_check(where + ": light on in the tint",
		light != null and light.visible and _color_eq(light.color, tint))
	var particles: CPUParticles2D = portal.get_node_or_null("Particles")
	_check(where + ": particles emitting from the rim in the tint glow",
		particles != null and particles.visible and particles.emitting
		and particles.emission_points.size() == 48 and _color_eq(particles.color, glow))

func _process(delta: float) -> bool:
	t += delta
	match phase:
		0:
			if scene.get_node_or_null("Player") != null and t > 0.4:
				p = scene.get_node("Player")
				_check("hub boot", scene.area_loader.current_area.name == "Hub")
				_check_flat_leg()
				scene.area_loader.enter_overworld() # #346: dungeon entrances live in the overworld
				var red: Gate = scene.area_loader.current_area.get_node_or_null("GateRed")
				_check("overworld: red gate present", red != null)
				red.gate_type = Gate.GateType.RED # #350 pin: offerings roll 50/50 per run (test350 covers the roll)
				red._on_body_entered(p)
				phase = 1; t = 0
		1:
			if t > 0.5:
				_check("red-gate entry into DungeonB", scene.area_loader.current_area.name == "DungeonB")
				portal = scene.area_loader.current_area.get_node_or_null("ExitPortal")
				_check("portal present", portal != null)
				if portal == null:
					return _finish()
				_check("main.gd mounts the flag ON for DungeonB only", portal.red_portal_look)
				_check("portal mounted locked (completable ELIMINATION objective)", portal.locked)
				_check("locked: StateLabel LOCKED", (portal.get_node("StateLabel") as Label).text == "LOCKED")
				var tint: ColorRect = portal.get_node("ColorRect")
				_check("locked: flat decor hidden, tint record kept gray",
					not tint.visible and _color_eq(tint.color, Color(0.35, 0.35, 0.4))
					and not (portal.get_node("ExitArrow") as Polygon2D).visible)
				_check_portal_geometry(GRAY_TINT, "locked")
				var cs: CollisionShape2D = portal.get_node_or_null("CollisionShape2D")
				_check("locked: collision RectangleShape2D (52,72) untouched",
					cs != null and cs.shape is RectangleShape2D and cs.shape.size == Vector2(52, 72))
				portal.entered.connect(func(_x): entered_emitted = true)
				portal._on_body_entered(p)
				phase = 2; t = 0
		2:
			if t > 0.3:
				_check("locked: entry blocked (no entered signal)", not entered_emitted)
				_check("locked: still in DungeonB", scene.area_loader.current_area.name == "DungeonB")
				# DungeonB mounts its SpawnData mobs (#177, #472 Fishy) gating the
				# warlord boss. Kill them via the public damage path - a shortcut,
				# not natural combat; the boss then spawns (deferred add).
				var mobs := get_nodes_in_group("enemies")
				var spawn_entries: int = scene.area_loader.current_area.get_node("SpawnData").entries.size()
				_check("DungeonB mounts one objective mob per SpawnData entry (got %d of %d)" % [mobs.size(), spawn_entries],
					spawn_entries > 0 and mobs.size() == spawn_entries)
				for e in mobs:
					e.apply_damage(999999)
				phase = 3; t = 0
		3:
			if t > 0.6:
				var boss: Node = null
				for b in get_nodes_in_group("boss"):
					boss = b
				_check("warlord boss spawned after the mobs died", boss != null)
				if boss == null:
					_finish()
					return true
				boss.apply_damage(999999)
				phase = 4; t = 0
		4:
			if t > 0.5:
				_check("objective cleared -> portal unlocked", not portal.locked)
				_check("unlocked: StateLabel EXIT", (portal.get_node("StateLabel") as Label).text == "EXIT")
				_check("unlocked: flat decor stays hidden, tint record purple",
					not (portal.get_node("ColorRect") as ColorRect).visible
					and _color_eq((portal.get_node("ColorRect") as ColorRect).color, Color(0.5, 0.2, 0.8)))
				_check_portal_geometry(RED_TINT, "unlocked")
				_check("portal look persists after unlock (rim still built and shown)",
					(portal.get_node("Rim") as Line2D).visible
					and (portal.get_node("Rim") as Line2D).points.size() == 48)
				portal._on_body_entered(p)
				_check("unlocked: entry allowed (entered emitted)", entered_emitted)
				_finish()
	return false

func _finish() -> bool:
	if fails == 0:
		print("[204] ALL PASS")
	print("[204] DONE fails=", fails)
	quit(1 if fails > 0 else 0)
	return true
