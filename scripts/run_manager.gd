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
##
## #351 FULL-RESET SCOPE (Colin, 2026-11-08): death resets EVERYTHING run-
## scoped - the world (current area -> hub, enemies, pickups), dungeon
## cleared-state, spells, upgrades, coins and the map. No partial carryover.
## Today all of that lives in nodes under the run scene, so the reload alone
## wipes it. State that outlives the reload (an autoload, a node parked on
## the tree root, e.g. future overworld cleared-state #348 or the map #347)
## MUST join RUN_STATE_GROUP and implement reset_run_state(); _restart calls
## it on every member right before the reload. Cross-run META records (the
## Bestiary, #325) are not run state and stay out of this group.

signal run_restarting()

## #351: group for run state that survives reload_current_scene (autoloads,
## root-parked nodes). Members implement reset_run_state() -> void.
const RUN_STATE_GROUP := &"run_state"

@export var restart_delay: float = 1.5
## Production wiring: main.gd passes the shared Player explicitly. Test scenes
## may leave this unset and rely on the Player.find fallback instead.
@export var player: Player

## #12 contract: optional. When wired, the satchel gets a synchronous chance to
## revive BEFORE any latch/disable/reload; null keeps this manager pure #6.
@export var satchel: ReviveSatchel

var _restarting := false
var _watched: Player = null

func _process(_delta: float) -> void:
	if _watched != null:
		return
	var p: Player = player if player != null else Player.find(get_tree())
	if p == null:
		return
	_watched = p
	p.died.connect(_on_player_died)

func _on_player_died() -> void:
	if _restarting:
		return
	# #12 interception: a carried revive item cancels the restart entirely.
	if satchel != null and satchel.try_revive():
		return
	_restarting = true
	_disable_casting()
	PlayerDeathPresentation.begin(get_parent(), _watched, restart_delay)
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
	reset_persistent_run_state(get_tree())
	get_tree().reload_current_scene()

## #351: explicit reset for run state the scene reload cannot reach.
static func reset_persistent_run_state(tree: SceneTree) -> void:
	for n in tree.get_nodes_in_group(RUN_STATE_GROUP):
		if n.has_method(&"reset_run_state"):
			n.call(&"reset_run_state")
		else:
			push_error("RunManager: '%s' is in %s but has no reset_run_state()" % [n.get_path(), RUN_STATE_GROUP])
