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
## #346: boot -> hub -> (TRAVEL gate) -> overworld -> (entrance) -> dungeon;
## exit portals return to that dungeon's overworld entrance (#378). Overworld entrance guards mount from
## "EntranceGuards" carriers only while their dungeon is uncleared this run.

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
	## #359: one persistent boss-music player; started by _on_boss_spawned
	## (RED-entered dungeons + the Head/Beast arenas). Freed with Main on a
	## death restart, so a theme never leaks into the reloaded run.
	boss_music = BossMusic.new()
	boss_music.name = "BossMusic"
	add_child(boss_music)
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
	## (#325) Hub bestiary: read-only walk-up panel over the cross-run
	## encountered-enemy record (Bestiary, static + saved to user://, so it
	## survives the restart reload). Same ONE-persistent-child pattern.
	var bestiary_panel: BestiaryPanel = preload("res://scenes/bestiary_panel.tscn").instantiate()
	bestiary_panel.name = "BestiaryPanel"
	add_child(bestiary_panel)
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
		## Spirit Punch route (#305): base -> burst -> launch -> bubble,
		## tiers 1/2/3. Cast thresholds 10/15/20 are provisional
		## implementation discretion, not approved final balance.
		preload("res://resources/upgrades/spirit_punch_burst.tres"),
		preload("res://resources/upgrades/spirit_punch_launch.tres"),
		preload("res://resources/upgrades/spirit_punch_bubble.tres"),
		## Water Ball tree (#331): three branches from the base, tiers
		## 1/2/3 each - Steer (guided -> seeking -> tidal seeker), Splash
		## (splash -> barrage -> heavy rain), Bubble (water bubble ->
		## surging -> big ball). Thresholds 10/15/20 mirror #305 and are
		## provisional, not approved final balance.
		preload("res://resources/upgrades/water_guided.tres"),
		preload("res://resources/upgrades/water_seeking.tres"),
		preload("res://resources/upgrades/water_tidal.tres"),
		preload("res://resources/upgrades/water_splash.tres"),
		preload("res://resources/upgrades/water_barrage.tres"),
		preload("res://resources/upgrades/water_heavy_rain.tres"),
		preload("res://resources/upgrades/water_bubble.tres"),
		preload("res://resources/upgrades/water_surging_bubble.tres"),
		preload("res://resources/upgrades/water_big_ball.tres"),
		## Stone Hammer tree (#370): two routes from the base, tiers 1/2/3
		## each - Crush (reaper -> titan -> vortex) and Rhythm (rhythm ->
		## leap -> dice roll). One route per run, like Water Ball.
		## Thresholds 10/15/20 mirror #305/#331 and are provisional.
		preload("res://resources/upgrades/hammer_reaper.tres"),
		preload("res://resources/upgrades/hammer_titan.tres"),
		preload("res://resources/upgrades/hammer_vortex.tres"),
		preload("res://resources/upgrades/hammer_rhythm.tres"),
		preload("res://resources/upgrades/hammer_leap.tres"),
		preload("res://resources/upgrades/hammer_gambler.tres"),
	]
	add_child(progress)
	var panel: EquipPanel = preload("res://scenes/equip_panel.tscn").instantiate()
	panel.name = "EquipPanel"
	panel.player_path = NodePath("../Player")
	panel.upgrader_path = NodePath("../SpellProgress")
	add_child(panel)
	## (#347) Player map: ONE persistent WorldMap record + its M panel (Shop
	## idiom; per-run reset comes free from the reload). Explored terrain is
	## shown automatically, details only as player-placed marks (Colin,
	## 2026-11-08). reveal_rule is deliberately LEFT UNSET: reveal timing is
	## Colin's open call (ARCHITECTURE.md O7), so nothing auto-reveals yet.
	var world_map := WorldMap.new()
	world_map.name = "WorldMap"
	world_map.player = $Player
	# (#347) Colin, 2026-11-08: terrain appears as you explore - wire the
	# production explore rule (vision circle, matches TerrainFog).
	world_map.reveal_rule = WorldMap.explore_rule
	world_map.cleared_rule = is_cleared # #366: cleared dungeons are marked
	add_child(world_map)
	_world_map = world_map
	var map_panel := MapPanel.new()
	map_panel.name = "MapPanel"
	map_panel.world_map_path = NodePath("../WorldMap")
	map_panel.travel_rule = can_map_travel_to # #366
	add_child(map_panel)
	map_panel.travel_requested.connect(_request_map_travel)
	_mount_fast_travel() # #349: separate mount after map setup
	_load_hub()

