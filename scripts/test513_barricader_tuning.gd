extends SceneTree
## #513: authored Barricader tuning, isolation and deferred placement.
var failures := 0
func _check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("[513 barricader tuning] ", label, " -> ", "PASS" if ok else "FAIL")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var prototype := load("res://resources/behaviors/barricader.tres") as EnemyBehaviorBarricader
	_check(prototype.deploy_range == EnemyBehaviorBarricader.DEPLOY_RANGE, "deploy_range unchanged")
	_check(prototype.min_deploy_dist == EnemyBehaviorBarricader.MIN_DEPLOY_DIST, "min_deploy_dist unchanged")
	_check(prototype.deploy_cooldown == EnemyBehaviorBarricader.DEPLOY_COOLDOWN, "deploy_cooldown unchanged")
	_check(prototype.scan_interval == EnemyBehaviorBarricader.SCAN_INTERVAL, "scan_interval unchanged")
	_check(prototype.barricade_ahead == EnemyBehaviorBarricader.BARRICADE_AHEAD, "barricade_ahead unchanged")
	_check(prototype.open_radius == EnemyBehaviorBarricader.OPEN_RADIUS, "open_radius unchanged")
	_check(prototype.spot_min == EnemyBehaviorBarricader.SPOT_MIN, "spot_min unchanged")
	_check(prototype.spot_max == EnemyBehaviorBarricader.SPOT_MAX, "spot_max unchanged")
	_check(prototype.spot_rings == EnemyBehaviorBarricader.SPOT_RINGS, "spot_rings unchanged")
	_check(prototype.spot_rays == EnemyBehaviorBarricader.SPOT_RAYS, "spot_rays unchanged")
	_check(prototype.spot_cone == EnemyBehaviorBarricader.SPOT_CONE, "spot_cone unchanged")
	_check(prototype.fast_mult == EnemyBehaviorBarricader.FAST_MULT, "fast_mult unchanged")
	_check(prototype.arrive_eps == EnemyBehaviorBarricader.ARRIVE_EPS, "arrive_eps unchanged")
	_check(prototype.stall_time == EnemyBehaviorBarricader.STALL_TIME, "stall_time unchanged")
	_check(prototype.max_run_time == EnemyBehaviorBarricader.MAX_RUN_TIME, "max_run_time unchanged")
	_check(prototype.build_time == EnemyBehaviorBarricader.BUILD_TIME, "build_time unchanged")
	var area := Node2D.new()
	area.position = Vector2(31, 47)
	root.add_child(area)
	var a: Enemy = load("res://scenes/enemy_barricader.tscn").instantiate()
	var b: Enemy = load("res://scenes/enemy_barricader.tscn").instantiate()
	a.set_physics_process(false)
	b.set_physics_process(false)
	area.add_child(a)
	area.add_child(b)
	var ab := a._behavior as EnemyBehaviorBarricader
	var bb := b._behavior as EnemyBehaviorBarricader
	_check(ab != null and bb != null and ab != bb and ab != prototype and bb != prototype, "actual Enemy owns separate duplicates")
	_check(ab._cover != bb._cover and ab._cover != prototype._cover and ab._run_path != bb._run_path and ab._terrain_path != bb._terrain_path, "cover run and chase helpers isolated")
	ab.deploy_range = 1.0
	ab._running = true
	ab._spot = Vector2(9, 10)
	ab._scan_t = 0.4
	ab._run_t = 2.0
	_check(bb.deploy_range == 420.0 and prototype.deploy_range == 420.0 and not bb._running and not prototype._running and bb._spot == Vector2.ZERO and prototype._spot == Vector2.ZERO and bb._scan_t == 0.0 and bb._run_t == 0.0, "tuning run state and clocks isolated")
	a.position = Vector2(100, 100)
	var wall := ab.deploy(a, a.global_position + Vector2(200, 0))
	_check(wall != null and wall.get_parent() == null and wall.deployer == a, "placement retains deferred tree entry and deployer")
	_check(wall.position.is_equal_approx(Vector2(140, 100)) and is_zero_approx(wall.rotation), "placement keeps area-local position and direction")
	_check(ab._deploy_cd == 6.0 and ab._build_t == 0.4 and ab.deployed == 1 and ab._barricade == wall, "deployment cooldown build and counter unchanged")
	_check(bb._deploy_cd == 0.0 and prototype._deploy_cd == 0.0 and bb._build_t == 0.0 and prototype.deployed == 0 and bb._barricade == null and prototype._barricade == null, "live barricade and deployment clocks isolated")
	await process_frame
	_check(wall.get_parent() == area and wall.is_in_group("cover"), "deferred barricade joins same area and cover group")
	area.free()
	quit(1 if failures else 0)
