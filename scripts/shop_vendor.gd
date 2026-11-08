class_name ShopVendor
extends Area2D
## (#129, foundation C2) Hub vendor. Walking up OPENS the shop panel and
## walking away CLOSES it (Daniel, 2026-11-07: "yes open a panel"). Gate
## idiom: an Area2D the persistent Main-mounted panel is found from via
## the "shop_panel" group, so this scene stands alone in the hub.

func _ready() -> void:
	add_to_group("shop_vendors")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		var panel := get_tree().get_first_node_in_group("shop_panel")
		if panel != null:
			panel.open()

func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		var panel := get_tree().get_first_node_in_group("shop_panel")
		if panel != null:
			panel.close()