var current_area: Node = null
## #359: boss theme player (RED dungeon bosses, Head, Beast).
var boss_music: BossMusic = null
## (#132) The mounted hub shop, kept so a dungeon victory can trigger its
## FREE stock refresh + paid-price reset from _on_objective_completed.
var _shop: Shop = null
## (#347) The run's map record; told about every area swap.
var _world_map: WorldMap = null

## (#350) Type of the gate the current dungeon was entered through, or -1 when
## the area was not entered through a gate (hub, direct _swap fixtures). Since
## a hub offering's NORMAL/RED type is rolled by chance, the RED lock-in follows
## the gate actually entered, not the target area's name.
var _entry_gate_type: int = -1

## #346 core loop (Colin, 2026-11-08): the hub sits OUTSIDE the overworld and
## keeps its services; one TRAVEL gate in the hub leads to the overworld,
## whose entrances lead into the dungeons. Leaving a dungeon by its exit
## portal returns to its overworld entrance (#378); the hub is one TRAVEL
## gate away, and #349 fast return still goes straight to the hub.
const OVERWORLD_SCENE := "res://scenes/overworld.tscn"

## #346: dungeon_ids cleared this run. Per-run for free: a death restart
## reloads Main. An overworld entrance only gets its guards while its
## dungeon is absent from here.
var cleared_dungeons: Dictionary = {}

## #400 (Daniel, 2026-11-09): after a clear, that dungeon's entrance gates
## stay closed for a short cooldown so the player does not re-enter by
## accident - #378 already drops them right in front of the gate. Run-scoped
## like cleared_dungeons (the death restart reloads Main). Only walking
## through the physical gate pauses; deliberate travel (#349 hub panel,
## #366 map) is unaffected.
var gate_reentry_cooldown_seconds := 60.0
var _gate_cooldown_until: Dictionary = {} # dungeon_id -> Time.get_ticks_msec() expiry

## #349 / #353 canonical clear API. No second record or node.
signal dungeon_cleared(dungeon_id: StringName)

func is_cleared(dungeon_id: StringName) -> bool:
	return cleared_dungeons.has(dungeon_id)

func cleared_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: StringName in cleared_dungeons:
		ids.append(id)
	return ids

func _load_hub() -> void:
	_entry_gate_type = -1
	_swap(preload("res://scenes/hub.tscn").instantiate())

## #346: go straight to the overworld (same swap a hub TRAVEL gate makes).
func enter_overworld() -> void:
	_swap((load(OVERWORLD_SCENE) as PackedScene).instantiate())

func _on_gate_entered(gate: Gate) -> void:
	print("gate entered: ", Gate.GateType.keys()[gate.gate_type], " -> ", gate.target_dungeon.resource_path if gate.target_dungeon else gate.target_path)
	_entry_gate_type = gate.gate_type
	var target := gate.target_scene()
	if target == null:
		push_warning("Gate %s has no target scene" % gate.name)
		return
	_swap.call_deferred(target.instantiate())

## #400: close the just-mounted area's gates to dungeons still inside their
## post-clear cooldown. Keyed by the gate's target scene like _dungeon_sites,
## so TRAVEL passages and unmapped targets are never touched.
func _apply_gate_cooldowns() -> void:
	var now := Time.get_ticks_msec()
	for g: Gate in get_tree().get_nodes_in_group("gates"):
		if not current_area.is_ancestor_of(g):
			continue
		var scene := g.target_scene()
		if scene == null:
			continue
		var id := FastTravelRoutes.id_for_scene(scene.resource_path)
		if id == &"":
			continue
		var until: int = _gate_cooldown_until.get(id, 0)
		if until > now:
			g.disable_for((until - now) / 1000.0)

