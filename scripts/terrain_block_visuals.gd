class_name TerrainBlockVisuals
extends Node2D
## #327: sprite-sheet look for the #216 spell-created terrain block (BLOCK).
## Child of a TerrainMap (the "Terrain" node in dungeon_generated). The map's
## atlas keeps ownership of cell data and walkability; this node only mirrors
## BLOCK cells with an AnimatedSprite2D: the rock wall's "intact" frame while
## the block stands, the "create" build-up when a block appears (spell cast,
## demo placement or debug write - any new BLOCK cell is caught by a per-frame
## diff of the map's sparse store) and the crack-and-collapse "destroy"
## one-shot when the map reports the cell destroyed. Presentation only: no
## placement, damage or walkability behavior lives here, so refused casts,
## one-hit destroy and movement rules are exactly #216/#169's.
## #437 (Daniel, 2026-11-09: stone-block terrain invisible in the
## overworld): the map may also be named by `map_path` instead of being
## this node's parent, so an area whose Terrain node is hidden (the
## overworld's collision-only grid, #391) can still show the block - a
## child of an invisible node never renders.

const FRAMES: SpriteFrames = preload("res://resources/sprites/terrain_block_frames.tres")
const CELL_PX := 64.0 ## art cell edge; scaled to the map's cell_size

## #437: optional path to the TerrainMap to mirror. Empty = the parent,
## the original dungeon wiring.
@export var map_path: NodePath

var _map: TerrainMap = null
var _standing: Dictionary = {} ## Vector2i -> AnimatedSprite2D (create or intact)

func _ready() -> void:
	if map_path != NodePath(""):
		_map = get_node_or_null(map_path) as TerrainMap
	if _map == null:
		_map = get_parent() as TerrainMap
	if _map == null:
		push_warning("TerrainBlockVisuals: no TerrainMap at map_path or as parent; idling")
		set_physics_process(false)
		return
	_map.cell_destroyed.connect(_on_cell_destroyed)
	for cell: Vector2i in _map.assigned_cells():
		if _map.tile_type_at_cell(cell) == TerrainTypes.BLOCK:
			_spawn(cell, false)

func _physics_process(_delta: float) -> void:
	if _map == null:
		return
	for cell: Vector2i in _map.assigned_cells():
		if _map.tile_type_at_cell(cell) == TerrainTypes.BLOCK and not _standing.has(cell):
			_spawn(cell, true)

## One wall sprite at `cell`; fresh placements play the build-up first.
func _spawn(cell: Vector2i, play_create: bool) -> void:
	var s := AnimatedSprite2D.new()
	s.sprite_frames = FRAMES
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.z_index = 1 ## above the map's obstacle atlas swatch
	s.position = (Vector2(cell) + Vector2(0.5, 0.5)) * float(_map.cell_size)
	var k := float(_map.cell_size) / CELL_PX
	s.scale = Vector2(k, k)
	add_child(s)
	_standing[cell] = s
	if play_create:
		s.play(&"create")
		s.animation_finished.connect(func():
			if is_instance_valid(s) and _standing.get(cell) == s:
				s.play(&"intact"))
	else:
		s.play(&"intact")

## The block broke: drop the standing wall, collapse into rubble, then free.
func _on_cell_destroyed(cell: Vector2i, old_type: StringName, _new_type: StringName) -> void:
	if old_type != TerrainTypes.BLOCK or _map == null:
		return
	var s: AnimatedSprite2D = _standing.get(cell)
	if s != null:
		_standing.erase(cell)
		s.queue_free()
	var rubble := AnimatedSprite2D.new()
	rubble.sprite_frames = FRAMES
	rubble.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rubble.z_index = 1
	rubble.position = (Vector2(cell) + Vector2(0.5, 0.5)) * float(_map.cell_size)
	var k := float(_map.cell_size) / CELL_PX
	rubble.scale = Vector2(k, k)
	add_child(rubble)
	rubble.play(&"destroy")
	rubble.animation_finished.connect(rubble.queue_free)

## Harness introspection: the standing wall sprite at `cell`, if any.
func debug_standing_at(cell: Vector2i) -> AnimatedSprite2D:
	return _standing.get(cell)

## Harness introspection: one-shot collapse sprites currently playing.
func debug_rubble_count() -> int:
	var n := 0
	for c in get_children():
		if c is AnimatedSprite2D and not _standing.values().has(c):
			n += 1
	return n
