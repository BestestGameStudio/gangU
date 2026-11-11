extends Node
class_name ReviveSatchel
## gangU #12: tracks carried revive items and revives the player when the run
## manager asks, per the ACCEPTED #6 x #12 contract (Daniel/peer-lead agreed):
##
##   - The run manager (pure #6) wires its exported `satchel` to this node and
##     calls try_revive() SYNCHRONOUSLY BEFORE latching/disabling/reloading on
##     player death: `if satchel != null and satchel.try_revive(): return`.
##   - This node has NO died() listener by design - interception ordering is
##     owned by the run manager, never by signal order.
##   - player_path MUST be set explicitly BEFORE tree entry; there is no
##     Player.find fallback (accepted contract).
##   - Player.heal() mirrors apply_damage: clampi + health_changed emitted
##     inside (lands with the #12 integration PR; died() still fires at HP 0
##     and the HUD recovers on health_changed).
##
## With no items carried, try_revive() returns false and the run manager's
## normal death/restart flow proceeds untouched.

signal revive_collected(carried: int)
signal revive_used(remaining: int, revived_hp: int)

## REQUIRED: set before adding this node to the tree. No group fallback.
@export var player_path: NodePath
## HP restored when a revive item is consumed.
@export var revive_hp: int = 50

var carried: int = 0
var _player: Player

func _ready() -> void:
	add_to_group("revive_satchel")
	if player_path == NodePath(""):
		push_error("ReviveSatchel: player_path is required (accepted #6/#12 contract: explicit wiring, no group fallback).")
		return
	_player = get_node_or_null(player_path) as Player
	if _player == null:
		push_error("ReviveSatchel: player_path did not resolve to a Player.")

func collect() -> void:
	carried += 1
	revive_collected.emit(carried)
	print("[revive] collected, carried=", carried)

## Called by the run manager before its death handling. Consumes one item and
## revives; returns true only when a revive actually happened.
func try_revive() -> bool:
	if carried <= 0:
		return false
	if _player == null:
		push_error("ReviveSatchel: cannot revive (missing player).")
		return false
	carried -= 1
	_player.heal(revive_hp)
	revive_used.emit(carried, revive_hp)
	print("[revive] USED, remaining=", carried, " revived_hp=", revive_hp)
	return true
