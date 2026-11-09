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
## #100: per-area enemy spawning is DATA-DRIVEN. An area attaches ONE
## "SpawnData" child (scripts/area_spawn_data.gd) in its .tscn; the generic
## mounter reads it on every area swap. No SpawnData child => no enemies for
## that area (the hub stays empty; DungeonB's carrier holds zero entries).
## No area-name checks and no hardcoded positions/tables remain in code.

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
	## (#238) starting_spells fill the slots in order at boot, so the HUD grid
	## and the Tab panel start from the same seeded loadout. _ready runs once
	## per run (a death restart reloads this scene); hub returns never reseed.
	var caster: SpellCaster = $Player/SpellCaster
	for i in mini(caster.starting_spells.size(), SpellCaster.SLOT_COUNT):
		caster.assign_slot(i, caster.starting_spells[i])
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
	## - RewardPool gets the demo table (Placeholder Bolt, Summon Ally and,
	##   since #264, a placeholder CURRENCY entry for the current dungeons).
	## - SpellProgress carries the two approved placeholder fork upgrades,
	##   both at 10 Fire Ball casts: Split OR Beam, an equal-cost manual
	##   either/or choice in the non-pausing Tab panel. Only the
	##   Specialization tier is configured; Mastery/Signature stay unbuilt.
	var loot_table: RewardTable = preload("res://resources/rewards/demo_table.tres")
	var pool := RewardPool.new()
	pool.name = "RewardPool"
	pool.setup(loot_table)
	add_child(pool)
	## (#128, foundation C1) Run-scoped currency wallet - same ONE-persistent
	## child pattern; per-run reset comes free from the full scene reload.
	## Inert until currency content lands (amounts/carriers human-open).
	var wallet := CurrencyWallet.new()
	wallet.name = "CurrencyWallet"
	add_child(wallet)
	## (#130, foundation C3) Generic carried consumables - same ONE-persistent
	## child pattern; per-run reset comes free from the reload. ReviveSatchel's
	## auto-revive path stays untouched beside it. No production consumable
	## content or effects exist yet (human-open); the manager is inert until
	## they land.
	var consumables := Consumables.new()
	consumables.name = "Consumables"
	consumables.player_path = NodePath("../Player") # explicit, ReviveSatchel idiom
	add_child(consumables)
	## (#129, foundation C2) Hub shop: data-driven catalog + walk-up choice
	## panel - same ONE-persistent-child pattern. The panel starts hidden;
	## the hub vendor opens/closes it on player proximity (Daniel, 2026-11-07).
	var shop := Shop.new()
	shop.name = "Shop"
	shop.setup(preload("res://resources/shop/demo_catalog.tres"))
	shop.caster_path = NodePath("../Player/SpellCaster") # explicit, SpellProgress idiom
	## (#132) Data-driven paid-refresh price schedule (Fibonacci 1,2 seeds).
	shop.refresh_schedule = preload("res://resources/shop/demo_refresh_schedule.tres")
	add_child(shop)
	_shop = shop
	var shop_panel: ShopPanel = preload("res://scenes/shop_panel.tscn").instantiate()
	shop_panel.name = "ShopPanel"
	add_child(shop_panel)
	## (#209) Summons foundation: ONE persistent manager child (Shop idiom).
	## Enforces the shared summon cap and spawns from the caster's spell_cast.
	## Mount order per cross-author ACK: Shop -> SummonManager -> DirectoryPanel -> OwnedRelics.
	var summon_manager := SummonManager.new()
	summon_manager.name = "SummonManager"
	summon_manager.caster_path = NodePath("../Player/SpellCaster")
	add_child(summon_manager)
	## (#218) Hub spell directory: read-only walk-up panel listing the
	## current-run unlocked spells. Same ONE-persistent-child pattern; the
	## hub directory location opens/closes it on player proximity.
	var spell_directory_panel: SpellDirectoryPanel = preload("res://scenes/spell_directory_panel.tscn").instantiate()
	spell_directory_panel.name = "SpellDirectoryPanel"
	add_child(spell_directory_panel)
	## (#131, foundation C4) Run-scoped owned relics - same ONE-persistent
	## child pattern as the wallet/satchel/pool; per-run reset comes free
	## from the reload. Inert until relic content lands (C2 catalog).
	var owned_relics := OwnedRelics.new()
	owned_relics.name = "OwnedRelics"
	add_child(owned_relics)
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
		preload("res://resources/upgrades/fireball_m2_beam_homing.tres"),
		## (#211) Mana Shot Specialization paths: Volley (3-bolt fan) and
		## Lance (heavy piercing rail). Branch design and numbers are the
		## implementer's delegated discretion for this issue (Daniel via
		## staff-lead relay, 2026-11-08); 10-cast threshold mirrors the
		## approved Fire Ball tier-1 precedent.
		preload("res://resources/upgrades/manashot_volley.tres"),
		preload("res://resources/upgrades/manashot_lance.tres"),
		## (#265) Pickup Bolt Specialization paths: Flurry (faster, lighter)
		## and Heavy (slower piercing hitter). Branch design and numbers are
		## the implementer's delegated discretion for this issue (Daniel via
		## staff-lead relay, 2026-11-08); 10-cast threshold mirrors the
		## approved Fire Ball / Mana Shot tier-1 precedent.
		preload("res://resources/upgrades/bolt_flurry.tres"),
		preload("res://resources/upgrades/bolt_heavy.tres"),
	]
	add_child(progress)
	var panel: EquipPanel = preload("res://scenes/equip_panel.tscn").instantiate()
	panel.name = "EquipPanel"
	panel.player_path = NodePath("../Player")
	panel.upgrader_path = NodePath("../SpellProgress")
	add_child(panel)
	_load_hub()

