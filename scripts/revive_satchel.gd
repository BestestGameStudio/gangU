extends Node
class_name ReviveSatchel
## gangU #12: tracks carried revive items and consumes one on player death to
## keep the run going, instead of the run restarting (#6's restart flow owns
## what happens when NO item is held - this node only intercepts with an item).
##
## CONTRACT GAP (explicit): reviving needs to RAISE player HP above 0. The
## merged #5 contract only mutates hp inside Player.apply_damage (HP can never
## change silently, health_changed emitted only there). A matching
## Player.heal(amount) entry point does NOT exist in main yet - it is a ~4-line
## addition to player.gd, which sits inside Daniel's #6 writer window. This
## node calls player.heal(revive_hp) and REQUIRES that method; without it the
## satchel logs an error and stays out of the way. The method is proposed in
## the PR body, not smuggled into this change.

signal revive_collected(carried: int)
signal revive_used(remaining: int, revived_hp: int)

## Set by the mounting scene. If unset, falls back to the "player" group.
@export var player_path: NodePath
## HP restored when a revive item is consumed.
@export var revive_hp: int = 50

var carried: int = 0
var _player: Player

func _ready() -> void:
	add_to_group("revive_satchel")
	if player_path != NodePath(""):
		_player = get_node_or_null(player_path) as Player
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player
	if _player == null:
		push_warning("ReviveSatchel: no player found (player_path unset, no 'player' group); idle.")
		return
	_player.died.connect(_on_player_died)

func collect() -> void:
	carried += 1
	revive_collected.emit(carried)
	print("[revive] collected, carried=", carried)

func _on_player_died() -> void:
	if carried <= 0:
		# No item: do nothing. #6's run restart handles this death.
		return
	carried -= 1
	if not _player.has_method(&"heal"):
		push_error("ReviveSatchel: Player.heal() missing (pending #6-window contract); cannot revive.")
		return
	_player.heal(revive_hp)
	revive_used.emit(carried, revive_hp)
	print("[revive] USED, remaining=", carried, " revived_hp=", revive_hp)
