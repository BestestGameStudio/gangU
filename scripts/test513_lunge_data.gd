extends SceneTree
## #513: shared lunge retains original speeds, hit rules and durations.
var failures := 0
func _check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("[513 lunge] ", label, " -> ", "PASS" if ok else "FAIL")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var area := Node2D.new()
	root.add_child(area)
	var enemy := Enemy.new()
	enemy.definition = EnemyDefinition.new()
	enemy.max_hp = 100
	enemy.hp = 100
	area.add_child(enemy)
	enemy.set_physics_process(false)
	var player := Player.new()
	area.add_child(player)
	player.set_physics_process(false)
	for b in [EnemyBehaviorBeast.new(), EnemyBehaviorWarlord.new()]:
		var beast: bool = b is EnemyBehaviorBeast
		var d = b.lunge_data
		_check(d.speed == (600.0 if beast else 560.0) and d.enraged_speed == (740.0 if beast else 700.0), "normal and enraged speed unchanged")
		_check(d.duration == (0.34 if beast else 0.32) and d.hit_range == (60.0 if beast else 58.0) and d.damage == 18, "duration range and damage unchanged")
		enemy.hp = 100
		b._dir = Vector2.RIGHT
		b._hits = 0
		b._lunge_step(enemy, player, d.hit_range + 1.0)
		_check(enemy.velocity == Vector2.RIGHT * d.speed and b._hits == 0, "normal velocity and out-of-range no hit")
		enemy.hp = 50
		b._lunge_step(enemy, player, d.hit_range + 1.0)
		_check(enemy.velocity == Vector2.RIGHT * d.enraged_speed, "enraged velocity at half HP")
		player.hp = player.max_hp
		var hp_before := player.hp
		b._lunge_step(enemy, player, d.hit_range)
		_check(b._hits == 1 and player.hp < hp_before, "inclusive hit boundary hits once")
		var hp_after := player.hp
		b._lunge_step(enemy, player, 0.0)
		_check(player.hp == hp_after, "no repeat hit in same lunge")
	area.free()
	quit(1 if failures else 0)
