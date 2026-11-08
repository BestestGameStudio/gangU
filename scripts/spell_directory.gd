class_name SpellDirectory
extends Area2D
## (#218) Hub spell directory location. Walking up OPENS the read-only
## directory panel and walking away CLOSES it - the ShopVendor idiom: an
## Area2D the persistent Main-mounted panel is found from via the
## "spell_directory_panel" group, so this scene stands alone in the hub.
## The listing only DISPLAYS the player's current-run unlock set; it never
## buys, equips, or grants anything.

func _ready() -> void:
	add_to_group("spell_directories")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		var panel := get_tree().get_first_node_in_group("spell_directory_panel")
		if panel != null:
			# The walk-up body IS the player: hand its caster to the panel
			# directly. Production Player is not in the "player" group, so
			# the panel cannot rely on the group fallback there.
			panel.open(body.get_node_or_null("SpellCaster"))

func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		var panel := get_tree().get_first_node_in_group("spell_directory_panel")
		if panel != null:
			panel.close()