## (#350) RED semantics for the mounted area: the entered gate's type when there
## is one; otherwise the authored default (DungeonB is the RED dungeon).
## #350: each gate's 50/50 offering type is rolled ONCE per run and stays
## fixed until death (Colin, 2026-11-08). Per-run reset comes free from the
## full scene reload on death restart, same as the other per-run records.
var _offering_rolls: Dictionary = {}

func offering_type_for(gate_name: StringName, authored: Gate.GateType, offering: GateOffering, rng: RandomNumberGenerator = null) -> Gate.GateType:
	if not _offering_rolls.has(gate_name):
		_offering_rolls[gate_name] = offering.roll(authored, rng)
	return _offering_rolls[gate_name]

func _area_is_red(area: Node) -> bool:
	if _entry_gate_type >= 0:
		return _entry_gate_type == Gate.GateType.RED
	return area.name == &"DungeonB"

func _swap(area: Node) -> void:
	if current_area:
		remove_child(current_area)
		current_area.queue_free()
	if boss_music:
		boss_music.stop_music() # #359: the boss theme never outlives its dungeon
	current_area = area
	add_child(current_area)
	for g: Gate in get_tree().get_nodes_in_group("gates"):
		if not g.entered.is_connected(_on_gate_entered):
			g.entered.connect(_on_gate_entered)
	_apply_gate_cooldowns()
	var p := get_node_or_null("Player") as Player
	var spawn := current_area.get_node_or_null("PlayerSpawn")
	if p and spawn:
		p.global_position = spawn.global_position
	if p:
		p.terrain = current_area.get_node_or_null("Terrain") as TerrainMap
	if _world_map:
		var sites := _dungeon_sites(current_area)
		if not sites.is_empty():
			_world_map.set_sites(current_area.name, sites) # #366
		_world_map.set_area(current_area.name, current_area.get_node_or_null("Terrain") as TerrainMap)
	_mount_area_spawns(current_area)
	_mount_entrance_guards(current_area)
	_mount_location_triggers(current_area)
	_mount_objective(current_area)
	_mount_exit_portal(current_area)
	_mount_revive_item(current_area)
	_mount_dungeon_modifiers(current_area)
	_refresh_fast_travel()

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

## #365: location-triggered events (foundation). Run-scoped fire history,
## keyed by LocationTrigger.id(); resets with the run reload like
## cleared_dungeons. Nothing reads it yet: repeat/reset rules are undesigned,
## and this is the record such a rule would consult.
var _location_event_fires: Dictionary = {}

## Emitted for every accepted trigger fire, before its event starts.
signal location_event_triggered(trigger_id: StringName, trigger: LocationTrigger)

func location_event_fire_count(trigger_id: StringName) -> int:
	return _location_event_fires.get(trigger_id, 0)

## #365: wire every LocationTrigger inside the mounted area. On a fire Main
## records it, emits location_event_triggered and starts the trigger's
## OverworldEvent with a fresh context. No production area places a trigger
## yet, so this is inert until content lands.
func _mount_location_triggers(area: Node) -> void:
	for t: LocationTrigger in get_tree().get_nodes_in_group("location_triggers"):
		if not area.is_ancestor_of(t):
			continue
		if not t.triggered.is_connected(_on_location_triggered):
			t.triggered.connect(_on_location_triggered.bind(area))

func _on_location_triggered(trigger: LocationTrigger, body: Node2D, area: Node) -> void:
	if area != current_area or not is_instance_valid(area):
		return
	var id := trigger.id()
	_location_event_fires[id] = location_event_fire_count(id) + 1
	location_event_triggered.emit(id, trigger)
	if trigger.event == null:
		return
	var ctx := OverworldEventContext.new()
	ctx.area = area
	ctx.trigger = trigger
	ctx.player = body as Player
	ctx.host = self
	ctx.run_fire_count = _location_event_fires[id]
	# Deferred: body_entered arrives during the physics flush, where adding
	# bodies (an ambush's enemies) is not allowed (D14).
	_start_location_event.call_deferred(trigger.event, ctx)

