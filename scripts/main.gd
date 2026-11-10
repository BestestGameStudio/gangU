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
## #512: Main keeps service boot and the persistent run children. Area
## loading/mounting lives in AreaLoader, fast/map travel in TravelService,
## and all music in MusicDirector (one each, wired below).

func _ready() -> void:
	print("gangU booted OK")
	var grid := BackgroundGrid.new()
	grid.name = "BackgroundGrid"
	add_child(grid)
	move_child(grid, 0)
	# #448: the day/night clock is parked on the tree root (not under Main or
	# any area) so it keeps running through area swaps and scene reloads.
	DayNightClock.ensure(get_tree())
	var rm := RunManager.new()
	rm.name = "RunManager"
	rm.player = $Player
	add_child(rm)
	var hud: HUD = preload("res://scenes/hud.tscn").instantiate()
	hud.player_path = NodePath("../Player") # explicit, read in HUD._ready on tree entry
	add_child(hud)
	## #512: ONE MusicDirector for the whole run (boss theme, dungeon loop,
	## overworld piano; merged from the three separate players). Freed with
	## Main on a death restart, so no music leaks into the reloaded run.
	music = MusicDirector.new()
	music.name = "MusicDirector"
	add_child(music)
	## #512: area loading/mounting and fast/map travel live in their own
	## services; Main keeps service boot and wires the seams between them.
	area_loader = AreaLoader.new()
	area_loader.name = "AreaLoader"
	area_loader.main_host = self
	area_loader.player = $Player
	area_loader.music = music
	add_child(area_loader)
	travel = TravelService.new()
	travel.name = "TravelService"
	travel.area_loader = area_loader
	travel.player = $Player
	add_child(travel)
	area_loader.travel = travel
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
	satchel.revive_collected.connect(area_loader._on_revive_collected)
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
	area_loader.shop = shop
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
	progress.upgrades = UpgradeCatalog.all()
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
	world_map.cleared_rule = area_loader.is_cleared # #366: cleared dungeons are marked
	add_child(world_map)
	_world_map = world_map
	area_loader.world_map = world_map
	var map_panel := MapPanel.new()
	map_panel.name = "MapPanel"
	map_panel.world_map_path = NodePath("../WorldMap")
	map_panel.travel_rule = travel.can_map_travel_to # #366
	add_child(map_panel)
	map_panel.travel_requested.connect(travel._request_map_travel)
	travel.mount() # #349: separate mount after map setup
	var settings := SettingsPanel.new() # #489: Esc settings (master volume)
	settings.name = "SettingsPanel"
	add_child(settings)
	area_loader._load_hub()

## #512: the run's services, created in _ready. Public so harnesses (and the
## map/world-map wiring above) can reach the moved APIs without forwarders.
var music: MusicDirector = null
var area_loader: AreaLoader = null
var travel: TravelService = null

## (#132) The mounted hub shop, kept so AreaLoader can trigger its FREE stock
## refresh + paid-price reset on a confirmed dungeon victory.
var _shop: Shop = null
## (#347) The run's map record; AreaLoader is told about every area swap.
var _world_map: WorldMap = null
