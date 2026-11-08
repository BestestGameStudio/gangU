class_name TerrainPalette
extends Resource
## #266: a dungeon's own terrain tiles. Assign one to a TerrainMap (for a
## generated dungeon: generated_dungeon.gd's `tile_palette`) and the map
## draws these looks, the movement rules follow each tile's category, and
## TerrainGen builds the map out of these tiles.
##
## Generator mapping: biome i uses open_tiles[i] for open ground and
## feature_tiles[i] for its noise features; border_tile rings the map and
## fills enclosed layouts. Empty lists / empty border keep the built-in
## grass/tree + snow/ice biomes and OBSTACLE border. Open tiles must be
## WALKABLE because the path guarantee carves corridors into them.

@export var tiles: Array[TerrainTile] = []
@export var open_tiles: Array[StringName] = []
@export var feature_tiles: Array[StringName] = []
@export var border_tile: StringName = &""

func tile(id: StringName) -> TerrainTile:
	for t in tiles:
		if t != null and t.id == id:
			return t
	return null

func has_tile(id: StringName) -> bool:
	return tile(id) != null

## True iff `type` can be placed on a map using this palette.
func is_valid_type(type: StringName) -> bool:
	return TerrainTypes.is_valid(type) or has_tile(type)

## Palette ids that are not built-in types, in palette order.
func custom_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for t in tiles:
		if t != null and t.id != &"" and not TerrainTypes.is_valid(t.id) and not out.has(t.id):
			out.append(t.id)
	return out

## Full properties of `type` under this palette (a fresh copy).
func properties(type: StringName) -> Dictionary:
	var t := tile(type)
	if t == null:
		return TerrainTypes.properties(type)
	var props := TerrainTypes.properties(type if TerrainTypes.is_valid(type) else TerrainTypes.GROUND)
	TerrainTypes.apply_movement(props, t.movement)
	if not TerrainTypes.is_valid(type) and t.movement != TerrainTypes.Movement.WALKABLE:
		props["speed_multiplier"] = 0.0
	return props

## [[open, feature], ...] for TerrainGen, or the built-in biomes when this
## palette does not define any (or defines an invalid set).
func biomes() -> Array:
	if open_tiles.is_empty() or not validate().is_empty():
		return TerrainGen.BIOMES
	var out: Array = []
	for i in open_tiles.size():
		out.append([open_tiles[i], feature_tiles[i]])
	return out

func border() -> StringName:
	return border_tile if border_tile != &"" and validate().is_empty() else TerrainTypes.OBSTACLE

## Human-readable problems; empty means the palette is usable as-is.
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var seen := {}
	for t in tiles:
		if t == null or t.id == &"":
			errors.append("tile with an empty id")
			continue
		if seen.has(t.id):
			errors.append("duplicate tile id '%s'" % t.id)
		seen[t.id] = true
	if open_tiles.size() != feature_tiles.size():
		errors.append("open_tiles (%d) and feature_tiles (%d) differ in length" % [open_tiles.size(), feature_tiles.size()])
	for id in open_tiles:
		if not is_valid_type(id):
			errors.append("unknown open tile '%s'" % id)
		elif properties(id)["movement"] != TerrainTypes.Movement.WALKABLE:
			errors.append("open tile '%s' is not walkable" % id)
	for id in feature_tiles:
		if not is_valid_type(id):
			errors.append("unknown feature tile '%s'" % id)
	if border_tile != &"":
		if not is_valid_type(border_tile):
			errors.append("unknown border tile '%s'" % border_tile)
		elif properties(border_tile)["movement"] == TerrainTypes.Movement.WALKABLE:
			errors.append("border tile '%s' is walkable" % border_tile)
	return errors
