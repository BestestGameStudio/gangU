class_name TerrainArt
## Terrain art lookup (sprite pass over the #142 colored-square tiles).
## Pure data + small helpers: which atlas cells draw a terrain type, how
## floor variants are picked and how autotile pieces connect. TerrainMap
## builds its art layers from this; the color atlas stays as the fallback
## for any type without art (and for harness introspection).
##
## Atlases (packed by tools/sprites/pack_terrain_sheets.py, 64 px cells):
## - terrain_tiles.png: rows 0-10 floors (cols 0-3 = variants; water's 4
##   cols are its animation loop), rows 11-24 autotile sets, two rows each
##   (A/B corner variants), col = exposed-side mask (N=1 E=2 S=4 W=8).
## - terrain_objects.png (80 px cells): tree spring/summer/autumn/winter, pine, block;
##   cols 0-3 idle variants, cols 4-7 destroy sequence.

enum Kind { NONE, FLOOR, AUTOTILE, OBJECT }

const TILES: Texture2D = preload("res://assets/sprites/terrain_tiles.png")
const OBJECTS: Texture2D = preload("res://assets/sprites/terrain_objects.png")
const CELL := 64
## Object cells are 80 px, centred on their 64 px game cell (overhang).
const OBJ_CELL := 80
const TILES_SOURCE := 1
const OBJECTS_SOURCE := 2
const VARIANTS := 4
const WATER_FPS := 4.0
const DESTROY_FPS := 10.0

const N := 1
const E := 2
const S := 4
const W := 8

## art id -> {kind, row[, animated][, floor][, destroy]}
const SETS: Dictionary = {
	&"ground": {"kind": Kind.FLOOR, "row": 0},
	&"grass_spring": {"kind": Kind.FLOOR, "row": 1},
	&"grass_summer": {"kind": Kind.FLOOR, "row": 2},
	&"grass_autumn": {"kind": Kind.FLOOR, "row": 3},
	&"grass_winter": {"kind": Kind.FLOOR, "row": 4},
	&"meadow": {"kind": Kind.FLOOR, "row": 5},
	&"scree": {"kind": Kind.FLOOR, "row": 6},
	&"snow": {"kind": Kind.FLOOR, "row": 7},
	&"ice": {"kind": Kind.FLOOR, "row": 8},
	&"mud": {"kind": Kind.FLOOR, "row": 9},
	&"water": {"kind": Kind.FLOOR, "row": 10, "animated": true},
	&"obstacle_slate": {"kind": Kind.AUTOTILE, "row": 11},
	&"obstacle_brown": {"kind": Kind.AUTOTILE, "row": 13},
	&"obstacle_purple": {"kind": Kind.AUTOTILE, "row": 15},
	&"obstacle_green": {"kind": Kind.AUTOTILE, "row": 17},
	&"mountain": {"kind": Kind.AUTOTILE, "row": 19},
	&"cliff": {"kind": Kind.AUTOTILE, "row": 21},
	&"chasm": {"kind": Kind.AUTOTILE, "row": 23},
	&"tree_spring": {"kind": Kind.OBJECT, "row": 0, "floor": &"grass_spring", "destroy": true},
	&"tree_summer": {"kind": Kind.OBJECT, "row": 1, "floor": &"grass_summer", "destroy": true},
	&"tree_autumn": {"kind": Kind.OBJECT, "row": 2, "floor": &"grass_autumn", "destroy": true},
	&"tree_winter": {"kind": Kind.OBJECT, "row": 3, "floor": &"grass_winter", "destroy": true},
	&"pine_forest": {"kind": Kind.OBJECT, "row": 4, "floor": &"meadow"},
	&"stone_block": {"kind": Kind.OBJECT, "row": 5, "floor": &"ground", "destroy": true},
}

const SEASON_SUFFIX: Dictionary = {
	TerrainSeason.Season.SPRING: "spring",
	TerrainSeason.Season.SUMMER: "summer",
	TerrainSeason.Season.AUTUMN: "autumn",
	TerrainSeason.Season.WINTER: "winter",
}

