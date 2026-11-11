class_name AreaLoader
extends Node
## #512: area loading and mounting, split out of main.gd. Owns the current
## area, the swap and every per-area mount (spawns, entrance guards, location
## triggers, objective, exit portal, revive item, dungeon modifiers), the
## run's gate/clear records (cleared dungeons, gate cooldowns, offering
## rolls) and the gate / objective / portal / location-trigger handlers.
## Music policy lives in MusicDirector; fast/map travel in TravelService.

## Main, which parents the mounted areas (they stay Main/<Area> children so
## every relative NodePath is unchanged); assigned by Main before _load_hub().
var main_host: Node = null
## The shared run Player (Main/Player); assigned by Main.
var player: Player = null
## (#132) The mounted hub shop, kept so a dungeon victory can trigger its
## FREE stock refresh + paid-price reset from _on_objective_completed.
var shop: Shop = null
## (#347) The run's map record; told about every area swap.
var world_map: WorldMap = null
## #512: the run's MusicDirector; area swaps, boss spawns and objective
## completions drive it.
var music: MusicDirector = null
## #512: the run's TravelService; refreshed after swaps and clears.
var travel: TravelService = null

var current_area: Node = null
var _run_overworld: Node2D
var regions: Array[OverworldRegion] = []
var _parked_collisions: Dictionary = {}
var activation: RegionActivation

func region_for(id: StringName) -> OverworldRegion:
	for region in regions:
		if region.encounter_id == id:
			return region
	return null

func region_at(world: Vector2) -> OverworldRegion:
	for region in regions:
		if region.contains(world):
			return region
	return null

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
const OVERWORLD_SCENE := "res://game/world/overworld.tscn"

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
	_swap(preload("res://game/world/hub.tscn").instantiate())

## #346: go straight to the overworld (same swap a hub TRAVEL gate makes).
func enter_overworld() -> void:
	if is_instance_valid(_run_overworld):
		_swap(_run_overworld)
	else:
		_swap((load(OVERWORLD_SCENE) as PackedScene).instantiate())

func _on_gate_entered(gate: Gate) -> void:
	if gate.target_path == FastTravelRoutes.HUB_SCENE and has_active_encounter():
		return
	print("gate entered: ", Gate.GateType.keys()[gate.gate_type], " -> ", gate.target_dungeon.resource_path if gate.target_dungeon else gate.target_path)
	_entry_gate_type = gate.gate_type
	var target := gate.target_scene()
	if target == null:
		push_warning("Gate %s has no target scene" % gate.name)
		return
	if target.resource_path == OVERWORLD_SCENE:
		enter_overworld.call_deferred()
	else:
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
	var def := DungeonCatalog.for_area(area)
	return def != null and def.red_by_default

func _swap(area: Node) -> void:
	if current_area == area:
		return
	if current_area:
		if current_area == _run_overworld:
			# Keep nodes in-tree: removing an active encounter from the tree
			# would abort it. Hub travel is refused while an encounter runs.
			_set_overworld_collisions(false)
			_set_overworld_layers(false)
			_run_overworld.hide()
			_run_overworld.process_mode = Node.PROCESS_MODE_DISABLED
		else:
			main_host.remove_child(current_area)
			current_area.queue_free()
	current_area = area
	var first_mount := current_area.get_parent() == null
	if first_mount:
		main_host.add_child(current_area)
	if current_area.scene_file_path == OVERWORLD_SCENE:
		_run_overworld = current_area as Node2D
		_set_overworld_collisions(true)
		_set_overworld_layers(true)
		_run_overworld.show()
		_run_overworld.process_mode = Node.PROCESS_MODE_INHERIT
	if music:
		# #359: the boss theme never outlives its dungeon; #471: a fresh loop
		# on every dungeon entry, silence in the hub/overworld; #487: the
		# overworld piano only while the overworld is mounted.
		music.on_area_swapped(current_area)
	for g: Gate in get_tree().get_nodes_in_group("gates"):
		if not g.entered.is_connected(_on_gate_entered):
			g.entered.connect(_on_gate_entered)
	_apply_gate_cooldowns()
	var p := player
	var spawn := current_area.get_node_or_null("PlayerSpawn")
	if p and spawn:
		p.global_position = (spawn as Node2D).global_position
	if p:
		p.terrain = current_area.get_node_or_null("Terrain") as TerrainMap
	if world_map:
		var sites := _dungeon_sites(current_area)
		if not sites.is_empty():
			world_map.set_sites(current_area.name, sites) # #366
		world_map.set_area(current_area.name, current_area.get_node_or_null("Terrain") as TerrainMap)
	if first_mount:
		_mount_area_spawns(current_area)
		if current_area.scene_file_path == OVERWORLD_SCENE:
			_mount_regions(current_area)
		_mount_entrance_guards(current_area)
		_mount_location_triggers(current_area)
		_mount_objective(current_area)
		_mount_exit_portal(current_area)
		_mount_revive_item(current_area)
		_mount_dungeon_modifiers(current_area)
	if current_area == _run_overworld and activation != null:
		activation.update_now()
	if travel:
		travel.refresh()

