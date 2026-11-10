extends SceneTree
## #513: the base owns CHASE/WINDUP dispatch and forwards attack arguments.
class Probe extends BossBehavior:
	var seen: Array = []
	func _chase(e: Enemy, p: Player, v: Vector2, d: float, t: BossTelegraph) -> void:
		seen = [State.CHASE,e,p,v,d,t]
	func _windup(e: Enemy, v: Vector2, t: BossTelegraph) -> void:
		seen = [State.WINDUP,e,v,t]
	func attack_call(e: Enemy, p: Player, v: Vector2, d: float, t: BossTelegraph) -> void:
		seen = [State.LUNGE,e,p,v,d,t]
var failures := 0
func _check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("[513 dispatch] ",label," -> ","PASS" if ok else "FAIL")
func _initialize() -> void:
	var b := Probe.new()
	var e := Enemy.new()
	var p := Player.new()
	var t := BossTelegraph.new()
	var v := Vector2(7,8)
	b.state = BossBehavior.State.CHASE
	b._step(e,p,v,0.125,t)
	_check(b.seen == [BossBehavior.State.CHASE,e,p,v,0.125,t],"chase forwarding")
	b.state = BossBehavior.State.WINDUP
	b._step(e,p,v,0.125,t)
	_check(b.seen == [BossBehavior.State.WINDUP,e,v,t],"windup forwarding")
	b.attack_steps[BossBehavior.State.LUNGE] = b.attack_call
	b.state = BossBehavior.State.LUNGE
	b._step(e,p,v,0.125,t)
	_check(b.seen == [BossBehavior.State.LUNGE,e,p,v,0.125,t],"attack arguments unchanged")
	_check(EnemyBehaviorHead.new().attack_steps.keys().size() == 2,"head two attack handlers")
	_check(EnemyBehaviorBeast.new().attack_steps.keys().size() == 2,"beast two attack handlers")
	_check(EnemyBehaviorWarlord.new().attack_steps.keys().size() == 3,"warlord three attack handlers")
	e.free()
	p.free()
	t.free()
	quit(1 if failures else 0)
