extends SceneTree
## #513: ring ordering, phase timing, counters, and single-step recovery.
class HeadProbe extends EnemyBehaviorHead:
	var releases: Array = []
	func _ring_release(_enemy: Enemy, _player: Player, _to: Vector2, radius: float, _tele: BossTelegraph) -> void:
		releases.append([radius, _pulses])
class BeastProbe extends EnemyBehaviorBeast:
	var releases: Array = []
	func _ring_release(_enemy: Enemy, _player: Player, _to: Vector2, radius: float, _tele: BossTelegraph) -> void:
		releases.append([radius, _screams])
var failures := 0
func _check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("[513 ring sequence] ", label, " -> ", "PASS" if ok else "FAIL")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var area := Node2D.new()
	root.add_child(area)
	var enemy := Enemy.new()
	area.add_child(enemy)
	enemy.set_physics_process(false)
	var player: Player = load("res://scenes/player.tscn").instantiate()
	area.add_child(player)
	player.set_physics_process(false)
	enemy.max_hp = 100
	for b in [HeadProbe.new(), BeastProbe.new()]:
		var head: bool = b is EnemyBehaviorHead
		var counter: StringName = &"_pulses" if head else &"_screams"
		var c: Dictionary = (EnemyBehaviorHead.new() if head else EnemyBehaviorBeast.new()).get_script().get_script_constant_map()
		_check(b.ring_data.duration == c["PULSE_TIME" if head else "SCREAM_TIME"], "normal duration preserved")
		_check(b.ring_data.enraged_duration == c["PULSE_TIME_ENRAGED" if head else "SCREAM_TIME"], "enraged duration preserved")
		for hp in [51, 50]:
			b.releases.clear()
			enemy.hp = hp
			b.state = BossBehavior.State.PULSE if head else BossBehavior.State.SCREAM
			b._t = 0.0
			b.set(counter, 0)
			b._ring_sequence(enemy, player, Vector2(999, 0), null, counter)
			_check(b.releases == [[b.ring_data.enraged_radius if not head and hp == 50 else b.ring_data.radius, 1]], "first radius and pre-release counter preserved")
			_check(b.get(counter) == 1 and enemy.velocity == Vector2.ZERO, "first ring once, stationary")
			b._t = 0.29
			b._ring_sequence(enemy, player, Vector2(999, 0), null, counter)
			_check(b.get(counter) == 1, "no premature repeat")
			b._t = 0.3
			b._ring_sequence(enemy, player, Vector2(999, 0), null, counter)
			_check(b.get(counter) == (2 if head and hp == 50 else 1), "second ring only enraged Head at threshold")
			if head and hp == 50:
				_check(b.releases[-1] == [b.ring_data.enraged_radius, 2], "second radius and pre-release counter preserved")
			b._t = b.ring_data.enraged_duration if hp == 50 else b.ring_data.duration
			b._ring_sequence(enemy, player, Vector2(999, 0), null, counter)
			_check(b.state == BossBehavior.State.RECOVER and b._t == 0.0, "exact duration recovers")
		# A large first frame still emits only the first ring before recovery.
		b.set(counter, 0)
		b._t = 10.0
		b._ring_sequence(enemy, player, Vector2(999, 0), null, counter)
		_check(b.get(counter) == 1 and b.state == BossBehavior.State.RECOVER, "large frame release-before-recover unchanged")
	area.free()
	quit(1 if failures else 0)
