extends SceneTree
## #513: shared lunge duration, chain transitions, counters and phase stun.
var failures := 0
func _check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("[513 lunge sequence] ", label, " -> ", "PASS" if ok else "FAIL")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var area := Node2D.new()
	root.add_child(area)
	var enemy: Enemy = load("res://scenes/enemy.tscn").instantiate()
	area.add_child(enemy)
	enemy.set_physics_process(false)
	var player: Player = load("res://scenes/player.tscn").instantiate()
	area.add_child(player)
	player.set_physics_process(false)
	enemy.max_hp = 100
	for b in [EnemyBehaviorBeast.new(), EnemyBehaviorWarlord.new()]:
		var beast: bool = b is EnemyBehaviorBeast
		for hp in [51, 50]:
			enemy.hp = hp
			b.state = BossBehavior.State.LUNGE
			b._dir = Vector2.RIGHT
			b._hits = 0
			b._t = b.lunge_data.duration - 0.01
			b._lunge_sequence(enemy, player, 999.0, null, 1)
			_check(b.state == BossBehavior.State.LUNGE and enemy.velocity.x > 0.0, "no premature transition")
			b._t = b.lunge_data.duration
			b._lunge_sequence(enemy, player, 999.0, null, 1)
			_check(b.state == (BossBehavior.State.WINDUP if beast and hp == 50 else BossBehavior.State.RECOVER), "exact duration chains only first enraged Beast")
			_check(b._t == 0.0 and enemy.velocity == Vector2.ZERO, "transition clears time and velocity")
		# The second lunge recovers, without modifying per-boss counts.
		b.state = BossBehavior.State.LUNGE
		b._t = b.lunge_data.duration
		b._lunge_sequence(enemy, player, 999.0, null, 2)
		_check(b.state == BossBehavior.State.RECOVER, "second lunge recovers")
	var beast := EnemyBehaviorBeast.new()
	_check(beast.lunge_data.chain_pause == beast.LUNGE_CHAIN_PAUSE and beast.lunge_data.chain_length == beast.LUNGE_LENGTH and beast.lunge_data.chain_animation == &"windup_bite", "chain authored values match constants")
	beast._lunges = 1
	beast.attack = BossBehavior.Attack.LUNGE
	_check(beast._windup_duration() == beast.lunge_data.chain_pause, "chain duration unchanged")
	beast._lunges = 2
	beast._attack_begin_reset()
	_check(beast._lunges == 2 and beast._hits == 0, "chain counter survives attack begin reset")
	_check(beast.clear_glow_on_stun and not EnemyBehaviorHead.new().clear_glow_on_stun, "only Beast clears phase-stun glow")
	beast._enter_stun(enemy, null)
	_check(beast.phase_two and beast.state == BossBehavior.State.STUN and beast._t == 0.0, "phase stun state preserved")
	area.free()
	quit(1 if failures else 0)
