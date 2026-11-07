extends SceneTree
## #90 (Graphics B) harness: enemy visual identity - shape-first threat
## readability via a jagged Polygon2D silhouette (orange family), visual
## nodes only in scenes/enemy.tscn. Collision, scripts, combat unchanged.
##
## Legs (stringly loads so the harness RUNS on base 1a4756e and FAILs):
##   (a) collision unchanged: CollisionShape2D circle radius == 13.0.
##   (b) jagged silhouette: an outer Polygon2D with >= 8 vertices, ALL
##       within radius <= 13.5 (visual footprint never exceeds r13).
##   (c) orange family fill: r > g > b and r >= 0.8.
##   (d) square language removed: NO ColorRect child (distinct from the
##       player's square and pickup squares).
##   (e) script attachment unchanged: still res://scripts/enemy.gd.
##   (f) mounts clean: instantiates, _ready runs, hp == 30.
## FAIL-when-broken: (b)/(d) FAIL on base 1a4756e (ColorRect square, no
## Polygon2D).

var failures := 0

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[90] ", name, " -> PASS")
	else:
		failures += 1
		print("[90] ", name, " -> FAIL")

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/enemy.tscn")
	_check(scene != null, "(0) enemy.tscn loads")
	if scene == null:
		print("[90] DONE failures=", failures)
		quit(failures)
		return
	var e: Node2D = scene.instantiate() as Node2D
	root.add_child(e)

	# (a) collision unchanged.
	var cs: CollisionShape2D = e.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var radius: float = -1.0
	if cs != null and cs.shape is CircleShape2D:
		radius = (cs.shape as CircleShape2D).radius
	_check(is_equal_approx(radius, 13.0), "(a) collision circle radius unchanged (13.0, got %.2f)" % radius)

	# (b) jagged silhouette within footprint.
	var outer: Polygon2D = null
	for c in e.get_children():
		if c is Polygon2D and (c as Polygon2D).scale == Vector2.ONE:
			outer = c as Polygon2D
			break
	var count_ok := false
	var footprint_ok := false
	var max_r := 0.0
	if outer != null:
		var poly: PackedVector2Array = outer.polygon
		count_ok = poly.size() >= 8
		footprint_ok = poly.size() > 0
		for v in poly:
			max_r = maxf(max_r, v.length())
			if v.length() > 13.5:
				footprint_ok = false
	_check(outer != null and count_ok, "(b) jagged Polygon2D silhouette present (>= 8 vertices)")
	_check(footprint_ok, "(b) all vertices within r13.5 footprint (max %.2f)" % max_r)

	# (c) orange family fill.
	var col_ok := false
	if outer != null:
		var c: Color = outer.color
		col_ok = c.r > c.g and c.g > c.b and c.r >= 0.8
	_check(col_ok, "(c) orange family fill (r > g > b, r >= 0.8)")

	# (d) square language removed.
	var has_colorrect := false
	for c in e.get_children():
		if c is ColorRect:
			has_colorrect = true
	_check(not has_colorrect, "(d) no ColorRect child (square language removed)")

	# (e) script attachment unchanged.
	var s: Script = e.get_script()
	_check(s != null and s.resource_path == "res://scripts/enemy.gd", "(e) script still res://scripts/enemy.gd")

	# (f) mounts clean (_ready defers to the first frame in a SceneTree harness).
	await process_frame
	_check(e.get("hp") == 30, "(f) mounts clean, hp 30 after ready")

	print("[90] DONE failures=", failures)
	quit(failures)
