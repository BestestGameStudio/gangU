extends Node2D
## gangU entry scene. Boots the game; scene flow (hub <-> dungeon) will be
## managed from here by the hub/gate issues (#7/#9).
## #20: a BackgroundGrid child gives a world-space reference so camera-follow
## movement is visible. Pure background (z_index -100), behind the Player,
## no gameplay interaction.
## #6: a RunManager child watches Player.died, blocks dead casting, and
## restarts the run with a full scene reload.
## #11: a HUD child shows health/spells/cooldowns. Mounted with an explicit
## player_path (no group fallback); the scene reload remounts it fresh.

func _ready() -> void:
	print("gangU booted OK")
	var grid := BackgroundGrid.new()
	grid.name = "BackgroundGrid"
	add_child(grid)
	move_child(grid, 0)
	var rm := RunManager.new()
	rm.name = "RunManager"
	rm.player = $Player
	add_child(rm)
	var hud: HUD = preload("res://scenes/hud.tscn").instantiate()
	hud.player_path = NodePath("../Player") # explicit, read in HUD._ready on tree entry
	add_child(hud)
	_load_hub()

var current_area: Node = null

func _load_hub() -> void:
	_swap(preload("res://scenes/hub.tscn").instantiate())

func _on_gate_entered(gate: Gate) -> void:
	print("gate entered: ", "RED" if gate.gate_type == Gate.GateType.RED else "NORMAL")
	_swap.call_deferred(gate.target_dungeon.instantiate())

func _swap(area: Node) -> void:
	if current_area:
		remove_child(current_area)
		current_area.queue_free()
	current_area = area
	add_child(current_area)
	for g: Gate in get_tree().get_nodes_in_group("gates"):
		if not g.entered.is_connected(_on_gate_entered):
			g.entered.connect(_on_gate_entered)
	var p := get_node_or_null("Player")
	var spawn := current_area.get_node_or_null("PlayerSpawn")
	if p and spawn:
		p.global_position = spawn.global_position
