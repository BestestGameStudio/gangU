extends SceneTree
## #92 (Graphics C2) harness: ground-item visual identity - spell pickup,
## reward drop, revive item each get distinct flat decoration AROUND their
## existing dominant fill. Visual nodes only; collision, scripts, logic,
## reward pools/tables unchanged. revive_satchel.tscn deliberately untouched
## (logic-only node, no visual presence).
##
## Legs (stringly loads so the harness RUNS on base c593493 and FAILs):
##   (0) scenes load.
##   (a) collision unchanged: pickup r24, reward r24, revive r14.
##   (b) preserved refs: pickup ColorRect + NameLabel; reward Visual is a
##       Polygon2D + NameLabel; revive Visual is a Polygon2D (12-vert cross).
##   (c) root scripts unchanged.
##   (d) decoration present: a Decor Node2D with Polygon2D children:
##       pickup 4, reward 1, revive 4.
##   (e) decor signatures: pickup ticks 6 verts each; reward ring 26 verts;
##       revive dots 8 verts each - three mutually distinct signatures.
##   (f) fill dominance: decor colors are neutral/desaturated (channel
##       spread < 0.2) so the script-set / scene fill color stays the
##       dominant read; reward ring vertices all sit at radius >= 13.5,
##       never covering the r12 dynamic diamond.
##   (g) footprint sanity: every decor vertex within radius <= 40.
## FAIL-when-broken: (d)/(e) FAIL on base c593493 (no Decor nodes).

var failures := 0

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[92] ", name, " -> PASS")
	else:
		failures += 1
		print("[92] ", name, " -> FAIL")

func _radius_of(e: Node) -> float:
	var cs: CollisionShape2D = e.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is CircleShape2D:
		return (cs.shape as CircleShape2D).radius
	return -1.0

func _decor_polys(e: Node) -> Array:
	var out: Array = []
	var d: Node = e.get_node_or_null("Decor")
	if d != null:
		for c in d.get_children():
			if c is Polygon2D:
				out.append(c)
	return out

func _max_spread(polys: Array) -> float:
	var worst := 0.0
	for p in polys:
		var c: Color = (p as Polygon2D).color
		worst = maxf(worst, maxf(maxf(absf(c.r - c.g), absf(c.g - c.b)), absf(c.r - c.b)))
	return worst

func _min_vertex_radius(p: Polygon2D) -> float:
	var m := 1e9
	for v in p.polygon:
		m = minf(m, v.length())
	return m

func _max_vertex_radius_all(polys: Array) -> float:
	var m := 0.0
	for p in polys:
		for v in (p as Polygon2D).polygon:
			m = maxf(m, v.length())
	return m

func _vertex_counts(polys: Array) -> Array:
	var out: Array = []
	for p in polys:
		out.append((p as Polygon2D).polygon.size())
	out.sort()
	return out