## (#222) Dungeon modifiers: an area opts in with ONE "DungeonModifiers"
## child (DungeonModifierHost, SpawnData idiom). Bound LAST so the
## dungeon_entered event sees spawns, objective and portal in place. No
## production area carries one yet (content is human-open), so this is inert.
func _mount_dungeon_modifiers(area: Node) -> void:
	var host := area.get_node_or_null("DungeonModifiers") as DungeonModifierHost
	if host == null:
		return
	host.bind(area, main_host.get_node_or_null("Player/SpellCaster") as SpellCaster, main_host.get_node_or_null("RunManager") as RunManager)

## #100 generic mounter: every area swap reads the area's "SpawnData" child
## (AreaSpawnData). Entries are SpawnEntry scene data - position, enemy scene
## and reward table per spawn. The carrier's player_path is assigned BEFORE
## add_child so Enemy._ready resolves it (D6 explicit wiring).
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
	var entries: Array[SpawnEntry] = []
	var player_path := NodePath("../../Player")
	for g in holder.get_children():
		var guards := g as EntranceGuards
		if guards == null:
			continue
		if guards.dungeon_id != &"" and cleared_dungeons.has(guards.dungeon_id):
			continue
		var id := guards.dungeon_id if guards.dungeon_id != &"" else &"generated"
		var region := region_for(id)
		if region != null:
			var local_entries: Array[SpawnEntry] = []
			var delta := Vector2.ZERO
			for entry in guards.entries:
				var copy := entry.duplicate() as SpawnEntry
				copy.position = region.layout.to_local((area as Node2D).to_global(entry.position + delta))
				copy.route = PackedVector2Array()
				for at in entry.route:
					copy.route.append(region.layout.to_local((area as Node2D).to_global(at + delta)))
				local_entries.append(copy)
			var local_spawner := EnemySpawner.new()
			local_spawner.name = "ApproachSpawner"
			region.layout.add_child(local_spawner)
			local_spawner.setup(local_entries, NodePath("../" + String(region.layout.get_path_to(player))), region.terrain, region.layout)
			local_spawner.spawn_initial()
			region.set_active(region.active)
		else:
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
## The boss enters the tree deferred, so its player_path (D6 explicit wiring)
## is assigned in boss_spawned, before tree entry.
## (#512: the boss and spawn point now live in data/dungeons/dungeon_b.tres;
## this constant stays for tests that spawn the Warlord directly.)
const WARLORD_SCENE: PackedScene = preload("res://game/enemies/bosses/mustache_warlord.tscn")
## #173 (human decision 2026-11-08): boss-gate DungeonC is a boss arena only -
## ELIMINATION with zero mobs, so the Head boss spawns on entry.
## #326 (human request by Mitravasu, 2026-11-09: "create a new dungeon for
## it"): DungeonD is the Beast boss's den - a boss arena only like DungeonC,
## ELIMINATION with zero mobs, so the Beast (#174) spawns on entry.
## #337: DungeonE runs the DEFENSE objective with plain chase/contact mobs.
const DEFENSE_WAVE_TABLE: RewardTable = preload("res://data/rewards/demo_table.tres")
## #368: boss of a defense boss wave.