func _start_location_event(event: OverworldEvent, ctx: OverworldEventContext) -> void:
	if ctx.area != current_area or not is_instance_valid(ctx.area):
		return # the area was left in the same frame
	event.start(ctx)

## #346: overworld entrance guards. Every EntranceGuards node under the
## area's "EntranceGuards" container whose dungeon is still uncleared this
## run contributes its entries (#373: a mix of stationary gate guards and
## patrols), plus the area's "Roamers" migrants (AreaSpawnData, always
## mounted); all of them go through ONE EnemySpawner
## (#220 seam), parented to the area so leaving the overworld frees them.
func _mount_entrance_guards(area: Node) -> void:
	var holder := area.get_node_or_null("EntranceGuards")
	if holder == null:
		return
	var entries: Array = []
	var player_path := NodePath("../../Player")
	for g in holder.get_children():
		var guards := g as EntranceGuards
		if guards == null:
			continue
		if guards.dungeon_id != &"" and cleared_dungeons.has(guards.dungeon_id):
			continue
		entries.append_array(guards.entries)
		player_path = guards.player_path
	# #373: overworld-wide migrants belong to no entrance, so a cleared
	# dungeon (#348) never suppresses them; they mount through the same spawner.
	var roamers := area.get_node_or_null("Roamers") as AreaSpawnData
	if roamers != null:
		entries.append_array(roamers.entries)
		player_path = roamers.player_path
	if entries.is_empty():
		return
	var spawner := EnemySpawner.new()
	spawner.name = "GuardSpawner"
	area.add_child(spawner)
	spawner.setup(entries, player_path, area.get_node_or_null("Terrain") as TerrainMap, area)
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
## #326 (human request by Mitravasu, 2026-11-09: "create a new dungeon for
## it"): DungeonD is the Beast boss's den - a boss arena only like DungeonC,
## ELIMINATION with zero mobs, so the Beast (#174) spawns on entry.
const BEAST_BOSS_SCENE: PackedScene = preload("res://scenes/beast_boss.tscn")
const DUNGEON_D_BOSS_SPAWN: Vector2 = Vector2(576, 280)
## #337: DungeonE runs the DEFENSE objective with plain chase/contact mobs.
const DEFENSE_WAVE_ENEMY: PackedScene = preload("res://scenes/enemy.tscn")
const DEFENSE_WAVE_TABLE: RewardTable = preload("res://resources/rewards/demo_table.tres")

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
	elif area.name == "DungeonD":
		obj.dungeon_id = &"dungeon_d"
		obj.objective_type = DungeonObjective.ObjectiveType.ELIMINATION
		obj.boss_scene = BEAST_BOSS_SCENE
		obj.boss_spawn_position = (area as Node2D).to_global(DUNGEON_D_BOSS_SPAWN) if area is Node2D else DUNGEON_D_BOSS_SPAWN
		obj.boss_spawned.connect(_on_boss_spawned)
	elif area.name == "DungeonE" or area.name == "DungeonMaze":
		# #337: DEFENSE - protect the area's DefenseCore through a fixed number
		# of periodic waves spawned at its "WaveSpawns" markers. Wave/HP numbers
		# are the objective's tunable defaults (implementer's choice).
		# #367: DungeonMaze is the maze variant - its WaveSpawns are the maze
		# entrances and its FlowNav steers every wave enemy through the maze.
		# Same defaults otherwise, mixed targeting (core_attacker_share) included.
		obj.dungeon_id = &"dungeon_e" if area.name == "DungeonE" else &"dungeon_maze"
		obj.objective_type = DungeonObjective.ObjectiveType.DEFENSE
		obj.wave_nav = area.get_node_or_null("FlowNav") as FlowNav
		obj.wave_enemy_scene = DEFENSE_WAVE_ENEMY
		obj.wave_reward_table = DEFENSE_WAVE_TABLE
		var points: Array[Vector2] = []
		var holder := area.get_node_or_null("WaveSpawns")
		if holder != null:
			for m in holder.get_children():
				if m is Node2D:
					points.append((m as Node2D).position + (holder as Node2D).position)
		obj.wave_spawn_points = points
		obj.objective_failed.connect(_on_objective_failed)
	else:
		obj.free()
		return
	obj.objective_completed.connect(_on_objective_completed)
	area.add_child(obj)