var current_area: Node = null
## (#132) The mounted hub shop, kept so a dungeon victory can trigger its
## FREE stock refresh + paid-price reset from _on_objective_completed.
var _shop: Shop = null

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
	var p := get_node_or_null("Player") as Player
	var spawn := current_area.get_node_or_null("PlayerSpawn")
	if p and spawn:
		p.global_position = spawn.global_position
	if p:
		p.terrain = current_area.get_node_or_null("Terrain") as TerrainMap
	_mount_area_spawns(current_area)
	_mount_objective(current_area)
	_mount_exit_portal(current_area)
	_mount_revive_item(current_area)
	_mount_dungeon_modifiers(current_area)

## (#222) Dungeon modifiers: an area opts in with ONE "DungeonModifiers"
## child (DungeonModifierHost, SpawnData idiom). Bound LAST so the
## dungeon_entered event sees spawns, objective and portal in place. No
## production area carries one yet (content is human-open), so this is inert.
func _mount_dungeon_modifiers(area: Node) -> void:
	var host := area.get_node_or_null("DungeonModifiers") as DungeonModifierHost
	if host == null:
		return
	host.bind(area, get_node_or_null("Player/SpellCaster") as SpellCaster, get_node_or_null("RunManager") as RunManager)

## #100 generic mounter: every area swap reads the area's "SpawnData" child
## (AreaSpawnData). Entries are plain scene data - position, enemy scene and
## reward table per spawn. The carrier's player_path is assigned BEFORE
## add_child so Enemy._ready resolves it (production Player is in no group).
## Children of the area so a gate swap frees them.
func _mount_area_spawns(area: Node) -> void:
	var data := area.get_node_or_null("SpawnData") as AreaSpawnData
	if data == null:
		return
	var terrain := area.get_node_or_null("Terrain") as TerrainMap
	# #220: all spawning goes through the area's EnemySpawner (one per mount,
	# freed with the area). Default policy = mount every entry once.
	var spawner := EnemySpawner.new()
	spawner.name = "EnemySpawner"
	area.add_child(spawner)
	spawner.setup(data.entries, data.player_path, terrain, area)
	spawner.spawn_initial()

## #8 production objective: CLEAR_ALL over the spawned enemies in
## DungeonA. Mounted AFTER _mount_area_spawns - DungeonObjective._ready
## scans the "enemies" group, so the enemies must already be in the tree or
## the objective targets 0 and never completes.
## #177 / O1 (human decision 2026-11-08): red-gate DungeonB runs ELIMINATION -
## clear its mobs, then the Mustache Warlord spawns; the boss kill clears it.
## The boss enters the tree deferred, so its player_path (production Player is
## in no group, D6) is assigned in boss_spawned, before tree entry.
const WARLORD_SCENE: PackedScene = preload("res://scenes/mustache_warlord.tscn")
const DUNGEON_B_BOSS_SPAWN: Vector2 = Vector2(576, 240)
## #173 (human decision 2026-11-08): boss-gate DungeonC is a boss arena only -
## ELIMINATION with zero mobs, so the Head boss spawns on entry.
const HEAD_BOSS_SCENE: PackedScene = preload("res://scenes/head_boss.tscn")
const DUNGEON_C_BOSS_SPAWN: Vector2 = Vector2(576, 300)