func _mount_objective(area: Node) -> void:
	# #512: the area's DungeonDefinition (data/dungeons/) decides the objective.
	var def := DungeonCatalog.for_area(area)
	if def == null:
		return
	var obj := DungeonObjective.new()
	obj.name = "DungeonObjective"
	obj.dungeon_id = def.id
	obj.objective_type = def.objective_type
	if def.boss_scene != null:
		obj.boss_scene = def.boss_scene
		obj.boss_spawn_position = (area as Node2D).to_global(def.boss_spawn) if area is Node2D else def.boss_spawn
		obj.boss_spawned.connect(_on_boss_spawned)
	if def.objective_type == DungeonObjective.ObjectiveType.DEFENSE:
		# #337: DEFENSE - protect the area's DefenseCore through a fixed number
		# of periodic waves spawned at its "WaveSpawns" markers. Wave/HP numbers
		# are the objective's tunable defaults (implementer's choice).
		# #367: DungeonMaze is the maze variant - its WaveSpawns are the maze
		# entrances and its FlowNav steers every wave enemy through the maze.
		# Same defaults otherwise, mixed targeting (core_attacker_share) included.
		obj.wave_nav = area.get_node_or_null("FlowNav") as FlowNav
		obj.wave_enemy_scene = def.wave_enemy_scene
		obj.wave_reward_table = def.wave_reward_table
		# #368: the final wave is a boss wave - its usual enemies plus one
		# Siege Brute that marches on the core (implementer defaults; boss
		# count, placement and balance are open).
		obj.wave_boss_scene = def.wave_boss_scene
		var boss_waves: Array[int] = [obj.wave_count]
		obj.boss_waves = boss_waves
		var points: Array[Vector2] = []
		var holder := area.get_node_or_null("WaveSpawns")
		if holder != null:
			for m in holder.get_children():
				if m is Node2D:
					points.append((m as Node2D).position + (holder as Node2D).position)
		obj.wave_spawn_points = points
		obj.objective_failed.connect(_on_objective_failed)
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
		(boss as Enemy).player_path = NodePath("../../Player")
	# #359: boss theme (random of the two tracks) for RED-entered dungeon bosses
	# and the boss arenas (Head, Beast). A NORMAL-rolled dungeon's boss is silent.
	if music and current_area:
		music.on_boss_spawned(_boss_theme_area(current_area)) # #471: the dungeon loop yields to the theme

## #359: areas whose boss fight plays the boss theme.
func _boss_theme_area(area: Node) -> bool:
	var def := DungeonCatalog.for_area(area)
	return _area_is_red(area) or (def != null and def.boss_theme)

func _on_objective_completed(dungeon_id: StringName) -> void:
	print("objective completed: ", dungeon_id)
	var first_clear := not is_cleared(dungeon_id)
	cleared_dungeons[dungeon_id] = true # #346: its overworld entrance stops spawning guards
	_gate_cooldown_until[dungeon_id] = Time.get_ticks_msec() + int(gate_reentry_cooldown_seconds * 1000.0) # #400
	if first_clear:
		dungeon_cleared.emit(dungeon_id)
	if travel:
		travel.refresh.call_deferred()
	## (#132) Confirmed dungeon VICTORY only: free stock refresh and the
	## paid-refresh price resets (Daniel 2026-11-07). A plain return to hub
	## (exit portal without a clear) never reaches this path.
	if shop != null:
		shop.on_dungeon_victory()
	if music:
		# #359: boss down, the theme fades; #471: the dungeon loop fades back in.
		music.on_objective_completed()

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
	var def := DungeonCatalog.for_area(area)
	if exit_point == null and not (def != null and def.default_exit_portal):
		return
	var portal: ExitPortal = preload("res://game/world/exit_portal.tscn").instantiate()
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
	if (red or (def != null and def.locks_portal)) and completable:
		portal.locked = true
		portal.objective_path = NodePath("../DungeonObjective")
	portal.red_portal_look = red  # #204: portal look only on a RED dungeon's exit portal (both its locked and unlocked states)
	portal.beast_portal_look = def != null and def.beast_portal_look  # #447: the Beast den's exit portal gets the portal look in purple
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
	var p := player
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
	var def := DungeonCatalog.for_area(area)
	if def == null or not def.revive_item or _revive_claimed:
		return
	var item: ReviveItem = preload("res://game/player/revive_item.tscn").instantiate()
	item.name = "ReviveItem"
	item.position = Vector2(900, 480)
	area.add_child(item)


