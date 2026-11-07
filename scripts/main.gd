extends Node2D
## gangU entry scene. #7: boots into the hub; gates transport the player into
## dungeons. Exit portals / gate lock-in rules are #9 scope.

var current_area: Node = null

func _ready() -> void:
	print("gangU booted OK")
	_load_hub()

func _load_hub() -> void:
	_swap(preload("res://scenes/hub.tscn").instantiate())
	for g: Gate in get_tree().get_nodes_in_group("gates"):
		g.entered.connect(_on_gate_entered)

func _on_gate_entered(gate: Gate) -> void:
	print("gate entered: ", "RED" if gate.gate_type == Gate.GateType.RED else "NORMAL")
	_swap(gate.target_dungeon.instantiate())

func _swap(scene: Node) -> void:
	if current_area:
		remove_child(current_area)
		current_area.queue_free()
	current_area = scene
	add_child(current_area)
