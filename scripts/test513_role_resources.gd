extends SceneTree
## #513: authored role tuning, definition consumers and per-enemy state isolation.
var failures := 0
func _check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("[513 role resources] ", label, " -> ", "PASS" if ok else "FAIL")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	for role in ["guard", "patrol", "migrant"]:
		var prototype := load("res://resources/behaviors/overworld_%s.tres" % role) as EnemyBehaviorGuard
		_check(prototype != null and prototype.aggro_radius == 220.0 and prototype.leash_radius == 520.0 and prototype.home_epsilon == 6.0, role + " authored base tuning unchanged")
		var area := Node2D.new()
		root.add_child(area)
		var a: Enemy = load("res://scenes/enemy.tscn").instantiate()
		var b: Enemy = load("res://scenes/enemy.tscn").instantiate()
		a.definition = load("res://resources/enemies/overworld_%s.tres" % role)
		b.definition = a.definition
		a.set_physics_process(false)
		b.set_physics_process(false)
		area.add_child(a)
		area.add_child(b)
		var ab := a._behavior as EnemyBehaviorGuard
		var bb := b._behavior as EnemyBehaviorGuard
		_check(ab != null and bb != null and ab.get_script() == prototype.get_script(), role + " actual Enemy uses authored role")
		_check(ab != bb and ab != prototype and bb != prototype, role + " each Enemy owns independent duplicate")
		ab.engaged = true
		ab.home = Vector2(12, 34)
		ab.engaged_from = Vector2(56, 78)
		ab.aggro_radius = 10.0
		ab.configure_route(PackedVector2Array([Vector2(1, 2), Vector2(3, 4)]))
		_check(not bb.engaged and not prototype.engaged and bb.home == Vector2.INF and prototype.home == Vector2.INF and bb.engaged_from == Vector2.INF and prototype.engaged_from == Vector2.INF, role + " engagement and home state isolated")
		_check(bb.route.is_empty() and prototype.route.is_empty() and ab.route.size() == 2, role + " route handoff isolated")
		_check(bb.aggro_radius == 220.0 and prototype.aggro_radius == 220.0, role + " authored tuning isolated")
		_check(ab._walk_path != bb._walk_path and ab._walk_path != prototype._walk_path and ab._terrain_path != bb._terrain_path, role + " routing helpers isolated")
		if role == "patrol":
			var patrol := bb as EnemyBehaviorPatrol
			_check(patrol != null and patrol.stroll_fraction == 0.45 and patrol.pause_time == 0.8 and patrol.patrol_leash_radius == 900.0 and patrol.mustache_leash_radius == 1350.0, "patrol authored tuning unchanged")
			_check(patrol._leash_radius(b) == 1350.0, "mustache patrol selection unchanged")
			b.cover_seek = false
			_check(patrol._leash_radius(b) == 900.0, "other patrol selection unchanged")
			ab.waypoint = 1
			ab._pause = 0.7
			_check(patrol.waypoint == 0 and patrol._pause == 0.0 and prototype.waypoint == 0, "patrol clock and waypoint isolated")
		elif role == "migrant":
			var migrant := bb as EnemyBehaviorMigrate
			_check(migrant != null and migrant.travel_fraction == 0.55 and migrant.rest_time == 6.0, "migrant authored tuning unchanged")
			ab.waypoint = 1
			ab.direction = -1
			ab.resting = true
			ab._rest = 5.0
			_check(migrant.waypoint == 0 and migrant.direction == 1 and not migrant.resting and migrant._rest == 0.0 and not prototype.resting, "migrant clock and direction isolated")
		area.free()
	for name in ["slime_guard", "slime_patrol"]:
		var definition := load("res://resources/enemies/%s.tres" % name) as EnemyDefinition
		var role := "guard" if name == "slime_guard" else "patrol"
		_check(definition.behavior == load("res://resources/behaviors/overworld_%s.tres" % role), name + " shares only the authored prototype")
	quit(1 if failures else 0)