func _mount_objective(area: Node) -> void:
	var obj := DungeonObjective.new()
	obj.name = "DungeonObjective"
	if area.name == "DungeonA":
		obj.dungeon_id = &"dungeon_a"
	elif area.name == "DungeonB":
		obj.dungeon_id = &"dungeon_b"
		obj.objective_type = DungeonObjective.ObjectiveType.ELIMINATION
		obj.boss_scene = WARLORD_SCENE
		obj.boss_spawn_position = (area as Node2D).to_global(DUNGEON_B_BOSS_SPAWN) if area is Node2D else DUNGEON_B_BOSS_SPAWN
		obj.boss_spawned.connect(_on_boss_spawned)
	elif area.name == "DungeonC":
		obj.dungeon_id = &"dungeon_c"
		obj.objective_type = DungeonObjective.ObjectiveType.ELIMINATION
		obj.boss_scene = HEAD_BOSS_SCENE
		obj.boss_spawn_position = (area as Node2D).to_global(DUNGEON_C_BOSS_SPAWN) if area is Node2D else DUNGEON_C_BOSS_SPAWN
		obj.boss_spawned.connect(_on_boss_spawned)
	else:
		obj.free()
		return
	obj.objective_completed.connect(_on_objective_completed)
	area.add_child(obj)

## Boss -> Main/<Area>/<Boss>, so the Player is "../../Player" (AreaSpawnData idiom).
func _on_boss_spawned(boss: Node) -> void:
	if boss is Enemy:
		boss.player_path = NodePath("../../Player")

func _on_objective_completed(dungeon_id: StringName) -> void:
	print("objective completed: ", dungeon_id)
	## (#132) Confirmed dungeon VICTORY only: free stock refresh and the
	## paid-refresh price resets (Daniel 2026-11-07). A plain return to hub
	## (exit portal without a clear) never reaches this path.
	if _shop != null:
		_shop.on_dungeon_victory()

## #9 production exit portal: normal-gate DungeonA mounts it UNLOCKED (retreat
## anytime, objective not required). Returns to the hub in the SAME run via a
## deferred swap - the shared Player is repositioned, never recreated, so
## spells and current HP are retained. Red-gate DungeonB (#177 / O1, human
## decision 2026-11-08) now has an ELIMINATION objective, so it mounts the
## portal LOCKED per D12 (clear-or-die): it opens when the Warlord dies. The
## #55 unlocked mount only existed because DungeonB had no objective.
## An area with an "ExitPoint" marker gets an unlocked portal at that marker.
func _mount_exit_portal(area: Node) -> void:
	var exit_point := area.get_node_or_null("ExitPoint") as Node2D
	if exit_point == null and not area.name in [&"DungeonA", &"DungeonB", &"DungeonC"]:
		return
	var portal: ExitPortal = preload("res://scenes/exit_portal.tscn").instantiate()
	portal.name = "ExitPortal"
	portal.position = exit_point.position if exit_point else Vector2(576, 120)
	# Lock only when a completable objective exists: an ELIMINATION objective
	# without a boss_scene could never clear, so a locked portal would
	# soft-lock the run (#55). Fail open instead.
	var obj := area.get_node_or_null("DungeonObjective") as DungeonObjective
	var completable := obj != null and (obj.objective_type != DungeonObjective.ObjectiveType.ELIMINATION or obj.boss_scene != null)
	# #173: boss-gate DungeonC is clear-or-die too (locked until the Head dies).
	if area.name in [&"DungeonB", &"DungeonC"] and completable:
		portal.locked = true
		portal.objective_path = NodePath("../DungeonObjective")
	portal.red_portal_look = area.name == &"DungeonB"  # #204: portal look only on the RED dungeon's exit portal (both its locked and unlocked states)
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
