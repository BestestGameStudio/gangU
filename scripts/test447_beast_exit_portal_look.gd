extends SceneTree
## #447 harness: the Beast den's exit portal gets the portal look in purple
## (Daniel 2026-11-09: "exit portal should look like the other portals,
## purple", "just copy the other portals", locked state: "use the existing
## locked portal"). Legs:
##   flat    - beast_portal_look defaults OFF: flat decor untouched
##   locked  - production GateBeast -> DungeonD: portal mounted locked with
##             the look ON, existing gray LOCKED look, entry blocked
##   unlock  - synthetic Beast kill: EXIT text, EXIT_PURPLE portal geometry,
##             entry allowed, transport returns to the overworld (#378)
## Kills are synthetic apply_damage calls, not natural combat.
## Run: godot --headless --path . --script scripts/test447_beast_exit_portal_look.gd

const GRAY_TINT := Color(0.4, 0.4, 0.45)
const PURPLE := Color(0.5, 0.2, 0.8)

var failures := 0
var portal: ExitPortal

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[447] ", name, " -> PASS")
	else:
		failures += 1
		print("[447] ", name, " -> FAIL")

func _physics(n: int) -> void:
	for i in n:
		await physics_frame

func _near(a: Vector2, b: Vector2) -> bool:
	return a.distance_to(b) < 0.01

func _color_eq(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.001 and absf(a.g - b.g) < 0.001 and absf(a.b - b.b) < 0.001 and absf(a.a - b.a) < 0.001

func _initialize() -> void:
	_leg_flat()
	await _leg_production()
	print("[447] DONE failures=", failures)
	print("RESULT: ALL PASS" if failures == 0 else "RESULT: FAIL")
	quit(failures)

func _leg_flat() -> void:
	var flat: ExitPortal = load("res://scenes/exit_portal.tscn").instantiate()
	root.add_child(flat)
	_check(not flat.beast_portal_look, "flat: beast flag defaults OFF")
	_check(not flat.red_portal_look, "flat: red flag still defaults OFF")
	var tint: ColorRect = flat.get_node_or_null("ColorRect")
	_check(tint != null and tint.visible and _color_eq(tint.color, PURPLE),
		"flat: ColorRect visible with the unlocked purple tint")
	var rim: Line2D = flat.get_node_or_null("Rim")
	_check(rim != null and rim.points.is_empty() and not rim.visible,
		"flat: no portal geometry built or shown")
	flat.free()

func _check_portal_geometry(tint: Color, where: String) -> void:
	var glow := tint.lightened(0.6)
	var rim: Line2D = portal.get_node_or_null("Rim")
	_check(rim != null and rim.visible and rim.closed and rim.points.size() == 48
		and _near(rim.points[0], Vector2(24, 0)) and _near(rim.points[12], Vector2(0, 34))
		and _color_eq(rim.default_color, glow),
		where + ": rim is a visible closed 48-point 24x34 ellipse in the tint glow")
	var body: Polygon2D = portal.get_node_or_null("Body")
	_check(body != null and body.visible and body.polygon.size() == 96 and body.polygons.size() == 48
		and _color_eq(body.vertex_colors[48], tint) and _color_eq(body.vertex_colors[0], tint.darkened(0.85)),
		where + ": body is a visible oval band, dark core to tint edge")
	var halo: Polygon2D = portal.get_node_or_null("Halo")
	_check(halo != null and halo.visible and halo.polygon.size() == 96
		and _color_eq(halo.vertex_colors[0], Color(tint, 0.45)),
		where + ": halo band fades the tint outward")
	var light: PointLight2D = portal.get_node_or_null("Light")
	_check(light != null and light.visible and _color_eq(light.color, tint),
		where + ": light on in the tint")
	var particles: CPUParticles2D = portal.get_node_or_null("Particles")
	_check(particles != null and particles.visible and particles.emitting
		and particles.emission_points.size() == 48 and _color_eq(particles.color, glow),
		where + ": particles emitting from the rim in the tint glow")

func _leg_production() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var p: Player = scene.get_node("Player")
	scene.area_loader.enter_overworld()
	await process_frame
	var gate := scene.area_loader.current_area.get_node_or_null("GateBeast") as Gate
	_check(gate != null, "production: GateBeast present in the overworld")
	if gate == null:
		return
	gate._on_body_entered(p)
	await _physics(4)
	_check(scene.area_loader.current_area.name == "DungeonD", "production: GateBeast enters DungeonD")
	portal = scene.area_loader.current_area.get_node_or_null("ExitPortal") as ExitPortal
	_check(portal != null, "production: exit portal mounted")
	if portal == null:
		return
	_check(portal.beast_portal_look, "production: main.gd mounts the beast look ON for DungeonD")
	_check(not portal.red_portal_look, "production: red flag stays OFF on DungeonD")
	_check(portal.locked, "locked: portal locked while the Beast lives")
	_check((portal.get_node("StateLabel") as Label).text == "LOCKED", "locked: StateLabel LOCKED")
	var tint_rec: ColorRect = portal.get_node("ColorRect")
	_check(not tint_rec.visible and _color_eq(tint_rec.color, Color(0.35, 0.35, 0.4))
		and not (portal.get_node("ExitArrow") as Polygon2D).visible,
		"locked: flat decor hidden, tint record kept gray")
	_check_portal_geometry(GRAY_TINT, "locked")
	var entered_emitted := [false]
	portal.entered.connect(func(_x): entered_emitted[0] = true)
	portal._on_body_entered(p)
	await _physics(2)
	_check(not entered_emitted[0], "locked: entry blocked (no entered signal)")

	# Synthetic kill (not natural combat): the Beast dies, objective clears.
	var boss: Node = null
	for b in get_nodes_in_group("boss"):
		boss = b
	_check(boss != null, "production: the Beast spawned on entry")
	if boss == null:
		return
	boss.apply_damage(9999)
	await _physics(4)
	_check(not portal.locked, "unlock: Beast death unlocks the portal")
	_check((portal.get_node("StateLabel") as Label).text == "EXIT", "unlock: StateLabel EXIT")
	_check(not (portal.get_node("ColorRect") as ColorRect).visible,
		"unlock: flat decor stays hidden")
	_check_portal_geometry(PURPLE, "unlock")
	portal._on_body_entered(p)
	await _physics(4)
	_check(entered_emitted[0], "unlock: entry allowed (entered emitted)")
	_check(scene.area_loader.current_area.name == "Overworld", "unlock: transport returns to the overworld entrance (#378)")
	scene.queue_free()
	current_scene = null
	await process_frame
