class_name BestiaryStation
extends Area2D
## (#325) Hub bestiary location. Walking up OPENS the bestiary panel and
## walking away CLOSES it - the SpellDirectory/ShopVendor idiom: the
## persistent Main-mounted panel is found via the "bestiary_panel" group,
## so this scene stands alone in the hub.

func _ready() -> void:
	add_to_group("bestiary_stations")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		var panel := get_tree().get_first_node_in_group("bestiary_panel")
		if panel != null:
			panel.open()

func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		var panel := get_tree().get_first_node_in_group("bestiary_panel")
		if panel != null:
			panel.close()
