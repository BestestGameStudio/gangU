class_name PanelStation
extends Area2D
## Hub walk-up location (shop vendor #129, spell directory #218, bestiary
## #325). A Player walking in OPENS the persistent Main-mounted panel found
## via `panel_group`; walking away CLOSES it, so the scene stands alone in
## the hub.

@export var panel_group: StringName
## Hand the walk-up Player's SpellCaster to panel.open(caster).
@export var pass_caster := false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		var panel := get_tree().get_first_node_in_group(panel_group)
		if panel == null:
			return
		if pass_caster:
			panel.call(&"open", body.get_node_or_null("SpellCaster"))
		else:
			panel.call(&"open")

func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		var panel := get_tree().get_first_node_in_group(panel_group)
		if panel != null:
			panel.call(&"close")
