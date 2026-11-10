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
## Terrain art pass: on top of those color layers the map draws sprite art
## (TerrainArt): every cell inside the bounding box of the assigned cells -
## default GROUND included - gets a floor tile (a hashed one of 4 variants,
## water animated), walls / mountains / cliffs / chasms get autotile pieces
## chosen from their 4 neighbours so runs connect, and trees / pines stand
## as objects over their floor. Grass and trees follow the season. A type
## with no art (BLOCK, winter WATER, palette tiles without an `art` id)
## leaves its color swatch visible. The color layers stay the data mirror
## harnesses read (debug_layer_cells, atlas colors).
##
## #266: an optional `palette` lets a dungeon add its own tile types and
## restyle built-in ones. Every property lookup here goes through it, so
## movement, navigation and generation all see the palette's categories.

signal cell_destroyed(cell: Vector2i, old_type: StringName, new_type: StringName)
## #167: a spell element interaction (TerrainInteractions rule `rule_id`)
## changed `cell` from old_type to new_type.
signal cell_interacted(cell: Vector2i, old_type: StringName, new_type: StringName, rule_id: StringName)

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
	TerrainTypes.BLOCK: Color(0.7, 0.56, 0.34, 1.0), ## #216 placeholder sandstone
	TerrainTypes.TALL_GRASS: Color(0.24, 0.48, 0.2, 1.0), ## #461 placeholder
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

## #167: spell -> terrain element rules this map answers to. Empty means the
## shared TerrainInteractions registry; an area may set its own list.
@export var interaction_rules: Array[TerrainInteraction] = []

## #396: a hand-designed map written into the store once, in _ready (before
## the first presentation build). Null = cells come from code (TerrainGen,
## MazeGen, harnesses) or the map stays flat.
@export var fixed_layout: TerrainFixedLayout = null

var _cells: Dictionary = {} ## Vector2i -> StringName, non-default cells only
## #407: solid circles that stop projectiles (overworld trees). World-space
## Vector3(x, y, radius). Kept apart from the cell store: OBSTACLE cells
## (dungeon borders, maze walls) keep letting shots through as before.
var _shot_blockers: Array[Vector3] = []
var _ground_layer: TileMapLayer = null
var _obstacle_layer: TileMapLayer = null

## Draw TerrainArt sprites over the color swatches. Off = the first-pass
## colored squares only.
@export var art_enabled: bool = true:
	set(value):
		art_enabled = value
		_rebuild_art()
var _art_floor: TileMapLayer = null
var _art_walls: TileMapLayer = null
var _art_objects: TileMapLayer = null
var _art_fx: Node2D = null

func _ready() -> void:
	if fixed_layout != null and not fixed_layout.apply(self):
		push_warning("TerrainFixedLayout '%s' names a tile type this map does not know" % fixed_layout.resource_path)
	_build_layers()
	_rebuild_presentation()
	visibility_changed.connect(_rebuild_art)

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
	var old_art := art_at_cell(cell)
	if not set_cell(cell, new_type):
		return false
	_play_destroy(cell, old_art)
	cell_destroyed.emit(cell, old_type, new_type)
	return true

func destroy_at(world_pos: Vector2) -> bool:
	return destroy_cell(world_to_cell(world_pos))

## #167 (Terrain B1): the rule that fires when a spell with `spell_tags`
## hits `cell`, or null. Matched by element tag only, through the
## palette-aware properties (TerrainInteractions owns the rule list).
func interaction_for_cell(cell: Vector2i, spell_tags: Array) -> TerrainInteraction:
	var tile_tags: Array = type_properties(tile_type_at_cell(cell))["element_tags"]
	var rule := TerrainInteractions.find(spell_tags, tile_tags, interaction_rules)
	if rule == null or not is_valid_type(rule.result_type):
		return null
	return rule

## #167: the single entry point for spell -> terrain element interactions.
## Applies the matching rule's result type and emits cell_interacted.
## Returns the rule that fired, or null when nothing changed.
func interact_cell(cell: Vector2i, spell_tags: Array) -> TerrainInteraction:
	var rule := interaction_for_cell(cell, spell_tags)
	if rule == null:
		return null
	var old_type := tile_type_at_cell(cell)
	if not set_cell(cell, rule.result_type):
		return null
	cell_interacted.emit(cell, old_type, rule.result_type, rule.id)
	return rule

