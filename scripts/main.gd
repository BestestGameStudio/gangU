extends Node2D
## gangU entry scene. Boots the game; scene flow (hub <-> dungeon) will be
## managed from here by the hub/gate issues (#7/#9).
## #6: a RunManager child watches Player.died, blocks dead casting, and
## restarts the run with a full scene reload.

func _ready() -> void:
	print("gangU booted OK")
	var rm := RunManager.new()
	rm.name = "RunManager"
	rm.player = $Player
	add_child(rm)
