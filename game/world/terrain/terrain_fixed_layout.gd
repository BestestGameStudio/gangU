class_name TerrainFixedLayout
extends Resource
## #396: a hand-designed, fixed terrain map for a dungeon that does not use a
## generator. Terrain is not coupled to generation: assign one of these to a
## TerrainMap's `fixed_layout` and the map is filled from it in _ready.
##
## `rows` is an ASCII picture of the map, one string per grid row; each
## character is one cell. Row 0 / column 0 of the picture is cell `origin`.
## Characters map to tile ids through `legend` (palette ids allowed); any
## character not in the legend - and '.' / ' ' - is plain GROUND.
##
## Default legend:
##   '#' obstacle (wall)   'T' tree      'M' mountain   'B' block (destroyable)
##   '~' water             'g' grass     'm' mud        's' snow     'i' ice
##   'w' tall grass (#461, conceals)

const DEFAULT_LEGEND: Dictionary = {
	"w": TerrainTypes.TALL_GRASS,
	"#": TerrainTypes.OBSTACLE,
	"T": TerrainTypes.TREE,
	"M": TerrainTypes.MOUNTAIN,
	"B": TerrainTypes.BLOCK,
	"~": TerrainTypes.WATER,
	"g": TerrainTypes.GRASS,
	"m": TerrainTypes.MUD,
	"s": TerrainTypes.SNOW,
	"i": TerrainTypes.ICE,
}

@export var origin: Vector2i = Vector2i.ZERO
@export var rows: PackedStringArray = PackedStringArray()
## Extra or overriding char -> tile id entries (e.g. a palette's own tiles).
@export var legend: Dictionary = {}

## The tile id a layout character stands for (GROUND when unmapped).
func type_for(ch: String) -> StringName:
	if legend.has(ch):
		return StringName(legend[ch])
	return DEFAULT_LEGEND.get(ch, TerrainTypes.GROUND)

## Cell -> tile id for every non-GROUND character (the TerrainMap.set_cells
## batch shape).
func cells() -> Dictionary:
	var out := {}
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var type := type_for(row[x])
			if type != TerrainTypes.GROUND:
				out[origin + Vector2i(x, y)] = type
	return out

## Writes the layout into `map` (all-or-nothing, like set_cells). Returns
## false when a character maps to a tile id the map does not know.
func apply(map: TerrainMap) -> bool:
	return map.set_cells(cells())
