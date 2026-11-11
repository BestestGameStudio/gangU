class_name Consumable
extends Resource
## gangU #130 (foundation C3): one consumable DEFINITION (data) - identity
## plus the hook id its uses dispatch to.
##
## WHAT consumables exist, what their effects do, stack counts, and shop
## prices are all open human decisions (issue #130 open questions + the
## goods list). NO real effect, content, or price ships with this
## foundation; concrete Consumable .tres resources land with the C2-style
## catalog content once those decisions are made.

@export var consumable_name: String = "Consumable"
## Hook id Consumables.try_use dispatches on. A hook with NO registered
## handler refuses the use WITHOUT consuming inventory.
@export var effect_hook: StringName = &""
