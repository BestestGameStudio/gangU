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
## Dead-cast guard (#6, review finding): the moment the player dies, every
## SpellCaster on the player is disabled, so a dead player can NEVER cast
## during the death pause: no projectile spawn, no cooldown start, no
## spell_cast. The scene reload rebuilds the caster fresh, so casting works
## again on the next run.
##
## Consumes: Player.died (#5). Exposes: run_restarting() for the #11 HUD.
## Later integration (#9/#10): if run state moves out of scene definitions,
## reset it here explicitly instead of relying on the reload.

signal run_restarting()

@export var restart_delay: float = 1.5
## Production wiring: main.gd passes the shared Player explicitly, because the
## main.tscn Player is in no group. Test scenes may leave this unset and rely
## on the "player" group fallback instead.
@export var player: Player

var _restarting := false
var _watched: Player = null

func _process(_delta: float) -> void:
	if _watched != null:
		return
	var p: Player = player if player != null else get_tree().get_first_node_in_group("player")
	if p == null:
		return
	_watched = p
	p.died.connect(_on_player_died)

func _on_player_died() -> void:
	if _restarting:
		return
	_restarting = true
	_disable_casting()
	run_restarting.emit()
	get_tree().create_timer(restart_delay).timeout.connect(_restart)

## A dead player must not cast: cut every caster's processing the instant
## death arrives, so SpellCaster's input-driven cast path cannot fire during
## the death pause. No restore needed - the reload rebuilds the caster.
func _disable_casting() -> void:
	for c in _watched.get_children():
		if c is SpellCaster:
			c.process_mode = Node.PROCESS_MODE_DISABLED

func _restart() -> void:
	get_tree().reload_current_scene()
