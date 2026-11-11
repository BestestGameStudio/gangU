extends Area2D
class_name ReviveItem
## gangU #12: a revive item lying in the world. Picked up on player contact and
## handed to the ReviveSatchel. Contains NO death/restart logic - the satchel
## owns consumption; run restart stays #6's contract.

func _ready() -> void:
	add_to_group("revive_items")
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if not body is Player:
		return
	var satchel := get_tree().get_first_node_in_group("revive_satchel") as ReviveSatchel
	if satchel != null:
		satchel.collect()
		queue_free()