## #337: a failed DEFENSE (core destroyed) never clears the dungeon, so a
## locked exit portal would soft-lock the run (#55 rule): open it to retreat.
func _on_objective_failed(dungeon_id: StringName) -> void:
	print("objective failed: ", dungeon_id)
	if current_area == null:
		return
	var portal := current_area.get_node_or_null("ExitPortal") as ExitPortal
	if portal != null:
		portal.unlock()

## Boss -> Main/<Area>/<Boss>, so the Player is "../../Player" (AreaSpawnData idiom).
func _on_boss_spawned(boss: Node) -> void:
	if boss is Enemy:
		boss.player_path = NodePath("../../Player")
	# #359: boss theme (random of the two tracks) for RED-entered dungeon bosses
	# and the boss arenas (Head, Beast). A NORMAL-rolled dungeon's boss is silent.
	if boss_music and current_area and _boss_theme_area(current_area):
		boss_music.start()

## #359: areas whose boss fight plays the boss theme.
const BOSS_THEME_ARENAS: Array[StringName] = [&"DungeonC", &"DungeonD"]

func _boss_theme_area(area: Node) -> bool:
	return _area_is_red(area) or area.name in BOSS_THEME_ARENAS

func _on_objective_completed(dungeon_id: StringName) -> void:
	print("objective completed: ", dungeon_id)
	var first_clear := not is_cleared(dungeon_id)
	cleared_dungeons[dungeon_id] = true # #346: its overworld entrance stops spawning guards
	_gate_cooldown_until[dungeon_id] = Time.get_ticks_msec() + int(gate_reentry_cooldown_seconds * 1000.0) # #400
	if first_clear:
		dungeon_cleared.emit(dungeon_id)
	_refresh_fast_travel.call_deferred()
	## (#132) Confirmed dungeon VICTORY only: free stock refresh and the
	## paid-refresh price resets (Daniel 2026-11-07). A plain return to hub
	## (exit portal without a clear) never reaches this path.
	if _shop != null:
		_shop.on_dungeon_victory()
	if boss_music:
		boss_music.fade_out() # #359: boss down, theme fades

## #9 production exit portal: normal-gate DungeonA mounts it UNLOCKED (retreat
## anytime, objective not required). Returns (#378: to the dungeon's overworld
## entrance; formerly the hub) in the SAME run via a
## deferred swap - the shared Player is repositioned, never recreated, so
## spells and current HP are retained. Red-gate DungeonB (#177 / O1, human
## decision 2026-11-08) now has an ELIMINATION objective, so it mounts the
## portal LOCKED per D12 (clear-or-die): it opens when the Warlord dies. The
## #55 unlocked mount only existed because DungeonB had no objective.
## An area with an "ExitPoint" marker gets an unlocked portal at that marker.
func _mount_exit_portal(area: Node) -> void:
	var exit_point := area.get_node_or_null("ExitPoint") as Node2D
	if exit_point == null and not area.name in [&"DungeonA", &"DungeonB", &"DungeonC", &"DungeonD", &"DungeonE"]:
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
	# #326: the Beast's den DungeonD is clear-or-die too (locked until the
	# Beast dies). #350: RED is whatever the entered gate rolled, so a
	# RED-rolled DungeonA locks and a NORMAL-rolled DungeonB allows retreat.
	var red := _area_is_red(area)
	if (red or area.name == &"DungeonC" or area.name == &"DungeonD") and completable:
		portal.locked = true
		portal.objective_path = NodePath("../DungeonObjective")
	portal.red_portal_look = red  # #204: portal look only on a RED dungeon's exit portal (both its locked and unlocked states)
	portal.entered.connect(_on_exit_portal_entered)
	area.add_child(portal)

