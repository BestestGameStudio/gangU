extends SceneTree
## #96 acceptance driver (headless). Proves the projectile visual identity +
## direction readability pass within its exact window:
##   dart       - NEW root-sibling "Dart" Polygon2D, exact flat arrowhead
##                geometry authored pointing +X; root rotation faces flight
##                direction (setup + homing steer already rotate the root)
##   tint/scale - Dart gets spell.projectile_color and radius/4 scale, same
##                as the core (fire_ball orange/2.25, homing beam cyan/3.5)
##   preserved  - Visual diamond core polygon + tint + radius scale
##                unchanged; spin/pulse constants unchanged; Visual still
##                spins in flight while the Dart does NOT rotate locally;
##                collision circle r4 scene base unchanged (per-spell
##                radius behavior identical to base)
## The dart legs FAIL on the old base (no Dart node) - meaningful negative.

const DART_POLY: Array[Vector2] = [Vector2(12, 0), Vector2(-4, 5), Vector2(-1, 0), Vector2(-4, -5)]
const CORE_POLY: Array[Vector2] = [Vector2(-4, 0), Vector2(0, -4), Vector2(4, 0), Vector2(0, 4)]

var failures := 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("[96] ", label, " -> PASS")
	else:
		failures += 1
		print("[96] ", label, " -> FAIL")

func _poly_pts(p: Polygon2D) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for v in p.polygon:
		out.append(v)
	return out

func _spawn(spell: Spell, dir: Vector2) -> Area2D:
	var p: Area2D = load("res://scenes/projectile.tscn").instantiate()
	var src := Node2D.new()
	get_root().add_child(src)
	p.setup(spell, dir, src)
	get_root().add_child(p)
	return p

func _initialize() -> void:
	var root := get_root()

	# ---- scene structure (stringly-loaded, unspawned) ----
	var scene: PackedScene = load("res://scenes/projectile.tscn")
	var probe: Area2D = scene.instantiate()
	var dart_scene := probe.get_node_or_null("Dart") as Polygon2D
	_check(dart_scene != null, "Dart Polygon2D present as root child")
	_check(dart_scene != null and _poly_pts(dart_scene) == DART_POLY, "Dart exact arrowhead geometry (+X tip)")
	var vis_scene := probe.get_node_or_null("Visual") as Polygon2D
	_check(vis_scene != null and _poly_pts(vis_scene) == CORE_POLY, "Visual diamond core polygon unchanged")
	var col_scene := probe.get_node_or_null("CollisionShape2D") as CollisionShape2D
	_check(col_scene != null and col_scene.shape is CircleShape2D and is_equal_approx(col_scene.shape.radius, 4.0), "collision circle r4 scene base unchanged")
	probe.free()

	# ---- direction legibility of the authored shape ----
	var xs := DART_POLY.map(func(v): return v.x)
	_check(xs.max() >= 2.0 * absf(xs.min()), "dart forward-asymmetric (tip clearly ahead of tail)")

	# ---- per-spell tint + radius scale (fire_ball r9 orange) ----
	var fire: Spell = load("res://resources/spells/fire_ball.tres")
	var p1 := _spawn(fire, Vector2.RIGHT)
	await process_frame # _ready (tint/scale) applies on the first idle frame
	var d1 := p1.get_node_or_null("Dart") as Polygon2D
	_check(d1 != null, "spawned Dart present (fire_ball)")
	if d1 != null:
		_check(d1.color == fire.projectile_color, "Dart per-spell tint (fire orange)")
		_check(is_equal_approx(d1.scale.x, fire.radius / 4.0) and is_equal_approx(d1.scale.y, fire.radius / 4.0), "Dart radius scale (9/4=2.25)")
		_check(is_zero_approx(d1.rotation), "Dart local rotation zero (root faces direction)")
	_check(is_zero_approx(p1.rotation), "root rotation faces +X for +X flight")

	# ---- per-spell tint + radius scale (homing beam r14 cyan) + angled flight ----
	var hom: Spell = load("res://resources/spells/fire_ball_beam_homing.tres")
	var p2 := _spawn(hom, Vector2(0, -1))
	await process_frame
	var d2 := p2.get_node_or_null("Dart") as Polygon2D
	_check(d2 != null and d2.color == hom.projectile_color, "Dart per-spell tint (homing cyan)")
	_check(d2 != null and is_equal_approx(d2.scale.x, hom.radius / 4.0), "Dart radius scale (14/4=3.5)")
	_check(is_equal_approx(p2.rotation, -PI / 2.0), "root rotation faces -Y for -Y flight")

	# ---- core preserved (tint, scale) ----
	var v1 := p1.get_node("Visual") as Polygon2D
	_check(v1.color == fire.projectile_color, "Visual core tint preserved")
	_check(absf(v1.scale.x - 2.25) < 0.6, "Visual core scale preserved (2.25 +/- pulse)")

	# ---- feel + gameplay constants unchanged ----
	_check(Projectile.SPIN_RATE == 12.0 and Projectile.PULSE_RATE == 10.0 and Projectile.PULSE_AMP == 0.15, "spin/pulse constants unchanged")
	_check(Projectile.HOMING_RANGE == 400.0 and Projectile.HOMING_TURN_RATE == 6.0, "homing constants unchanged")

	# ---- in flight: core spins, dart does not rotate locally ----
	for i in 20:
		await physics_frame
	_check(absf(v1.rotation) > 0.1, "Visual core still spins in flight")
	_check(d1 != null and is_zero_approx(d1.rotation), "Dart holds direction in flight (no local spin)")

	print("[96] DONE failures=%d" % failures)
	quit(1 if failures > 0 else 0)
