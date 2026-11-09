extends SceneTree
## #388 showcase: boots main.tscn and steps the shield through a few states so
## a --write-movie run captures the white shield bar under the HP bar.
##   frames  0-19: no shield (bar hidden)
##   frames 20-39: +60 shield
##   frames 40-59: hit for 75 (shield absorbs 60, HP takes 15)
##   frames 60-79: +350 shield (uncapped, bar full, label shows 350)

var _player: Player
var _frame := 0

func _initialize() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	_player = main.get_node("Player")

func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		20:
			_player.add_shield(60)
		40:
			_player.apply_damage(75)
		60:
			_player.add_shield(350)
	return false