## Shared by the #349 Hub shortcut and #366 map travel: mount `path` with the
## run's gate offering / authored boss semantics for `dungeon_id`.
func _enter_dungeon(dungeon_id: StringName, path: String) -> void:
	if path == "" or not FastTravelRoutes.DUNGEONS.has(dungeon_id):
		return
	enter_overworld()
	var region := region_for(dungeon_id)
	if region != null and player != null:
		player.global_position = region.arrival
		activation.update_now()



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
	for region in regions:
		if area.is_ancestor_of(region) and FastTravelRoutes.DUNGEONS.has(region.encounter_id):
			sites[region.encounter_id] = region.entry
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

## Folded region lifetime equals the run. All initial enemy carriers go
## through EnemySpawner, exactly once, with explicit persistent Player paths.
func _mount_regions(area: Node) -> void:
	var shared := area.get_node("Terrain") as TerrainMap
	for child in area.get_children():
		var region := child as OverworldRegion
		if region == null:
			continue
		region.mount(shared)
		regions.append(region)
		var data := region.layout.get_node_or_null("SpawnData") as AreaSpawnData
		if data != null:
			var spawner := EnemySpawner.new()
			spawner.name = "EnemySpawner"
			region.layout.add_child(spawner)
			var path := NodePath("../" + String(region.layout.get_path_to(player)))
			spawner.setup(data.entries, path, shared, region.layout)
			spawner.spawn_initial()
		_mount_revive_item(region.layout)
		var host := RegionEncounterHost.new()
		host.name = "RegionEncounterHost"
		region.layout.add_child(host)
		host.mount(region, self)
		region.set_active(false)
	var ground := area.get_node_or_null("Ground") as OverworldGround
	if ground != null:
		ground.reserve_regions(regions)
	activation = RegionActivation.new()
	activation.name = "RegionActivation"
	activation.player = player
	activation.regions = regions
	area.add_child(activation)
	if world_map:
		world_map.set_sites(area.name, _dungeon_sites(area))

func has_active_encounter() -> bool:
	for region in regions:
		if region.keep_active():
			return true
	return false

func _set_overworld_collisions(enabled: bool) -> void:
	if not is_instance_valid(_run_overworld):
		return
	for n in _run_overworld.find_children("*", "CollisionObject2D", true, false):
		var body := n as CollisionObject2D
		if not enabled:
			_parked_collisions[body.get_instance_id()] = [body.collision_layer, body.collision_mask]
			body.collision_layer = 0
			body.collision_mask = 0
		elif _parked_collisions.has(body.get_instance_id()):
			var state: Array = _parked_collisions[body.get_instance_id()]
			body.collision_layer = state[0]
			body.collision_mask = state[1]
	if enabled:
		_parked_collisions.clear()

## CanvasLayers do not inherit Node2D visibility. Park screen-space area
## titles too, without touching the shared player HUD.
func _set_overworld_layers(enabled: bool) -> void:
	if not is_instance_valid(_run_overworld):
		return
	for node in _run_overworld.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = enabled
