extends SceneTree
## #513: preserve strict range endpoints and the original third-repeat fallback.
var failures := 0
func _check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("[513 ranges] ",label," -> ","PASS" if ok else "FAIL")
func sample(b: BossBehavior, dist: float, expected: int, label: String) -> void:
	b._history.clear()
	_check(b._pick_attack(dist) == expected,label)
func _initialize() -> void:
	var h := EnemyBehaviorHead.new()
	sample(h,149.999,BossBehavior.Attack.PULSE,"head below150 pulse")
	sample(h,150.0,BossBehavior.Attack.VOLLEY,"head at150 volley")
	var b := EnemyBehaviorBeast.new()
	sample(b,139.999,BossBehavior.Attack.SCREAM,"beast below140 scream")
	sample(b,140.0,BossBehavior.Attack.LUNGE,"beast at140 lunge")
	var w := EnemyBehaviorWarlord.new()
	sample(w,129.999,BossBehavior.Attack.SPIN,"warlord below130 spin")
	sample(w,130.0,BossBehavior.Attack.LUNGE,"warlord at130 lunge")
	sample(w,270.0,BossBehavior.Attack.LUNGE,"warlord at270 lunge")
	sample(w,270.001,BossBehavior.Attack.VOLLEY,"warlord above270 volley")
	for pair in [[h,100.0,BossBehavior.Attack.PULSE,BossBehavior.Attack.VOLLEY],[h,200.0,BossBehavior.Attack.VOLLEY,BossBehavior.Attack.PULSE],[b,100.0,BossBehavior.Attack.SCREAM,BossBehavior.Attack.LUNGE],[b,200.0,BossBehavior.Attack.LUNGE,BossBehavior.Attack.SCREAM],[w,100.0,BossBehavior.Attack.SPIN,BossBehavior.Attack.LUNGE],[w,200.0,BossBehavior.Attack.LUNGE,BossBehavior.Attack.VOLLEY],[w,300.0,BossBehavior.Attack.VOLLEY,BossBehavior.Attack.LUNGE]]:
		var brain: BossBehavior = pair[0]
		brain._history.clear()
		_check(brain._pick_attack(pair[1]) == pair[2] and brain._pick_attack(pair[1]) == pair[2] and brain._pick_attack(pair[1]) == pair[3],"third repeat uses original fallback")
		for i in 5: brain._pick_attack(pair[1])
		_check(brain._history.size() == 4,"history remains capped at four")
	quit(1 if failures else 0)
