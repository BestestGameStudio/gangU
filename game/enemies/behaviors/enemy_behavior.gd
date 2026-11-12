class_name EnemyBehavior
extends Resource
## #513: the common base of every enemy behavior (the #99 behavior slot).
## An Enemy duplicates its OWN behavior from the EnemyDefinition.behavior
## prototype and calls physics_step each physics frame, so mutable runtime
## state is never shared. Behaviors override physics_step; the base does
## nothing.

func physics_step(_enemy: Enemy, _player, _delta: float) -> void:
	pass

## #637 (Daniel, 2026-11-12: "debug mode toggleable by F2 which shows enemy
## state in a text above their head"): text for the F2 debug label. Behaviors
## with a NAMED `State` enum resolve the current value via the script
## constant map; stateless behaviors (no `state` var / no `State` enum)
## return "" and get no label.
func debug_state_text() -> String:
	# Behaviors name the var `state` or `_state`; either resolves.
	var s: Variant = get("state")
	if typeof(s) != TYPE_INT:
		s = get("_state")
	if typeof(s) != TYPE_INT:
		return ""
	var named: Variant = get_script().get_script_constant_map().get("State")
	if named is Dictionary:
		var keys: Array = (named as Dictionary).keys()
		if s >= 0 and s < keys.size():
			return String(keys[s])
	# Anonymous enums (bird, wolf) expose the state name through the
	# state_name() harness hook instead.
	if has_method("state_name"):
		return call("state_name")
	return ""
