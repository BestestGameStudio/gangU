extends Node
class_name RunManager
## #6 Run manager: when the Player dies, the run restarts.
##
## Restart = full reload of the current scene after a short death pause, so
## NOTHING carries over: player HP/position, enemies, live projectiles and any
## spells collected during the run all rebuild from the scene definition, and
## SpellCaster (#3) re-adds only its starting_spells. Repeatable: every death
## restarts the run again.
##
## Consumes: Player.died (#5). Exposes: run_restarting() for the #11 HUD.
## Later integration (#9/#10): if run state moves out of scene definitions,
## reset it here explicitly instead of relying on the reload.

signal run_restarting()

@export var restart_delay: float = 1.5

var _restarting := false

func _ready() -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p == null:
		push_warning("RunManager: no node in group 'player'; nothing to watch")
		return
	p.died.connect(_on_player_died)

func _on_player_died() -> void:
	if _restarting:
		return
	_restarting = true
	run_restarting.emit()
	get_tree().create_timer(restart_delay).timeout.connect(_restart)

func _restart() -> void:
	get_tree().reload_current_scene()
