class_name OverworldRegion
extends Node2D
## One mounted region, retained for the run. The host supplies the shared
## collision/navigation terrain and a legacy layout as data, not a transport.
@export var encounter_id: StringName
@export var layout_scene: PackedScene
@export var approach: Vector2
@export var door_direction := Vector2.DOWN
var layout: Node2D
var terrain: TerrainMap
var bounds := Rect2()
var active := true
var arrival := Vector2.ZERO
var entry := Vector2.ZERO
var _collision_state: Dictionary = {}
var _source: TerrainMap
var _syncing_terrain := false

func mount(shared: TerrainMap) -> void:
	terrain = shared
	if layout != null or layout_scene == null:
		return
	layout = layout_scene.instantiate() as Node2D
	# Layout generation uses local terrain before it is stamped into shared.
	add_child(layout)
	for child in layout.get_children():
		if child is CanvasLayer:
			child.queue_free() # old full-screen dungeon titles cannot stack
	var source := layout.get_node_or_null("Terrain") as TerrainMap
	var spawn := layout.get_node_or_null("PlayerSpawn") as Node2D
	var entry_local := spawn.position if spawn != null else Vector2(576, 560)
	if layout is MazeDefenseDungeon:
		var maze := layout as MazeDefenseDungeon
		for point: Vector2 in maze.maze["entrances"]:
			if point.y > entry_local.y:
				entry_local = point
	elif source != null and source.fixed_layout == null:
		# Generated layouts have no authored doorway: the south-center gap
		# joins the existing generated walkable graph below.
		entry_local = Vector2(39.5, 12.5) * source.cell_size
	layout.position = approach - entry_local
	entry = to_global(approach)
	arrival = entry - door_direction * 96.0
	if source == null:
		# The old crystal scene had only a drawn frame, not collision. Give
		# its existing arena footprint the same terrain wall seam as lairs.
		source = TerrainMap.new()
		source.name = "Terrain"
		source.z_index = -60
		layout.add_child(source)
		var cells := {}
		for x in range(3,15):
			for y in range(1,11):
				cells[Vector2i(x,y)] = TerrainTypes.OBSTACLE if x==3 or x==14 or y==1 or y==10 else TerrainTypes.GROUND
		source.set_cells(cells)
	_open_source_door(source)
	_stamp_terrain(source)
	# Each original region terrain draws its palette/art. Shared terrain is
	# the invisible collision lookup, just like the original overworld's
	# decor lookup: revealing it would draw rocky walls around every tree.
	source.visible = true
	# Presentation must rebuild after movement; its _ready ran at origin.
	source.art_enabled = true
	_source = source
	terrain.cell_changed.connect(_on_shared_cell_changed)

	set_active(false)

func _stamp_terrain(source: TerrainMap) -> void:
	var cells := {}
	var source_cells := source.assigned_cells()
	if source_cells.is_empty():
		bounds = Rect2(global_position + layout.position, Vector2(1152, 704))
		return
	var min_cell: Vector2i = source_cells[0]
	var max_cell := min_cell
	for cell: Vector2i in source_cells:
		min_cell = min_cell.min(cell)
		max_cell = max_cell.max(cell)
	bounds = Rect2(source.to_global(Vector2(min_cell) * source.cell_size), Vector2(max_cell - min_cell + Vector2i.ONE) * source.cell_size)
	# Clear existing overworld decor inside the layout footprint, including
	# floor cells omitted from the sparse source store. No trees in rooms.
	var lo := terrain.world_to_cell(bounds.position)
	var hi := terrain.world_to_cell(bounds.end - Vector2.ONE)
	var style_id: StringName = TerrainTypes.OBSTACLE
	if source.palette != null:
		var wall := source.palette.tile(TerrainTypes.OBSTACLE)
		if wall != null:
			var tile := wall.duplicate() as TerrainTile
			tile.id = StringName(String(encounter_id) + "_wall")
			style_id = tile.id
			var palette := terrain.palette
			if palette == null:
				palette = TerrainPalette.new()
			palette.tiles.append(tile)
			terrain.palette = palette
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			var target := Vector2i(x, y)
			var world := terrain.cell_to_world(target)
			var source_cell := source.world_to_cell(world)
			var type := source.tile_type_at_cell(source_cell)
			cells[target] = style_id if type == TerrainTypes.OBSTACLE else type
	# Physical south entrance at the former PlayerSpawn. The host may place
	# encounter barriers here, but there is never a transport/exit portal.
	var forward := Vector2i(door_direction)
	var side := Vector2i(door_direction.orthogonal())
	for x in range(-1, 2):
		for y in range(-3, 6):
			cells[terrain.world_to_cell(entry) + side*x + forward*y] = TerrainTypes.GROUND
	terrain.set_cells(cells)
func _open_source_door(source: TerrainMap) -> void:
	var center := source.world_to_cell(entry)
	var forward := Vector2i(door_direction)
	var side := Vector2i(door_direction.orthogonal())
	var cells := {}
	# Join the boundary opening to the existing walkable graph, even for a
	# generated layout with a thick wall at the chosen physical approach.
	var depth := 2
	while depth < 40 and not source.is_walkable_at_cell(center - forward*depth):
		depth += 1
	for across in range(-1,2):
		for along in range(-depth,4):
			cells[center + side*across + forward*along] = TerrainTypes.GROUND
	source.set_cells(cells)

func contains(world: Vector2) -> bool:
	return bounds.has_point(world)

func keep_active() -> bool:
	if layout == null:
		return false
	for node in layout.get_children():
		if node.has_method("is_active") and node.call("is_active"):
			return true
	return false

func set_active(value: bool) -> void:
	active = value
	if layout == null:
		return
	layout.process_mode = Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED
	_sync_collisions(layout, value)

func refresh_dormancy() -> void:
	if not active and layout != null:
		_sync_collisions(layout, false) # includes deferred spawns/slime children

func _sync_collisions(node: Node, enabled: bool) -> void:
	if node is CollisionObject2D:
		var body := node as CollisionObject2D
		if not _collision_state.has(body.get_instance_id()):
			_collision_state[body.get_instance_id()] = [body.collision_layer, body.collision_mask]
		var original: Array = _collision_state[body.get_instance_id()]
		body.collision_layer = original[0] if enabled else 0
		body.collision_mask = original[1] if enabled else 0
	for child in node.get_children():
		_sync_collisions(child, enabled)

## Physical edits (destroyed blocks/terrain spells) update the original
## palette renderer and maze navigation too. A source tile can span several
## shared cells; keep that tile's physical footprint coherent with its art.
func _on_shared_cell_changed(cell: Vector2i, _old: StringName, type: StringName) -> void:
	if _syncing_terrain or _source == null:
		return
	var world := terrain.cell_to_world(cell)
	if not bounds.has_point(world):
		return
	_syncing_terrain = true
	var source_cell := _source.world_to_cell(world)
	var source_type := TerrainTypes.OBSTACLE if type == StringName(String(encounter_id)+"_wall") else type
	if _source.is_valid_type(source_type):
		_source.set_cell(source_cell, source_type)
		var origin := _source.to_global(Vector2(source_cell) * _source.cell_size)
		var lo := terrain.world_to_cell(origin)
		var hi := terrain.world_to_cell(origin + Vector2.ONE * (_source.cell_size-1))
		var cells := {}
		for x in range(lo.x,hi.x+1):
			for y in range(lo.y,hi.y+1): cells[Vector2i(x,y)] = type
		terrain.set_cells(cells)
	_syncing_terrain = false
