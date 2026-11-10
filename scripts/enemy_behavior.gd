class_name EnemyBehavior
extends Resource
## #513: the common base of every enemy behavior (the #99 behavior slot).
## An Enemy creates its OWN behavior from EnemyDefinition.behavior and
## calls physics_step each physics frame; Enemy._ready checks the instance
## `is EnemyBehavior` instead of probing has_method("physics_step").
##
## Behaviors override physics_step; the base does nothing.
## Authored Resource prototypes are duplicated per enemy; legacy Script slots
## still create a new instance. Mutable runtime state is never shared.

func physics_step(_enemy: Enemy, _player, _delta: float) -> void:
	pass
