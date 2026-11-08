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
##
## #266: an optional `palette` lets a dungeon add its own tile types and
## restyle built-in ones. Every property lookup here goes through it, so
## movement, navigation and generation all see the palette's categories.

signal cell_destroyed(cell: Vector2i, old_type: StringName, new_type: StringName)

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

## Cosmetic palette over TYPE_COLORS; never touches the store or properties.
var season: TerrainSeason.Season = TerrainSeason.Season.SUMMER:
	set = _set_season
var _atlas_source: TileSetAtlasSource = null

## #266: the dungeon's own tiles. Changing it redraws the atlas; the cell
## store is left as is.
@export var palette: TerrainPalette = null:
	set = _set_palette

var _cells: Dictionary = {} ## Vector2i -> StringName, non-default cells only
var _ground_layer: TileMapLayer = null
var _obstacle_layer: TileMapLayer = null

func _ready() -> void:
	_build_layers()
	_rebuild_presentation()

## Assigns a cell. Returns false and changes nothing for an unregistered
## type. Assigning GROUND restores the default (erases the sparse entry).
func set_cell(cell: Vector2i, type: StringName) -> bool:
	if not is_valid_type(type):
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
		if not is_valid_type(type):
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

## The single entry point every damage source calls when it hits terrain.
## A destroyable cell becomes its registry destroyed_into type; anything
## else is left untouched. Returns true iff the cell changed.
func destroy_cell(cell: Vector2i) -> bool:
	var old_type := tile_type_at_cell(cell)
	var old_props := type_properties(old_type)
	if not old_props["destroyable"]:
		return false
	var new_type: StringName = old_props["destroyed_into"]
	if not set_cell(cell, new_type):
		return false
	cell_destroyed.emit(cell, old_type, new_type)
	return true

func destroy_at(world_pos: Vector2) -> bool:
	return destroy_cell(world_to_cell(world_pos))

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
	return type_properties(tile_type_at_cell(cell))["walkable"]

func is_walkable_at(world_pos: Vector2) -> bool:
	return is_walkable_at_cell(world_to_cell(world_pos))

## #266: the cell's TerrainTypes.Movement category.
func movement_at_cell(cell: Vector2i) -> TerrainTypes.Movement:
	return type_properties(tile_type_at_cell(cell))["movement"]

func movement_at(world_pos: Vector2) -> TerrainTypes.Movement:
	return movement_at_cell(world_to_cell(world_pos))

## True iff `type` is a built-in type or one of this map's palette tiles.
func is_valid_type(type: StringName) -> bool:
	return TerrainTypes.is_valid(type) or (palette != null and palette.has_tile(type))

## Properties of `type` on this map (palette-aware, fresh copy).
func type_properties(type: StringName) -> Dictionary:
	return palette.properties(type) if palette != null else TerrainTypes.properties(type)

## type + full properties at a world position, in one call. The returned
## Dictionary is a fresh copy (registry-safe).
func properties_at(world_pos: Vector2) -> Dictionary:
	var type: StringName = tile_type_at(world_pos)
	var props := type_properties(type)
	props["type"] = type
	return props

## Cells carrying a non-default assignment (flood-fill/debug enumeration).
func assigned_cells() -> Array:
	return _cells.keys()

## --- presentation (output-only; reads the store, never the reverse) ---

## Swaps the atlas texture only; cell data and placed tiles stay as they are.
func _set_season(value: TerrainSeason.Season) -> void:
	season = value
	if _atlas_source != null:
		_atlas_source.texture = _atlas_texture()

func _set_palette(value: TerrainPalette) -> void:
	palette = value
	if palette != null:
		var errors := palette.validate()
		if not errors.is_empty():
			push_warning("TerrainPalette '%s': %s" % [palette.resource_path, "; ".join(errors)])
	if _atlas_source != null:
		_sync_atlas_tiles()
		_rebuild_presentation()

## Atlas column order: built-in types first (stable columns), then the
## palette's new ids.
func _atlas_types() -> Array[StringName]:
	var out: Array[StringName] = TerrainTypes.ALL.duplicate()
	if palette != null:
		out.append_array(palette.custom_ids())
	return out

func _atlas_texture() -> ImageTexture:
	var types := _atlas_types()
	var n := types.size()
	var img := Image.create(cell_size * n, cell_size, false, Image.FORMAT_RGBA8)
	for i in range(n):
		var rect := Rect2i(i * cell_size, 0, cell_size, cell_size)
		var t: TerrainTile = palette.tile(types[i]) if palette != null else null
		if t == null:
			img.fill_rect(rect, TerrainSeason.color(season, types[i]))
		elif t.texture != null:
			var art := t.texture.get_image()
			if art.is_compressed():
				art.decompress()
			art.convert(Image.FORMAT_RGBA8)
			art.resize(cell_size, cell_size, Image.INTERPOLATE_NEAREST)
			img.blit_rect(art, Rect2i(Vector2i.ZERO, art.get_size()), rect.position)
		else:
			img.fill_rect(rect, t.color)
	return ImageTexture.create_from_image(img)

## Rebuilds the atlas texture and makes one tile per atlas column.
func _sync_atlas_tiles() -> void:
	_atlas_source.texture = _atlas_texture()
	var n := _atlas_types().size()
	for i in range(_atlas_source.get_tiles_count() - 1, -1, -1):
		var id := _atlas_source.get_tile_id(i)
		if id.x >= n:
			_atlas_source.remove_tile(id)
	for i in range(n):
		if not _atlas_source.has_tile(Vector2i(i, 0)):
			_atlas_source.create_tile(Vector2i(i, 0))

func _build_layers() -> void:
	_atlas_source = TileSetAtlasSource.new()
	_atlas_source.texture_region_size = Vector2i(cell_size, cell_size)
	_sync_atlas_tiles()
	var ts := TileSet.new()
	ts.tile_size = Vector2i(cell_size, cell_size)
	ts.add_source(_atlas_source, 0)
	_ground_layer = TileMapLayer.new()
	_ground_layer.name = "Ground"
	_ground_layer.tile_set = ts
	add_child(_ground_layer)
	_obstacle_layer = TileMapLayer.new()
	_obstacle_layer.name = "Obstacle"
	_obstacle_layer.tile_set = ts
	add_child(_obstacle_layer)

func _atlas_column(type: StringName) -> int:
	return _atlas_types().find(type)

func _rebuild_presentation() -> void:
	if _ground_layer == null:
		return # pre-_ready writes; _ready rebuilds from the store
	_ground_layer.clear()
	_obstacle_layer.clear()
	var types := _atlas_types()
	for cell: Vector2i in _cells:
		var type: StringName = _cells[cell]
		var col := Vector2i(types.find(type), 0)
		if col.x < 0:
			continue # palette swapped away from this type: no look to draw
		if type_properties(type)["walkable"]:
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
