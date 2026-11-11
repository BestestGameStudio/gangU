extends SceneTree
## #513: authored overworld Fishy radii and per-enemy mutable-state isolation.
var failures := 0
func _check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("[513 fishy resource] ", label, " -> ", "PASS" if ok else "FAIL")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var prototype := load("res://resources/behaviors/fishy_guard.tres") as EnemyBehaviorFishy
	_check(prototype != null and prototype.notice_radius == 420.0 and prototype.leash_radius == 800.0, "authored guard radii unchanged")
	var dungeon := EnemyBehaviorFishy.new()
	_check(is_inf(dungeon._notice_radius()) and is_inf(dungeon._leash_radius()), "dungeon still always notices, never leashes")
	var area := Node2D.new()
	root.add_child(area)
	var a: Enemy = load("res://scenes/enemy_fishy.tscn").instantiate()
	var b: Enemy = load("res://scenes/enemy_fishy.tscn").instantiate()
	a.definition = load("res://resources/enemies/overworld_fishy.tres")
	b.definition = a.definition
	area.add_child(a)
	area.add_child(b)
	a.set_physics_process(false)
	b.set_physics_process(false)
	_check(a._behavior is EnemyBehaviorFishy and b._behavior is EnemyBehaviorFishy, "actual Enemy definition loads Resource behavior")
	_check(a._behavior != b._behavior and a._behavior != prototype, "each Enemy owns independent duplicate")
	a._behavior.engaged = true
	a._behavior.home = Vector2(12, 34)
	a._behavior.notice_radius = 10.0
	_check(not b._behavior.engaged and not prototype.engaged and b._behavior.home == Vector2.INF and prototype.home == Vector2.INF, "mutable engagement/home state isolated")
	_check(b._behavior.notice_radius == 420.0 and prototype.notice_radius == 420.0, "authored tuning remains isolated")
	area.free()
	quit(1 if failures else 0)
