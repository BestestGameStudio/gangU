class_name ForestPassage
extends Area2D
## Physical, non-portal passage. AreaLoader owns the actual scene swap.
@export_file("*.tscn") var target_path := ""
@export var arrival := Vector2.ZERO
signal entered(passage: ForestPassage)
func _ready() -> void:
 add_to_group("forest_passages")
 collision_layer = 0
 collision_mask = 2
 body_entered.connect(func(body: Node2D) -> void:
  if body is Player: entered.emit(self))
