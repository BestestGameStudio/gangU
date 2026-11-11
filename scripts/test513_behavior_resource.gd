extends SceneTree
## #513 H1: authored behavior prototypes isolate enemy state.
class TunedBehavior extends EnemyBehavior:
	@export var interval: float = 1.0
	var history: Array[int] = []
	var timer: float = 0.0

var failures := 0
func _check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("[513 resource] ", label, " -> ", "PASS" if ok else "FAIL")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var prototype := TunedBehavior.new()
	prototype.interval = 2.25
	var d := EnemyDefinition.new()
	d.behavior = prototype
	var scene := load("res://scenes/head_boss.tscn") as PackedScene
	var a := scene.instantiate() as Enemy
	var b := scene.instantiate() as Enemy
	a.definition = d
	b.definition = d
	root.add_child(a)
	root.add_child(b)
	a.set_physics_process(false)
	b.set_physics_process(false)
	_check(a._behavior is TunedBehavior and b._behavior is TunedBehavior, "resource prototype preserves concrete class")
	_check(a._behavior != b._behavior and a._behavior != prototype and b._behavior != prototype, "each enemy owns a separate behavior")
	_check(a._behavior.interval == 2.25 and b._behavior.interval == 2.25, "prototype tuning copied")
	a._behavior.history.append(BossBehavior.Attack.VOLLEY)
	a._behavior.timer = 9.0
	_check(b._behavior.history.is_empty() and prototype.history.is_empty(), "mutable history isolated from peer and prototype")
	_check(b._behavior.timer == 0.0 and prototype.timer == 0.0, "runtime timer isolated")
	var head_proto: EnemyBehavior = (load("res://resources/enemies/head_boss.tres") as EnemyDefinition).behavior
	var c := scene.instantiate() as Enemy
	root.add_child(c)
	c.set_physics_process(false)
	_check(c._behavior is EnemyBehaviorHead and c._behavior != head_proto, "head scene duplicates its authored prototype")
	var fallback := scene.instantiate() as Enemy
	var unsupported := EnemyDefinition.new()
	unsupported.behavior = Resource.new()
	fallback.definition = unsupported
	root.add_child(fallback)
	fallback.set_physics_process(false)
	_check(fallback._behavior == null, "non-EnemyBehavior slot gets no fallback behavior")
	var defaulted := scene.instantiate() as Enemy
	defaulted.definition = EnemyDefinition.new()
	root.add_child(defaulted)
	defaulted.set_physics_process(false)
	_check(defaulted._behavior is EnemyBehaviorChaseContact, "null slot uses the default chase/contact behavior")
	a.free()
	b.free()
	c.free()
	fallback.free()
	defaulted.free()
	quit(1 if failures else 0)
