extends SceneTree
## #513: all Fishy tuning values and production prototype isolation.
var failures := 0
func _check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("[513 fishy tuning] ", label, " -> ", "PASS" if ok else "FAIL")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	for name in ["fishy", "fishy_guard"]:
		var prototype := load("res://resources/behaviors/%s.tres" % name) as EnemyBehaviorFishy
		_check(prototype != null, name + " loads authored behavior")
		_check(prototype.hook_range == 560.0 and prototype.hook_range == EnemyBehaviorFishy.HOOK_RANGE, "hook_range unchanged")
		_check(prototype.hook_speed == 950.0 and prototype.hook_speed == EnemyBehaviorFishy.HOOK_SPEED, "hook_speed unchanged")
		_check(prototype.hook_hit_radius == 22.0 and prototype.hook_hit_radius == EnemyBehaviorFishy.HOOK_HIT_RADIUS, "hook_hit_radius unchanged")
		_check(prototype.windup_time == 0.6 and prototype.windup_time == EnemyBehaviorFishy.WINDUP_TIME, "windup_time unchanged")
		_check(prototype.aim_lock_at == 0.35 and prototype.aim_lock_at == EnemyBehaviorFishy.AIM_LOCK_AT, "aim_lock_at unchanged")
		_check(prototype.reel_speed == 380.0 and prototype.reel_speed == EnemyBehaviorFishy.REEL_SPEED, "reel_speed unchanged")
		_check(prototype.reel_stop == 46.0 and prototype.reel_stop == EnemyBehaviorFishy.REEL_STOP, "reel_stop unchanged")
		_check(prototype.hook_max_time == 2.4 and prototype.hook_max_time == EnemyBehaviorFishy.HOOK_MAX_TIME, "hook_max_time unchanged")
		_check(prototype.tick_interval == 0.25 and prototype.tick_interval == EnemyBehaviorFishy.TICK_INTERVAL, "tick_interval unchanged")
		_check(prototype.tick_damage == 3 and prototype.tick_damage == EnemyBehaviorFishy.TICK_DAMAGE, "tick_damage unchanged")
		_check(prototype.stall_time == 0.3 and prototype.stall_time == EnemyBehaviorFishy.STALL_TIME, "stall_time unchanged")
		_check(prototype.retract_speed == 1400.0 and prototype.retract_speed == EnemyBehaviorFishy.RETRACT_SPEED, "retract_speed unchanged")
		_check(prototype.recover_time == 0.45 and prototype.recover_time == EnemyBehaviorFishy.RECOVER_TIME, "recover_time unchanged")
		_check(prototype.cast_cooldown == 2.4 and prototype.cast_cooldown == EnemyBehaviorFishy.CAST_COOLDOWN, "cast_cooldown unchanged")
		_check(prototype.keep_away == 150.0 and prototype.keep_away == EnemyBehaviorFishy.KEEP_AWAY, "keep_away unchanged")
		_check(prototype.engage_fraction == 0.85 and prototype.engage_fraction == EnemyBehaviorFishy.ENGAGE_FRACTION, "engage_fraction unchanged")
		_check(prototype.ally_radius == 520.0 and prototype.ally_radius == EnemyBehaviorFishy.ALLY_RADIUS, "ally_radius unchanged")
		_check(prototype.rally_time == 2.5 and prototype.rally_time == EnemyBehaviorFishy.RALLY_TIME, "rally_time unchanged")
		_check(prototype.rally_interval == 0.5 and prototype.rally_interval == EnemyBehaviorFishy.RALLY_INTERVAL, "rally_interval unchanged")
		_check(prototype.rod_tip_offset == Vector2(16, -22) and prototype.rod_tip_offset == EnemyBehaviorFishy.ROD_TIP, "rod_tip_offset unchanged")
		_check((prototype.notice_radius == 420.0 and prototype.leash_radius == 800.0) if name == "fishy_guard" else (is_inf(prototype.notice_radius) and is_inf(prototype.leash_radius)), name + " notice and leash unchanged")
		var area := Node2D.new()
		root.add_child(area)
		var a: Enemy = load("res://scenes/enemy_fishy.tscn").instantiate()
		var b: Enemy = load("res://scenes/enemy_fishy.tscn").instantiate()
		a.definition = load("res://resources/enemies/%s.tres" % ("overworld_fishy" if name == "fishy_guard" else "fishy"))
		b.definition = a.definition
		a.set_physics_process(false)
		b.set_physics_process(false)
		area.add_child(a)
		area.add_child(b)
		var ab := a._behavior as EnemyBehaviorFishy
		var bb := b._behavior as EnemyBehaviorFishy
		_check(ab != null and bb != null and ab != bb and ab != prototype and bb != prototype, name + " actual Enemy owns independent duplicate")
		ab.hook_range = 1.0
		ab.home = Vector2(3, 4)
		ab.engaged = true
		ab.state = EnemyBehaviorFishy.State.CAST
		ab._cooldown = 5.0
		ab._tick_t = 0.1
		ab._rally_t = 1.0
		ab.hook_pos = Vector2(9, 10)
		_check(bb.hook_range == 560.0 and prototype.hook_range == 560.0, name + " tuning isolated")
		_check(bb.home == Vector2.INF and prototype.home == Vector2.INF and not bb.engaged and not prototype.engaged, name + " home engagement isolated")
		_check(bb.state == EnemyBehaviorFishy.State.APPROACH and prototype.state == EnemyBehaviorFishy.State.APPROACH and bb.hook_pos == Vector2.ZERO and prototype.hook_pos == Vector2.ZERO, name + " hook state isolated")
		_check(bb._cooldown == 0.6 and prototype._cooldown == 0.6 and bb._tick_t == 0.0 and prototype._tick_t == 0.0 and bb._rally_t == 0.0 and prototype._rally_t == 0.0, name + " cooldown damage and rally clocks isolated")
		_check(ab._terrain_path != bb._terrain_path and ab._terrain_path != prototype._terrain_path, name + " terrain helper isolated")
		area.free()
	quit(1 if failures else 0)
