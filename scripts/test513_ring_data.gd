extends SceneTree
## #513: shared ring data preserves each boss's values and inclusive hit range.
var failures := 0
func _check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("[513 ring] ", label, " -> ", "PASS" if ok else "FAIL")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var area := Node2D.new()
	root.add_child(area)
	var enemy := Enemy.new()
	enemy.definition = EnemyDefinition.new()
	area.add_child(enemy)
	enemy.set_physics_process(false)
	var player := Player.new()
	area.add_child(player)
	player.set_physics_process(false)
	for b in [EnemyBehaviorHead.new(), EnemyBehaviorBeast.new()]:
		var head: bool = b is EnemyBehaviorHead
		var d = b.ring_data
		_check(d.radius == (120.0 if head else 125.0) and d.enraged_radius == (175.0 if head else 180.0), "normal and enraged radii unchanged")
		_check(d.damage == (16 if head else 15) and d.display_time == (0.5 if head else 0.55), "damage and display time unchanged")
		_check(d.color == (EnemyBehaviorHead.HEAD_RED if head else EnemyBehaviorBeast.BEAST_GREEN), "effect color unchanged")
		enemy.max_hp = 100
		enemy.hp = 51
		_check(b._ring_radius(enemy) == d.radius, "normal radius above half HP")
		enemy.hp = 50
		_check(b._ring_radius(enemy) == d.enraged_radius, "enraged radius at half HP")
		player.hp = player.max_hp
		var hp_before := player.hp
		b._ring_release(enemy, player, Vector2(d.radius + 1.0, 0), d.radius, null)
		_check(player.hp == hp_before, "outside radius does not hit")
		b._ring_release(enemy, player, Vector2(d.radius, 0), d.radius, null)
		_check(player.hp < hp_before, "inclusive radius boundary hits")
	area.free()
	quit(1 if failures else 0)
