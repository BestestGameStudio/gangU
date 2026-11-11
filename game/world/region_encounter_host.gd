class_name RegionEncounterHost
extends Node
## Run-local integration, not another objective system. Counts only this
## region's initial mob spawns and their descendants; no global enemy scan.
var region: OverworldRegion
var loader: AreaLoader
var definition: DungeonDefinition
var trigger: LocationTrigger
var defense: DefenseEncounter
var lair: BossLair
var doors: Array[EncounterBarrier] = []
var _alive: Array[Enemy] = []
var _active := false
var _started := false
var _finished := false
var _boss_spawned := false

func mount(p_region: OverworldRegion, p_loader: AreaLoader) -> void:
	region = p_region
	loader = p_loader
	definition = DungeonCatalog.for_area(region.layout)
	if definition == null:
		return # generated exploration has no invented clear condition
	var spawner := region.layout.get_node_or_null('EnemySpawner') as EnemySpawner
	if spawner != null:
		for enemy in region.layout.get_children():
			if enemy is Enemy: _watch(enemy)
	trigger = LocationTrigger.new()
	trigger.name = 'EncounterEntry'
	trigger.trigger_id = region.encounter_id
	trigger.position = region.layout.to_local(region.arrival)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(144,144)
	shape.shape = rect
	trigger.add_child(shape)
	region.layout.add_child(trigger)
	trigger.triggered.connect(_on_triggered)
	if definition.boss_scene != null or definition.wave_enemy_scene != null:
		_mount_doors()
	if definition.wave_enemy_scene != null:
		_mount_defense()
	elif definition.boss_scene != null:
		_mount_lair()
	loader.player.died.connect(_on_player_died)

func is_active() -> bool:
	return _active or (defense != null and defense.is_active()) or (lair != null and lair.is_active())

func _mount_doors() -> void:
	var points: Array[Vector2] = [region.entry]
	if region.layout is MazeDefenseDungeon:
		for point: Vector2 in (region.layout as MazeDefenseDungeon).maze['entrances']:
			var world := region.layout.to_global(point)
			if world.distance_to(region.entry) > 32.0: points.append(world)
	for i in points.size():
		var door: EncounterBarrier = preload('res://game/world/encounter_barrier.tscn').instantiate()
		door.name = 'EncounterDoor%d' % i
		door.position = region.layout.to_local(points[i])
		door.size = Vector2(192,32)
		if i > 0:
			var local := door.position
			var map := region.layout.get_node('Terrain') as TerrainMap
			var size: Vector2i = (region.layout as MazeDefenseDungeon).maze['size']
			if local.x < 128 or local.x > (size.x-2)*map.cell_size: door.size = Vector2(32,192)
		region.layout.add_child(door)
		doors.append(door)

func _door_paths(from: Node) -> Array[NodePath]:
	var paths: Array[NodePath] = []
	for door in doors: paths.append(from.get_path_to(door))
	return paths

func _mount_defense() -> void:
	defense = DefenseEncounter.new()
	defense.name = 'DefenseEncounter'
	defense.encounter_id = region.encounter_id
	defense.defense_core = region.layout.get_node('DefenseCore') as DefenseCore
	defense.wave_terrain = region.terrain
	defense.wave_nav = region.layout.get_node_or_null('FlowNav') as FlowNav
	defense.wave_enemy_scene = definition.wave_enemy_scene
	defense.wave_reward_table = definition.wave_reward_table
	defense.wave_boss_scene = definition.wave_boss_scene
	defense.boss_waves = [defense.wave_count]
	defense.wave_player_path = NodePath('../' + String(region.layout.get_path_to(loader.player)))
	var holder := region.layout.get_node('WaveSpawns')
	for marker in holder.get_children():
		if marker is Node2D: defense.wave_spawn_points.append((marker as Node2D).position + (holder as Node2D).position)
	# Assign paths relative to the eventual sibling-mounted controller.
	for door in doors: defense.barriers.append(NodePath('../'+String(door.name)))
	defense.encounter_finished.connect(_on_finished)
	defense.boss_spawned.connect(_on_boss_spawned)
	region.layout.add_child(defense)

func _mount_lair() -> void:
	lair = BossLair.new()
	lair.name = 'BossLair'
	lair.encounter_id = region.encounter_id
	lair.trigger = NodePath('../EncounterEntry')
	for door in doors: lair.barriers.append(NodePath('../'+String(door.name)))
	lair.encounter_finished.connect(_on_finished)
	lair.boss_spawned.connect(_on_boss_spawned)
	region.layout.add_child(lair)

func _on_triggered(_trigger: LocationTrigger, body: Node2D) -> void:
	_begin.call_deferred(body as Player)

func _begin(player: Player) -> void:
	if _started or _finished or player == null or player.hp <= 0:
		return
	_started = true
	trigger.disarm()
	if loader.is_cleared(region.encounter_id):
		return # same run clear never creates a fresh encounter
	if defense != null:
		_active = defense.start(player)
	else:
		_active = true
		if lair != null:
			for door in doors: door.lock()
			if _alive.is_empty(): _spawn_boss()
		elif _alive.is_empty():
			_finish(false) # no phantom clear for an invalid/empty carrier
	if _active and loader.music != null:
		loader.music.start_dungeon()

func _watch(enemy: Enemy) -> void:
	if enemy == null or _alive.has(enemy): return
	_alive.append(enemy)
	enemy.died.connect(_on_mob_died.bind(enemy))
	if enemy is EnemySlime:
		(enemy as EnemySlime).children_spawned.connect(_on_children_spawned)

func _on_children_spawned(kids: Array) -> void:
	for kid in kids:
		if kid is Enemy: _watch(kid)

func _on_mob_died(enemy: Enemy) -> void:
	_alive.erase(enemy)
	if not _alive.is_empty() or _finished: return
	if lair != null:
		if _active: _spawn_boss.call_deferred()
	elif defense == null:
		_finish(true)

func _spawn_boss() -> void:
	if not _active or _finished or lair == null or _boss_spawned: return
	_boss_spawned = true
	var opts := EnemySpawner.SpawnOptions.new()
	opts.wire_enemy = true
	opts.player_path = NodePath('../' + String(region.layout.get_path_to(loader.player)))
	opts.terrain = region.terrain
	var boss := EnemySpawner.spawn(definition.boss_scene, definition.boss_spawn, opts) as Enemy
	if boss == null:
		_finish(false)
		return
	region.layout.add_child(boss)
	lair.register_boss(boss)
	lair.start(loader.player)

func _on_boss_spawned(_boss: Node) -> void:
	if loader.music != null:
		loader.music.on_boss_spawned(definition.red_by_default or definition.boss_theme)

func _on_finished(_id: StringName, cleared: bool) -> void:
	_finish(cleared)

func _finish(cleared: bool) -> void:
	if _finished: return
	_finished = true
	_active = false
	for door in doors: door.unlock()
	if cleared: loader._on_objective_completed(region.encounter_id)
	if loader.music != null:
		loader.music.on_objective_completed()
		loader.music.stop_dungeon()

func _on_player_died() -> void:
	_resolve_death.call_deferred()
func _resolve_death() -> void:
	if _active and is_instance_valid(loader.player) and loader.player.hp <= 0:
		_finish(false)
