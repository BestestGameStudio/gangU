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
## #34: demo enemy mount - Daniel-approved demo config: exactly THREE enemies
## in DungeonA (normal gate), spread away from the entrance (PlayerSpawn at the
## room's bottom edge). Code-mounted here - no scene edits - each with an
## explicit player_path set BEFORE tree entry (production Player is in no
## group). Count/positions are the human-approved demo design, not invented
## defaults; DungeonB (red gate) is out of the demo loop and gets none.

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
	## #12 production wiring: ONE persistent satchel mounted on Main so carried
	## count survives area swaps. Code assign, not a tscn NodePath - a scene-set
	## NodePath on a typed export resolves null silently (verified in #12 prep).
	## Explicit player_path per the #34 no-group convention; resolved relative
	## to the satchel itself (Main/ReviveSatchel -> Main/Player = "../Player").
	## INERT by design: no revive items are placed in production (content /
	## placement / counts are an OPEN human choice), so carried stays 0 and
	## interception never fires until that decision lands.
	var satchel: ReviveSatchel = preload("res://scenes/revive_satchel.tscn").instantiate()
	satchel.name = "ReviveSatchel"
	satchel.player_path = NodePath("../Player")
	add_child(satchel)
	rm.satchel = satchel
	satchel.revive_collected.connect(_on_revive_collected)
	## (E) Reward/progression production mounts - same ONE-persistent-child
	## pattern as ReviveSatchel. Per-run reset comes free from RunManager's
	## full scene reload. First playable config (approved by Daniel via his
	## Instinct, 2026-11-07, "yep!" to the delivered package):
	## - RewardPool gets the single-entry demo table (Placeholder Bolt).
	## - SpellProgress carries the two approved placeholder fork upgrades,
	##   both at 10 Fire Ball casts: Split OR Beam, an equal-cost manual
	##   either/or choice in the non-pausing Tab panel. Only the
	##   Specialization tier is configured; Mastery/Signature stay unbuilt.
	var loot_table: RewardTable = preload("res://resources/rewards/demo_table.tres")
	var pool := RewardPool.new()
	pool.name = "RewardPool"
	pool.setup(loot_table)
	add_child(pool)
	var progress := SpellProgress.new()
	progress.name = "SpellProgress"
	progress.caster_path = NodePath("../Player/SpellCaster")
	progress.upgrades = [
		preload("res://resources/upgrades/fireball_split.tres"),
		preload("res://resources/upgrades/fireball_beam.tres"),
		## Mastery-tier forks (2026-11-07, lead's numeric placeholder choices
		## under Colin's judgment grant - NOT preexisting owner-approved
		## content): 15 casts of a Specialization result qualify its fork.
		preload("res://resources/upgrades/fireball_m2_split_wide.tres"),
		preload("res://resources/upgrades/fireball_m2_split_heavy.tres"),
		preload("res://resources/upgrades/fireball_m2_beam_long.tres"),
		preload("res://resources/upgrades/fireball_m2_beam_heavy.tres"),
		preload("res://resources/upgrades/fireball_m2_beam_piercing.tres"),
	]
	add_child(progress)
	var panel: EquipPanel = preload("res://scenes/equip_panel.tscn").instantiate()
	panel.name = "EquipPanel"
	panel.player_path = NodePath("../Player")
	panel.upgrader_path = NodePath("../SpellProgress")
	add_child(panel)
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
	_mount_demo_enemies(current_area)
	_mount_objective(current_area)
	_mount_exit_portal(current_area)
	_mount_revive_item(current_area)

## #34 demo config: three enemies, upper half of the room, far from the
## entrance spawn (576,560). Children of the area so a gate swap frees them.
const DEMO_ENEMY_POSITIONS: Array[Vector2] = [Vector2(250, 280), Vector2(576, 220), Vector2(900, 280)]

func _mount_demo_enemies(area: Node) -> void:
	if area.name != "DungeonA":
		return
	for pos in DEMO_ENEMY_POSITIONS:
		var e: Enemy = preload("res://scenes/enemy.tscn").instantiate()
		e.position = pos
		# First playable loot: every kill rolls the single-Bolt table until
		# the pickup is granted (pool removes on grant only); later kills
		# then roll null. Unpicked floor copies can repeat; extra copies
		# consume with no effect (approved 2026-11-07 package).
		e.reward_table = preload("res://resources/rewards/demo_table.tres")
		# Enemy is Main/DungeonA/EnemyN, Player is Main/Player - set the
		# explicit target BEFORE add_child so Enemy._ready resolves it.
		e.player_path = NodePath("../../Player")
		area.add_child(e)

## #8 production objective: CLEAR_ALL over the mounted demo enemies in
## DungeonA. Mounted AFTER _mount_demo_enemies - DungeonObjective._ready
## scans the "enemies" group, so the enemies must already be in the tree or
## the objective targets 0 and never completes.
func _mount_objective(area: Node) -> void:
	if area.name != "DungeonA":
		return
	var obj := DungeonObjective.new()
	obj.name = "DungeonObjective"
	obj.dungeon_id = &"dungeon_a"
	obj.objective_completed.connect(_on_objective_completed)
	area.add_child(obj)

func _on_objective_completed(dungeon_id: StringName) -> void:
	print("objective completed: ", dungeon_id)

## #9 production exit portal: normal-gate DungeonA mounts it UNLOCKED (retreat
## anytime, objective not required). Returns to the hub in the SAME run via a
## deferred swap - the shared Player is repositioned, never recreated, so
## spells and current HP are retained. #55: red-gate DungeonB mounts it
## UNLOCKED too - DungeonB has no enemies/objective, so without a portal an
## entered run could not end (soft-lock). Locked objective-gated portal
## mechanics remain proven by the labeled fixture regression in
## scripts/test9_exit_flow.gd.
func _mount_exit_portal(area: Node) -> void:
	if area.name != "DungeonA" and area.name != "DungeonB":
		return
	var portal: ExitPortal = preload("res://scenes/exit_portal.tscn").instantiate()
	portal.name = "ExitPortal"
	portal.position = Vector2(576, 120)
	portal.entered.connect(_on_exit_portal_entered)
	area.add_child(portal)

func _on_exit_portal_entered(_portal: ExitPortal) -> void:
	_load_hub.call_deferred()

## #54: ONE revive item (green cross) per run, spawned in DungeonA only, away
## from the entrance spawn (576,560), the demo enemies (y<=280) and the exit
## portal (576,120). Scoped choice under the 2026-11-07 collaboration grants:
## placement/count here are the bounded #54 decision, not a new design tier.
## Per-run semantics ride the existing full-scene-reload restart: Main
## rebuilds fresh each run, so _revive_claimed resets for free. Within a run
## the flag latches on the FIRST collection - a successful revive continues
## the same scene, so claimed-once (even after the item is consumed) keeps
## re-entered DungeonA free of a second spawn; leaving UNclaimed keeps the
## item available on re-entry.
var _revive_claimed := false

func _on_revive_collected(_carried: int) -> void:
	_revive_claimed = true

func _mount_revive_item(area: Node) -> void:
	if area.name != "DungeonA" or _revive_claimed:
		return
	var item: ReviveItem = preload("res://scenes/revive_item.tscn").instantiate()
	item.name = "ReviveItem"
	item.position = Vector2(900, 480)
	area.add_child(item)
