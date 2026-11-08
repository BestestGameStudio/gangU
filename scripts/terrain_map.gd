class_name TerrainMap
extends Node2D
## #142 (Terrain A1) terrain grid: the authoritative cell -> tile-type store
## plus THE world-position lookup seam. Integration contract (issue #142):
## downstream issues (A2/A4/B1/B3/C1/C2) consume ONLY tile_type_at /
## properties_at / is_walkable_at and the cell<->world helpers here - never
## TileMapLayer internals and never the raw store.
##
## Sparse store: unset cells read as GROUND (flat-world default), so only
## non-ground cells are recorded. Writes go through set_cell/set_cells/clear_cell.
##
## Presentation: ground + obstacle TileMapLayers are BUILT FROM the data on
## every change; colored square tiles are the disclosed first-pass debug
## presentation (per Colin's phased split), not an art requirement. The
## layers are output-only. A walkable non-default type renders on Ground,
## a non-walkable type on Obstacle; default GROUND renders as the scene
## background (no tile), keeping the sparse store literal.

## Grid cell size in pixels (matches BackgroundGrid's 64 spacing).
@export var cell_size: int = 64

## First-pass debug tile colors, keyed by type. Presentation only.
const TYPE_COLORS: Dictionary = {
	TerrainTypes.GROUND: Color(0.16, 0.24, 0.18, 1.0),
	TerrainTypes.OBSTACLE: Color(0.45, 0.28, 0.22, 1.0),
	TerrainTypes.GRASS: Color(0.36, 0.62, 0.3, 1.0),
	TerrainTypes.TREE: Color(0.1, 0.3, 0.14, 1.0),
	TerrainTypes.SNOW: Color(0.92, 0.94, 0.97, 1.0),
	TerrainTypes.ICE: Color(0.66, 0.88, 0.95, 1.0),
	TerrainTypes.MUD: Color(0.42, 0.3, 0.16, 1.0),
	TerrainTypes.WATER: Color(0.15, 0.4, 0.8, 1.0),
	TerrainTypes.MOUNTAIN: Color(0.5, 0.5, 0.52, 1.0),
}
## Fallback swatch for a registered type with no listed color.
const DEFAULT_TILE_COLOR: Color = Color(0.3, 0.3, 0.35, 1.0)

var _cells: Dictionary = {} ## Vector2i -> StringName, non-default cells only
var _ground_layer: TileMapLayer = null
var _obstacle_layer: TileMapLayer = null

func _ready() -> void:
	_build_layers()
	_rebuild_presentation()

## Assigns a cell. Returns false and changes nothing for an unregistered
## type. Assigning GROUND restores the default (erases the sparse entry).
func set_cell(cell: Vector2i, type: StringName) -> bool:
	if not TerrainTypes.is_valid(type):
		return false
	if type == TerrainTypes.GROUND:
		_cells.erase(cell)
	else:
		_cells[cell] = type
	_rebuild_presentation()
	return true

## Bulk write (Vector2i -> StringName). All-or-nothing: any unregistered
## type refuses the whole batch with no change. Presentation rebuilds once,
## since a per-cell set_cell rebuild makes filling a map quadratic.
func set_cells(cells: Dictionary) -> bool:
	for type: StringName in cells.values():
		if not TerrainTypes.is_valid(type):
			return false
	for cell: Vector2i in cells:
		var type: StringName = cells[cell]
		if type == TerrainTypes.GROUND:
			_cells.erase(cell)
		else:
			_cells[cell] = type
	_rebuild_presentation()
	return true

## Restores a cell to the flat-world default (GROUND).
func clear_cell(cell: Vector2i) -> void:
	_cells.erase(cell)
	_rebuild_presentation()

## --- THE lookup seam (downstream consumes only from here) ---

func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i((to_local(world_pos) / float(cell_size)).floor())

func cell_to_world(cell: Vector2i) -> Vector2:
	return to_global((Vector2(cell) + Vector2(0.5, 0.5)) * float(cell_size))

func tile_type_at_cell(cell: Vector2i) -> StringName:
	return _cells.get(cell, TerrainTypes.GROUND)

func tile_type_at(world_pos: Vector2) -> StringName:
	return tile_type_at_cell(world_to_cell(world_pos))

func is_walkable_at_cell(cell: Vector2i) -> bool:
	return TerrainTypes.is_walkable(tile_type_at_cell(cell))

func is_walkable_at(world_pos: Vector2) -> bool:
	return TerrainTypes.is_walkable(tile_type_at(world_pos))

## type + full properties at a world position, in one call. The returned
## Dictionary is a fresh copy (registry-safe).
func properties_at(world_pos: Vector2) -> Dictionary:
	var type: StringName = tile_type_at(world_pos)
	var props := TerrainTypes.properties(type)
	props["type"] = type
	return props

## Cells carrying a non-default assignment (flood-fill/debug enumeration).
func assigned_cells() -> Array:
	return _cells.keys()

## --- presentation (output-only; reads the store, never the reverse) ---

func _build_layers() -> void:
	var n := TerrainTypes.ALL.size()
	var img := Image.create(cell_size * n, cell_size, false, Image.FORMAT_RGBA8)
	for i in range(n):
		var type: StringName = TerrainTypes.ALL[i]
		img.fill_rect(Rect2i(i * cell_size, 0, cell_size, cell_size), TYPE_COLORS.get(type, DEFAULT_TILE_COLOR))
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(cell_size, cell_size)
	for i in range(n):
		src.create_tile(Vector2i(i, 0))
	var ts := TileSet.new()
	ts.tile_size = Vector2i(cell_size, cell_size)
	ts.add_source(src, 0)
	_ground_layer = TileMapLayer.new()
	_ground_layer.name = "Ground"
	_ground_layer.tile_set = ts
	add_child(_ground_layer)
	_obstacle_layer = TileMapLayer.new()
	_obstacle_layer.name = "Obstacle"
	_obstacle_layer.tile_set = ts
	add_child(_obstacle_layer)

func _atlas_column(type: StringName) -> int:
	return TerrainTypes.ALL.find(type)

func _rebuild_presentation() -> void:
	if _ground_layer == null:
		return # pre-_ready writes; _ready rebuilds from the store
	_ground_layer.clear()
	_obstacle_layer.clear()
	for cell: Vector2i in _cells:
		var type: StringName = _cells[cell]
		var col := Vector2i(_atlas_column(type), 0)
		if TerrainTypes.is_walkable(type):
			_ground_layer.set_cell(cell, 0, col)
		else:
			_obstacle_layer.set_cell(cell, 0, col)

## Test/debug introspection for the presentation legs (harness use; NOT
## part of the downstream gameplay contract).
func debug_layer_cells(walkable_layer: bool) -> Array[Vector2i]:
	if _ground_layer == null:
		return []
	var layer: TileMapLayer = _ground_layer if walkable_layer else _obstacle_layer
	var out: Array[Vector2i] = []
	out.assign(layer.get_used_cells())
	return out