func _on_exit_portal_entered(_portal: ExitPortal) -> void:
	_exit_dungeon.call_deferred(current_area.scene_file_path if current_area else "")

## #378: leaving a dungeon by its exit portal returns the player to that
## dungeon's entrance in the overworld, standing just in front of (below) the
## entrance gate so they do not walk straight back in. A dungeon without an
## overworld entrance (test fixtures, direct swaps) falls back to the hub.
## The #349 fast-return shortcut is a separate path and still goes to the hub.
const ENTRANCE_EXIT_OFFSET := Vector2(0, 80)

func _exit_dungeon(dungeon_scene: String) -> void:
	var overworld := (load(OVERWORLD_SCENE) as PackedScene).instantiate()
	var entrance := _entrance_gate_for(overworld, dungeon_scene)
	if entrance == null:
		overworld.free()
		_load_hub()
		return
	_entry_gate_type = -1
	_swap(overworld)
	var p := get_node_or_null("Player") as Player
	if p:
		p.global_position = entrance.global_position + ENTRANCE_EXIT_OFFSET

## #378: the overworld gate whose target is `dungeon_scene` (scene path), or null.
## Walks the not-yet-mounted overworld so no swap happens when there is none.
func _entrance_gate_for(area: Node, dungeon_scene: String) -> Gate:
	if dungeon_scene == "":
		return null
	for n in area.find_children("*", "", true, false):
		var g := n as Gate
		if g == null:
			continue
		var scene := g.target_scene()
		if scene != null and scene.resource_path == dungeon_scene:
			return g
	return null

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


## #349 travel wiring. Uses the ONE canonical dictionary above. Mount kept
## separate from the map block so exploration-map work remains independent.
var _fast_travel: FastTravelPanel

func _mount_fast_travel() -> void:
	_fast_travel = FastTravelPanel.new()
	_fast_travel.name = "FastTravelPanel"
	add_child(_fast_travel)
	_fast_travel.destination_requested.connect(_request_fast_travel)
	_fast_travel.hub_requested.connect(_request_fast_return)

func _refresh_fast_travel() -> void:
	if not is_instance_valid(_fast_travel) or current_area == null:
		return
	_fast_travel.close()
	var choices: Array[StringName] = []
	if _is_hub_area():
		choices = cleared_ids()
	_fast_travel.set_choices(choices, not _is_hub_area() and can_fast_return())

func _is_hub_area() -> bool:
	return current_area != null and current_area.scene_file_path == FastTravelRoutes.HUB_SCENE

## Only the production Hub is currently proven incapable of enemy spawn.
## Empty overworld/dungeon groups are NOT sufficient: their spawn carriers,
## objectives and scripted generators remain capabilities after enemies die.
## New safe-area types must establish their own no-spawn contract first.
func _is_proven_safe_area() -> bool:
	if not _is_hub_area():
		return false
	var enemies := not get_tree().get_nodes_in_group("enemies").is_empty()
	var spawn_capable := current_area.get_node_or_null("SpawnData") != null or current_area.get_node_or_null("EntranceGuards") != null or current_area.get_node_or_null("Roamers") != null or current_area.get_node_or_null("DungeonObjective") != null
	return FastTravelRoutes.is_safe_area(enemies, spawn_capable)

func can_fast_return() -> bool:
	if current_area == null:
		return false
	if _is_proven_safe_area():
		return true
	var objective := current_area.get_node_or_null("DungeonObjective") as DungeonObjective
	## #349 owner choice: once cleared this run, re-entry may return to hub
	## immediately, without completing the fresh interior objective again.
	## Existing exit-portal locks are unchanged; this is the explicit shortcut.
	return objective != null and is_cleared(objective.dungeon_id)

