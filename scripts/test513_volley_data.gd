extends SceneTree
## #513: shared volley preserves per-boss data and second-wave math.
class Probe extends EnemyBehaviorHead:
	var fired: Array = []
	func _fire_wave(_enemy: Enemy, aim: Vector2, rot: float) -> void:
		_waves_fired += 1
		fired.append([aim, rot])
var failures := 0
func _check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("[513 volley] ", label, " -> ", "PASS" if ok else "FAIL")
func _initialize() -> void:
	for b in [EnemyBehaviorHead.new(), EnemyBehaviorWarlord.new()]:
		var d = b.volley_data
		var head: bool = b is EnemyBehaviorHead
		_check(d.shots == 5 and d.enraged_shots == 7, "wave counts unchanged")
		_check(d.spread == (48.0 if head else 50.0) and d.enraged_spread == (66.0 if head else 70.0), "fan spreads unchanged")
		_check(d.fire_at == (0.12 if head else 0.2) and d.second_wave_at == (0.4 if head else 0.45), "wave timing unchanged")
		_check(d.duration == (0.55 if head else 0.6) and d.muzzle_offset == (30.0 if head else 34.0), "duration and muzzle unchanged")
		_check(d.spell == (EnemyBehaviorHead.BOLT_SPELL if head else EnemyBehaviorWarlord.ORB_SPELL), "spell identity unchanged")
	var enemy := Enemy.new()
	enemy.max_hp = 100
	enemy.hp = 50
	var b := Probe.new()
	b._t = 0.119
	b._volley_step(enemy, Vector2.DOWN)
	_check(b.fired.is_empty(), "no early wave")
	b._t = 0.12
	b._volley_step(enemy, Vector2.DOWN)
	_check(b.fired.size() == 1 and b.fired[0][0] == Vector2.RIGHT and b.fired[0][1] == 0.0, "first wave retains locked aim")
	b._t = 0.4
	b._volley_step(enemy, Vector2.DOWN)
	_check(b.fired.size() == 2 and b.fired[1][0] == Vector2.DOWN and is_equal_approx(b.fired[1][1], deg_to_rad(66.0) / 6.0 * 0.5), "enraged second wave reaims and staggers half gap")
	b._t = 0.55
	b._volley_step(enemy, Vector2.DOWN)
	_check(b.state == BossBehavior.State.RECOVER, "recover at original duration")
	var p := Projectile.new()
	var area := Node2D.new()
	EnemyBehaviorHead.new()._decorate_volley_projectile(p, area)
	_check(p.visual_override == null, "head visual stays default")
	EnemyBehaviorWarlord.new()._decorate_volley_projectile(p, area)
	_check(p.visual_override is WarlordOrbVisual and p.hit.get_connections().size() == 1, "warlord orb and impact hook retained")
	p.free()
	area.free()
	enemy.free()
	quit(1 if failures else 0)
