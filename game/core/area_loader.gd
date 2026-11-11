class_name AreaLoader
extends Node
## Run-owned area mounting, physical region integration and canonical clear
## adapter. Hub travel retains the overworld; full death rebuilds it. Music
## policy lives in MusicDirector and hub-spoke travel in TravelService.

## Main, which parents the mounted areas (they stay Main/<Area> children so
## every relative NodePath is unchanged); assigned by Main before _load_hub().
var main_host: Node = null
## The shared run Player (Main/Player); assigned by Main.
var player: Player = null
## (#132) The mounted hub shop, kept so a dungeon victory can trigger its
## FREE stock refresh + paid-price reset from complete_encounter.
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

const OVERWORLD_SCENE := "res://game/world/overworld.tscn"

## One run-owned clear record. Hub trips retain it; death frees the loader.
var encounter_state: EncounterState
signal dungeon_cleared(dungeon_id: StringName)
func _ready() -> void:
	encounter_state = EncounterState.new()
	encounter_state.name = "EncounterState"
	add_child(encounter_state)

func is_cleared(id: StringName) -> bool:
	return encounter_state != null and encounter_state.is_cleared(id)

func cleared_ids() -> Array[StringName]:
	return encounter_state.cleared_ids() if encounter_state != null else []

func complete_encounter(id: StringName) -> bool:
	if encounter_state == null or not encounter_state.complete(id):
		return false
	dungeon_cleared.emit(id)
	if shop != null:
		shop.on_dungeon_victory()
	if travel != null:
		travel.refresh.call_deferred()
	# Approach guards are a clear-state consumer, not encounter targets.
	# Cached hub travel must not resurrect or retain obsolete clear guards.
	var region := region_for(id)
	if region != null:
		var spawner := region.layout.get_node_or_null("ApproachSpawner") as EnemySpawner
		if spawner != null:
			for group in spawner._alive.values():
				for enemy in group:
					if is_instance_valid(enemy): enemy.queue_free()
	return true

func _load_hub() -> void:
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
	var target := gate.target_scene()
	if target == null:
		push_warning("Gate %s has no target scene" % gate.name)
		return
	if target.resource_path == OVERWORLD_SCENE:
		enter_overworld.call_deferred()
	else:
		_swap.call_deferred(target.instantiate())

func _swap(area: Node) -> void:
	if current_area == area:
		return
	if current_area:
		if current_area == _run_overworld:
			# Keep nodes in-tree: removing an active encounter from the tree
			# would abort it. Hub travel is refused while an encounter runs.
			_set_overworld_collisions(false)
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
		if guards.dungeon_id != &"" and is_cleared(guards.dungeon_id):
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
