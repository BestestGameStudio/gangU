extends SceneTree
## #513: authored loop values retain original constants and isolate dictionaries.
var failures := 0
func _check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("[513 tuning] ",label," -> ","PASS" if ok else "FAIL")
func _initialize() -> void:
	for b in [EnemyBehaviorHead.new(),EnemyBehaviorBeast.new(),EnemyBehaviorWarlord.new()]:
		var c: Dictionary = b.get_script().get_script_constant_map()
		for pair in [["first_attack_delay","FIRST_ATTACK_DELAY"],["attack_interval","ATTACK_INTERVAL"],["enraged_interval","ENRAGED_INTERVAL"],["recover_time","RECOVER_TIME"],["windup_times","WINDUP_TIME"],["windup_anims","WINDUP_ANIM"]]:
			_check(b.get(pair[0]) == c[pair[1]],"loop "+pair[0]+" matches original")
		_check(b._attack_timer == c["FIRST_ATTACK_DELAY"],"initial timer uses authored delay")
		_check(b.has_stun_phase == (not b is EnemyBehaviorWarlord),"phase stun unchanged")
		_check(b.stun_time == c.get("STUN_TIME", 1.6), "stun time unchanged")
		_check(b.arrival_color == c.get("HEAD_RED", c.get("BEAST_GREEN", Enemy.SPRITE_BURST_COLOR)), "arrival color unchanged")
	var original := load("res://resources/boss_attacks/head_tuning.tres") as BossTuning
	var a := EnemyBehaviorHead.new()
	var b := EnemyBehaviorHead.new()
	a.windup_times[BossBehavior.Attack.VOLLEY] = 9.0
	a.windup_anims[BossBehavior.Attack.VOLLEY] = &"changed"
	_check(b.windup_times[BossBehavior.Attack.VOLLEY] == 0.7 and original.windup_times[BossBehavior.Attack.VOLLEY] == 0.7,"time dictionary isolated")
	_check(b.windup_anims[BossBehavior.Attack.VOLLEY] == &"windup_projectile" and original.windup_anims[BossBehavior.Attack.VOLLEY] == &"windup_projectile","animation dictionary isolated")
	quit(1 if failures else 0)
