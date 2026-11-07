class_name ExitPortal
extends Area2D
## #9: exit portal back to the hub. Using it returns the player to the hub in
## the SAME run: spells, pickups and current HP are retained because the shared
## Player node is repositioned, never recreated (transport is owned by main.gd,
## which connects `entered` the same way it connects gates).
## Normal-gate dungeons mount it unlocked (retreat at any time, objective not
## required). Red-gate dungeons WITH an objective mount it locked; it opens
## when the dungeon objective completes (clear-or-die: death restarts the run
## via RunManager). #55: a red-gate dungeon WITHOUT an objective (DungeonB in
## the demo config) mounts it unlocked - no objective exists to open a locked
## one, so a locked mount would soft-lock the run.

signal entered(portal: ExitPortal)

## Locked portals ignore the player. Red dungeons with an objective start
## locked and open on completion; normal dungeons leave this false.
@export var locked: bool = false
## Optional path to a node with an `objective_completed` signal (the #8
## DungeonObjective). Duck-typed by signal name so this file stands alone.
@export var objective_path: NodePath

func _ready() -> void:
	add_to_group("exit_portals")
	body_entered.connect(_on_body_entered)
	if objective_path != NodePath(""):
		var obj := get_node_or_null(objective_path)
		if obj != null and obj.has_signal("objective_completed"):
			obj.objective_completed.connect(_on_objective_completed)
		else:
			push_warning("ExitPortal: objective_path did not resolve to a node with an objective_completed signal.")
	_refresh_visual()

func unlock() -> void:
	if not locked:
		return
	locked = false
	print("exit portal unlocked")
	_refresh_visual()

func _on_objective_completed(_dungeon_id) -> void:
	unlock()

func _on_body_entered(body: Node2D) -> void:
	if locked:
		return
	if body is Player:
		entered.emit(self)

func _refresh_visual() -> void:
	var tint: ColorRect = $ColorRect
	var label: Label = $StateLabel
	if locked:
		tint.color = Color(0.35, 0.35, 0.4)
		label.text = "LOCKED"
	else:
		tint.color = Color(0.5, 0.2, 0.8)
		label.text = "EXIT"
