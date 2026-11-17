extends EnemySprite
## Attacks and miss-stun hold their telegraph/forward pose even when hit.
## Enemy still flashes and emits health_changed; ordinary sprites unchanged.
func _on_health_changed(current: int, max_hp_value: int) -> void:
	var e := get_parent() as EnemyScorpion
	if e != null and e._behavior is EnemyBehaviorScorpion:
		var state := (e._behavior as EnemyBehaviorScorpion).state
		if state not in [EnemyBehaviorScorpion.State.CHASE,EnemyBehaviorScorpion.State.BURIED]:
			_last_hp = current
			return
	super._on_health_changed(current,max_hp_value)
