extends SceneTree
## #513: authored presentation keeps the exact existing seven-entry contract.
var failures := 0
func _check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("[513 authored presentation] ",label," -> ","PASS" if ok else "FAIL")
func _initialize() -> void:
	var total := 0
	for b in [EnemyBehaviorHead.new(),EnemyBehaviorBeast.new(),EnemyBehaviorWarlord.new()]:
		for key in b.presentations:
			var p = b.presentations[key]
			total += 1
			_check(p is BossAttack and p.resource_path.begins_with("res://resources/boss_attacks/"),"typed authored presentation")
			_check(p.animation != &"" and p.next_state in [BossBehavior.State.LUNGE,BossBehavior.State.SPIN,BossBehavior.State.VOLLEY,BossBehavior.State.PULSE,BossBehavior.State.SCREAM],"valid animation and attack state")
	_check(total == 7,"exactly seven attack entries")
	var exports := 0
	for p in BossAttack.new().get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and p.usage & PROPERTY_USAGE_EDITOR: exports += 1
	_check(exports == 10,"all ten presentation fields editable")
	quit(1 if failures else 0)