## The art id that draws `type` in `season`, or &"" for the color
## fallback. `tile` is the palette's TerrainTile for the type (null when
## the map has no palette entry for it): a palette entry decides on its
## own (its `art` id, or the color/texture swatch when it has none).
## BLOCK has no tile art: the #327 TerrainBlockVisuals sprite draws it.
## Winter WATER has no art either and keeps its seasonal color.
static func art_for(type: StringName, season: TerrainSeason.Season, tile: TerrainTile = null) -> StringName:
	if tile != null:
		return tile.art if SETS.has(tile.art) else &""
	var suffix: String = SEASON_SUFFIX[season]
	match type:
		TerrainTypes.GROUND: return &"ground"
		TerrainTypes.GRASS: return StringName("grass_" + suffix)
		TerrainTypes.TREE: return StringName("tree_" + suffix)
		TerrainTypes.SNOW: return &"snow"
		TerrainTypes.ICE: return &"ice"
		TerrainTypes.MUD: return &"mud"
		TerrainTypes.WATER: return &"" if season == TerrainSeason.Season.WINTER else &"water"
		TerrainTypes.MOUNTAIN: return &"mountain"
		TerrainTypes.OBSTACLE: return &"obstacle_brown"
	return &""

static func kind(art: StringName) -> Kind:
	return SETS[art]["kind"] if SETS.has(art) else Kind.NONE

static func row(art: StringName) -> int:
	return SETS[art]["row"]

## The floor drawn under an object (tree -> its season's grass).
static func floor_under(art: StringName) -> StringName:
	return SETS[art].get("floor", &"ground")

static func has_destroy(art: StringName) -> bool:
	return SETS.has(art) and SETS[art].get("destroy", false)

## Deterministic per-cell 0..n-1 pick (no RNG, stable across rebuilds).
static func variant(cell: Vector2i, salt: int, n: int = VARIANTS) -> int:
	var h := (cell.x * 73856093) ^ (cell.y * 19349663) ^ (salt * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return posmod(h, n)

## Exposed-side mask for an autotile cell: a side is exposed when the
## neighbour does not draw the same art. `same` is a Callable(Vector2i) ->
## bool answering "this neighbour connects".
static func mask(cell: Vector2i, same: Callable) -> int:
	var m := 0
	if not same.call(cell + Vector2i.UP):
		m |= N
	if not same.call(cell + Vector2i.RIGHT):
		m |= E
	if not same.call(cell + Vector2i.DOWN):
		m |= S
	if not same.call(cell + Vector2i.LEFT):
		m |= W
	return m

## The art TileSet: source 1 = tiles atlas (water animated), source 2 =
## objects atlas. Built once and shared by every map.
static var _tile_set: TileSet = null

static func tile_set() -> TileSet:
	if _tile_set != null:
		return _tile_set
	var ts := TileSet.new()
	ts.tile_size = Vector2i(CELL, CELL)
	var tiles := TileSetAtlasSource.new()
	tiles.texture = TILES
	tiles.texture_region_size = Vector2i(CELL, CELL)
	var water_row: int = SETS[&"water"]["row"]
	var size := TILES.get_size() / CELL
	for y in size.y:
		for x in size.x:
			if y == water_row and x > 0:
				continue # animation frames of (0, water_row)
			tiles.create_tile(Vector2i(x, y))
	var water := Vector2i(0, water_row)
	tiles.set_tile_animation_columns(water, VARIANTS)
	tiles.set_tile_animation_frames_count(water, VARIANTS)
	for i in VARIANTS:
		tiles.set_tile_animation_frame_duration(water, i, 1.0 / WATER_FPS)
	ts.add_source(tiles, TILES_SOURCE)
	var objects := TileSetAtlasSource.new()
	objects.texture = OBJECTS
	objects.texture_region_size = Vector2i(OBJ_CELL, OBJ_CELL)
	var osize := OBJECTS.get_size() / OBJ_CELL
	for y in osize.y:
		for x in VARIANTS:
			objects.create_tile(Vector2i(x, y))
	ts.add_source(objects, OBJECTS_SOURCE)
	_tile_set = ts
	return ts

## One-shot destroy frames (cols 4-7) for an object art id.
static var _destroy_frames: Dictionary = {}

static func destroy_frames(art: StringName) -> SpriteFrames:
	if _destroy_frames.has(art):
		return _destroy_frames[art]
	var sf := SpriteFrames.new()
	sf.set_animation_loop(&"default", false)
	sf.set_animation_speed(&"default", DESTROY_FPS)
	for i in VARIANTS:
		var at := AtlasTexture.new()
		at.atlas = OBJECTS
		at.region = Rect2(Vector2((VARIANTS + i) * OBJ_CELL, row(art) * OBJ_CELL), Vector2(OBJ_CELL, OBJ_CELL))
		sf.add_frame(&"default", at)
	_destroy_frames[art] = sf
	return sf