func _request_fast_travel(dungeon_id: StringName) -> void:
	_commit_fast_travel.call_deferred(dungeon_id)

func _commit_fast_travel(dungeon_id: StringName) -> void:
	var path := FastTravelRoutes.scene_from_hub(_is_hub_area(), dungeon_id, cleared_ids())
	var player := get_node_or_null("Player") as Player
	if path == "" or player == null or player.hp <= 0:
		return
	_enter_dungeon(dungeon_id, path)

## Shared by the #349 Hub shortcut and #366 map travel: mount `path` with the
## run's gate offering / authored boss semantics for `dungeon_id`.
func _enter_dungeon(dungeon_id: StringName, path: String) -> void:
	var target := load(path) as PackedScene
	if target == null:
		return
	## Reuse the current run's gate offering and authored boss semantics.
	var authored := Gate.GateType.RED if dungeon_id == &"dungeon_b" else Gate.GateType.NORMAL
	var gate_name: StringName = &"GateRed" if dungeon_id == &"dungeon_b" else &"GateNormal"
	if dungeon_id in [&"dungeon_a", &"dungeon_b"]:
		_entry_gate_type = offering_type_for(gate_name, authored, preload("res://resources/gate_offering.tres"))
	elif dungeon_id == &"dungeon_e" or dungeon_id == &"dungeon_maze":
		_entry_gate_type = Gate.GateType.NORMAL # Preserve authored defense gate; no offering roll.
	else:
		_entry_gate_type = Gate.GateType.BOSS
	_swap(target.instantiate())

func _request_fast_return() -> void:
	_commit_fast_return.call_deferred()

func _commit_fast_return() -> void:
	var player := get_node_or_null("Player") as Player
	if player == null or player.hp <= 0 or not can_fast_return() or _is_hub_area():
		return
	_load_hub()

## #366 map travel. The map marks every dungeon cleared this run at its
## entrance (sites read from the area's gates); selecting one there offers
## fast travel to it.
##
## Route policy is the #349 Hub-spoke policy, unchanged: map travel is a
## second way to pick the same Hub -> cleared-dungeon trip, so the trip is
## only committed from the Hub (FastTravelRoutes.scene_from_hub). No new
## origins: no escape from a guarded/spawn-capable overworld and no direct
## dungeon -> dungeon hop. The way back stays the existing #349 return-to-Hub
## path (FastTravelPanel / can_fast_return), untouched here.
## Implementer defaults (issue left open): marks show even under map fog
## (clearing implies discovery); run-scoped like cleared_dungeons/WorldMap.
func _dungeon_sites(area: Node) -> Dictionary:
	var sites := {}
	for g: Gate in get_tree().get_nodes_in_group("gates"):
		if not area.is_ancestor_of(g):
			continue
		var scene := g.target_scene()
		if scene == null:
			continue
		var id := FastTravelRoutes.id_for_scene(scene.resource_path)
		if id != &"":
			sites[id] = g.global_position
	return sites

## Asked by the map at click time and rechecked at commit. Same policy as the
## #349 Hub panel: origin must be the Hub, target must be cleared this run.
func can_map_travel_to(dungeon_id: StringName) -> bool:
	if current_area == null:
		return false
	var player := get_node_or_null("Player") as Player
	if player == null or player.hp <= 0:
		return false
	return FastTravelRoutes.scene_from_hub(_is_hub_area(), dungeon_id, cleared_ids()) != ""

func _request_map_travel(dungeon_id: StringName) -> void:
	_commit_map_travel.call_deferred(dungeon_id)

## Commits through the #349 Hub commit (it rechecks scene_from_hub against the
## live clear record), so both entry points share one route policy.
func _commit_map_travel(dungeon_id: StringName) -> void:
	if not can_map_travel_to(dungeon_id): # recheck at commit, never trust the UI
		return
	_commit_fast_travel(dungeon_id)
