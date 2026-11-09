extends SceneTree
## #388 showcase: boots main.tscn and steps the shield through a few states so
## a --write-movie run (--fixed-fps 30) captures the white shield bar under
## the HP bar, including timed decay. Decay tuning here is a showcase choice
## (delay 1s, 40/s), not game tuning.
##   frames   0-19: no shield (bar hidden)
##   frame      20: +60 shield
##   frame      40: hit for 75 (shield absorbs 60, HP takes 15)
##   frame      60: +350 shield (uncapped, bar full, label shows 350)
##   frames  60-89: holding (decay delay)
##   frames 90-   : draining at 40/s
##   frame     150: +20 grant refreshes the delay (holds again until ~180)
##   then drains to 0 and the bar hides (~frame 455)

var _player: Player
var _frame := 0

func _initialize() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	_player = main.get_node("Player")
	_player.shield_decay_delay = 1.0
	_player.shield_decay_rate = 40.0

func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		20:
			_player.add_shield(60)
		40:
			_player.apply_damage(75)
		60:
			_player.add_shield(350)
		150:
			_player.add_shield(20)
	if _frame % 15 == 0:
		print("[shield_hud] frame %d shield %d hp %d" % [_frame, _player.shield, _player.hp])
	return false
