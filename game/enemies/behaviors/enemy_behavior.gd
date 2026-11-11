class_name EnemyBehavior
extends Resource
## #513: the common base of every enemy behavior (the #99 behavior slot).
## An Enemy duplicates its OWN behavior from the EnemyDefinition.behavior
## prototype and calls physics_step each physics frame, so mutable runtime
## state is never shared. Behaviors override physics_step; the base does
## nothing.

func physics_step(_enemy: Enemy, _player, _delta: float) -> void:
	pass
