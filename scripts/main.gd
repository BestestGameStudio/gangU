extends Node2D
## gangU entry scene. #7: boots into the hub; gates transport the shared
## player into dungeons. Exit portals / gate lock-in rules are #9 scope.
## The Player and FollowCamera live in main.tscn and are never replaced:
## areas only swap below them, and the player is moved to each area's
## PlayerSpawn marker on entry.

var current_area: Node = null

func _ready() -> void:
	print("gangU booted OK")
	_load_hub()

func _load_hub() -> void:
	_swap(preload("res://scenes/hub.tscn").instantiate())

func _on_gate_entered(gate: Gate) -> void:
	print("gate entered: ", "RED" if gate.gate_type == Gate.GateType.RED else "NORMAL")
	_swap(gate.target_dungeon.instantiate())

func _swap(area: Node) -> void:
	if current_area:
		remove_child(current_area)
		current_area.queue_free()
	current_area = area
	add_child(current_area)
	for g: Gate in get_tree().get_nodes_in_group("gates"):
		if not g.entered.is_connected(_on_gate_entered):
			g.entered.connect(_on_gate_entered)
	var p := get_node_or_null("Player")
	var spawn := current_area.get_node_or_null("PlayerSpawn")
	if p and spawn:
		p.global_position = spawn.global_position