func interact_at(world_pos: Vector2, spell_tags: Array) -> TerrainInteraction:
	return interact_cell(world_to_cell(world_pos), spell_tags)

## #407: replaces the projectile-blocking circles (Vector3(x, y, radius),
## world space). Indestructible: hits never remove them.
func set_projectile_blockers(circles: Array[Vector3]) -> void:
	_shot_blockers = circles.duplicate()

func projectile_blockers() -> Array[Vector3]:
	return _shot_blockers.duplicate()

## #407: the fraction (0..1) of the segment `from` -> `from + motion` at
## which its centre line first ENTERS a blocking circle, or -1.0 for none.
## A segment that starts inside a circle ignores that circle, so a shot
## fired while standing against a canopy edge flies out instead of dying
## on its own first frame.
func projectile_block_t(from: Vector2, motion: Vector2) -> float:
	var best := -1.0
	var to := from + motion
	for c in _shot_blockers:
		var at := Vector2(c.x, c.y)
		if from.distance_squared_to(at) <= c.z * c.z:
			continue
		var t := Geometry2D.segment_intersects_circle(from, to, at, c.z)
		if t >= 0.0 and (best < 0.0 or t < best):
			best = t
	return best

## #443: LOW cover a lobbed shot arcs over (Daniel 2026-11-09: "rocks go
## over low cover only (barricades, trees). Maze walls and stone blocks
## still block them"). Low = a TREE cell, or a cell planted under an #407
## overworld-tree circle (the #391 rule: cell centre inside the canopy, or
## the tree's own cell). Every other solid cell - OBSTACLE walls, MOUNTAIN,
## BLOCK stone blocks, palette walls - is high cover.
func is_low_cover_cell(cell: Vector2i) -> bool:
	if tile_type_at_cell(cell) == TerrainTypes.TREE:
		return true
	if _shot_blockers.is_empty():
		return false
	var centre := cell_to_world(cell)
	for c in _shot_blockers:
		var at := Vector2(c.x, c.y)
		if centre.distance_to(at) <= c.z or world_to_cell(at) == cell:
			return true
	return false

## #443: true when a lobbed shot from `from` to `to` would be stopped by high
## cover (a projectile-blocking cell that is not low cover). Half-cell
## sampling, the starting cell ignored - the Projectile._terrain_events idiom.
func lob_blocked(from: Vector2, to: Vector2) -> bool:
	var start := world_to_cell(from)
	var samples := maxi(1, ceili(from.distance_to(to) / (cell_size * 0.5)))
	for i in range(1, samples + 1):
		var cell := world_to_cell(from.lerp(to, float(i) / float(samples)))
		if cell == start:
			continue
		if type_properties(tile_type_at_cell(cell))["blocks_projectiles"] and not is_low_cover_cell(cell):
			return true
	return false

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

## #461: true when the cell at world_pos hides whoever stands there (tall
## grass). Palette-aware like every other property lookup.
func conceals_at(world_pos: Vector2) -> bool:
	return type_properties(tile_type_at(world_pos)).get("conceals", false)

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
		_rebuild_art()

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
	# Art layers: 64 px TileSet scaled to this map's cell size, drawn over
	# the color layers (child order).
	var k := float(cell_size) / float(TerrainArt.CELL)
	for layer_name in ["ArtFloor", "ArtWalls", "ArtObjects"]:
		var layer := TileMapLayer.new()
		layer.name = layer_name
		layer.tile_set = TerrainArt.tile_set()
		layer.scale = Vector2(k, k)
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if is_equal_approx(k, 1.0) else CanvasItem.TEXTURE_FILTER_LINEAR
		add_child(layer)
	_art_floor = get_node("ArtFloor")
	_art_walls = get_node("ArtWalls")
	_art_objects = get_node("ArtObjects")
	_art_fx = Node2D.new()
	_art_fx.name = "ArtFx"
	add_child(_art_fx)

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
	_rebuild_art()

