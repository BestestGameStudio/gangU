class_name Gate
extends Area2D
## #7: gate object. Normal and red gates are distinct in code (gate_type) and
## visuals (tint + label). Entering a gate transports the player to its dungeon.
## Red-gate lock-in rules themselves are #9 scope; this is transport + typing only.

enum GateType { NORMAL, RED }

@export var gate_type: GateType = GateType.NORMAL
@export var target_dungeon: PackedScene

signal entered(gate: Gate)

func _ready() -> void:
	add_to_group("gates")
	body_entered.connect(_on_body_entered)
	var tint: ColorRect = $ColorRect
	var label: Label = $TypeLabel
	if gate_type == GateType.RED:
		tint.color = Color(0.85, 0.15, 0.15)
		label.text = "RED"
	else:
		tint.color = Color(0.15, 0.6, 0.9)
		label.text = "NORMAL"

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		entered.emit(self)