func _initialize() -> void:
	var pickup_scene: PackedScene = load("res://scenes/spell_pickup.tscn")
	var reward_scene: PackedScene = load("res://scenes/reward_drop.tscn")
	var revive_scene: PackedScene = load("res://scenes/revive_item.tscn")
	_check(pickup_scene != null, "(0) spell_pickup.tscn loads")
	_check(reward_scene != null, "(0) reward_drop.tscn loads")
	_check(revive_scene != null, "(0) revive_item.tscn loads")
	if pickup_scene == null or reward_scene == null or revive_scene == null:
		print("[92] DONE failures=", failures)
		quit(failures)
		return
	var pickup: Node2D = pickup_scene.instantiate() as Node2D
	var reward: Node2D = reward_scene.instantiate() as Node2D
	var revive: Node2D = revive_scene.instantiate() as Node2D
	root.add_child(pickup)
	root.add_child(reward)
	root.add_child(revive)

	# (a) collision bytes unchanged.
	_check(is_equal_approx(_radius_of(pickup), 24.0), "(a) pickup collision radius unchanged (24.0, got %.2f)" % _radius_of(pickup))
	_check(is_equal_approx(_radius_of(reward), 24.0), "(a) reward collision radius unchanged (24.0, got %.2f)" % _radius_of(reward))
	_check(is_equal_approx(_radius_of(revive), 14.0), "(a) revive collision radius unchanged (14.0, got %.2f)" % _radius_of(revive))

	# (b) preserved refs.
	_check(pickup.get_node_or_null("ColorRect") is ColorRect, "(b) pickup ColorRect fill preserved")
	_check(pickup.get_node_or_null("NameLabel") is Label, "(b) pickup NameLabel preserved")
	_check(reward.get_node_or_null("Visual") is Polygon2D, "(b) reward Visual is still a Polygon2D")
	_check(reward.get_node_or_null("NameLabel") is Label, "(b) reward NameLabel preserved")
	var rv: Polygon2D = revive.get_node_or_null("Visual") as Polygon2D
	_check(rv != null and rv.polygon.size() == 12, "(b) revive Visual is still a Polygon2D 12-vert cross")

	# (c) root scripts unchanged.
	_check(pickup.get_script() != null and (pickup.get_script() as Script).resource_path == "res://scripts/spell_pickup.gd", "(c) pickup script unchanged")
	_check(reward.get_script() != null and (reward.get_script() as Script).resource_path == "res://scripts/reward_drop.gd", "(c) reward script unchanged")
	_check(revive.get_script() != null and (revive.get_script() as Script).resource_path == "res://scripts/revive_item.gd", "(c) revive script unchanged")

	# (d) decoration present.
	var pd := _decor_polys(pickup)
	var rd := _decor_polys(reward)
	var vd := _decor_polys(revive)
	_check(pd.size() == 4, "(d) pickup has 4 decor polygons (got %d)" % pd.size())
	_check(rd.size() == 1, "(d) reward has 1 decor ring (got %d)" % rd.size())
	_check(vd.size() == 4, "(d) revive has 4 decor polygons (got %d)" % vd.size())

	# (e) signatures distinct: 6-vert ticks, 26-vert ring, 8-vert dots.
	var pcounts := _vertex_counts(pd)
	var rcounts := _vertex_counts(rd)
	var vcounts := _vertex_counts(vd)
	_check(pcounts == [6, 6, 6, 6], "(e) pickup decor = 4 x 6-vert corner ticks (got %s)" % str(pcounts))
	_check(rcounts == [26], "(e) reward decor = 1 x 26-vert ring (got %s)" % str(rcounts))
	_check(vcounts == [8, 8, 8, 8], "(e) revive decor = 4 x 8-vert dots (got %s)" % str(vcounts))
	_check(pcounts != rcounts and rcounts != vcounts and pcounts != vcounts, "(e) three decor signatures mutually distinct")

	# (f) fill dominance.
	_check(_max_spread(pd) < 0.2, "(f) pickup decor neutral (max channel spread %.3f)" % _max_spread(pd))
	_check(_max_spread(rd) < 0.2, "(f) reward decor neutral (max channel spread %.3f)" % _max_spread(rd))
	_check(_max_spread(vd) < 0.2, "(f) revive decor neutral (max channel spread %.3f)" % _max_spread(vd))
	if rd.size() == 1:
		_check(_min_vertex_radius(rd[0]) >= 13.5, "(f) reward ring never covers the r12 dynamic diamond (min radius %.2f)" % _min_vertex_radius(rd[0]))
	else:
		_check(false, "(f) reward ring never covers the r12 dynamic diamond (no ring)")

	# (g) footprint sanity.
	_check(_max_vertex_radius_all(pd) <= 40.0, "(g) pickup decor within r40 (max %.2f)" % _max_vertex_radius_all(pd))
	_check(_max_vertex_radius_all(rd) <= 40.0, "(g) reward decor within r40 (max %.2f)" % _max_vertex_radius_all(rd))
	_check(_max_vertex_radius_all(vd) <= 40.0, "(g) revive decor within r40 (max %.2f)" % _max_vertex_radius_all(vd))

	print("[92] DONE failures=", failures)
	quit(failures)