## The TerrainArt id drawing `cell` (&"" = color swatch).
func art_at_cell(cell: Vector2i) -> StringName:
	var type := tile_type_at_cell(cell)
	var t: TerrainTile = palette.tile(type) if palette != null else null
	return TerrainArt.art_for(type, season, t)

## Cells the art covers: the bounding box of every assigned cell (empty
## for a flat map, which keeps showing the scene background).
func art_bounds() -> Rect2i:
	var first := true
	var r := Rect2i()
	for cell: Vector2i in _cells:
		if first:
			r = Rect2i(cell, Vector2i.ONE)
			first = false
		else:
			r = r.merge(Rect2i(cell, Vector2i.ONE))
	return r

func _rebuild_art() -> void:
	if _art_floor == null:
		return
	_art_floor.clear()
	_art_walls.clear()
	_art_objects.clear()
	if not art_enabled or not is_visible_in_tree():
		return
	var bounds := art_bounds()
	var arts := {}
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var c := Vector2i(x, y)
			arts[c] = art_at_cell(c)
	for c: Vector2i in arts:
		var art: StringName = arts[c]
		match TerrainArt.kind(art):
			TerrainArt.Kind.FLOOR:
				_set_floor(c, art)
			TerrainArt.Kind.OBJECT:
				_set_floor(c, TerrainArt.floor_under(art))
				_art_objects.set_cell(c, TerrainArt.OBJECTS_SOURCE, Vector2i(TerrainArt.variant(c, 2), TerrainArt.row(art)))
			TerrainArt.Kind.AUTOTILE:
				# Off-bounds neighbours connect, so a map's outer ring
				# shows no rim on its outside.
				var m := TerrainArt.mask(c, func(n: Vector2i) -> bool: return arts.get(n, art) == art)
				var alt := TerrainArt.variant(c, 3, 2)
				_art_walls.set_cell(c, TerrainArt.TILES_SOURCE, Vector2i(m, TerrainArt.row(art) + alt))

func _set_floor(c: Vector2i, art: StringName) -> void:
	var col := 0 if TerrainArt.SETS[art].get("animated", false) else TerrainArt.variant(c, 1)
	_art_floor.set_cell(c, TerrainArt.TILES_SOURCE, Vector2i(col, TerrainArt.row(art)))

## Tree / block break: the art's 4-frame destroy one-shot (ends on the
## stump / rubble), held briefly, then faded out over the new floor.
func _play_destroy(cell: Vector2i, art: StringName) -> void:
	if _art_fx == null or not art_enabled or not TerrainArt.has_destroy(art) or not is_inside_tree():
		return
	var s := AnimatedSprite2D.new()
	s.sprite_frames = TerrainArt.destroy_frames(art)
	s.texture_filter = _art_floor.texture_filter
	s.position = (Vector2(cell) + Vector2(0.5, 0.5)) * float(cell_size)
	var k := float(cell_size) / float(TerrainArt.CELL)
	s.scale = Vector2(k, k)
	_art_fx.add_child(s)
	s.play()
	s.animation_finished.connect(func():
		var tw := s.create_tween()
		tw.tween_interval(0.8)
		tw.tween_property(s, "modulate:a", 0.0, 0.6)
		tw.tween_callback(s.queue_free))

## Harness introspection for the art layers ("floor", "walls", "objects"):
## the atlas coords drawn at `cell`, or (-1, -1).
func debug_art_coords(layer: String, cell: Vector2i) -> Vector2i:
	var l: TileMapLayer = {"floor": _art_floor, "walls": _art_walls, "objects": _art_objects}.get(layer)
	return l.get_cell_atlas_coords(cell) if l != null else Vector2i(-1, -1)

func debug_destroy_fx_count() -> int:
	return _art_fx.get_child_count() if _art_fx != null else 0

## Test/debug introspection for the presentation legs (harness use; NOT
## part of the downstream gameplay contract).
func debug_layer_cells(walkable_layer: bool) -> Array[Vector2i]:
	if _ground_layer == null:
		return []
	var layer: TileMapLayer = _ground_layer if walkable_layer else _obstacle_layer
	var out: Array[Vector2i] = []
	out.assign(layer.get_used_cells())
	return out
