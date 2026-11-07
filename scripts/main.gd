extends Node
## gangU entry point (#1 scaffold).
## On the #5 branch: boots directly into the #5 test arena so the damage
## pipeline is visible without hub navigation (hub flow lands with #7).

const ARENA_SCENE := "res://scenes/test_arena.tscn"

func _ready() -> void:
	var arena: Node = (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(arena)
