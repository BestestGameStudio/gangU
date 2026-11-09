extends SceneTree
## Season harness: seed -> season determinism and coverage, cosmetic-only
## switching (properties and cell data unchanged), and the drawn atlas
## colors read back from the TileSet texture.

const SIZE := Vector2i(40, 24)
const MAP_SEED := 7
const SEASONS: Array[TerrainSeason.Season] = [
	TerrainSeason.Season.SPRING,
	TerrainSeason.Season.SUMMER,
	TerrainSeason.Season.AUTUMN,
	TerrainSeason.Season.WINTER,
]
const BASE_COLORS: Dictionary = {
	TerrainTypes.GROUND: Color(0.16, 0.24, 0.18, 1.0),
	TerrainTypes.OBSTACLE: Color(0.45, 0.28, 0.22, 1.0),
	TerrainTypes.GRASS: Color(0.36, 0.62, 0.3, 1.0),
	TerrainTypes.TREE: Color(0.1, 0.3, 0.14, 1.0),
	TerrainTypes.SNOW: Color(0.92, 0.94, 0.97, 1.0),
	TerrainTypes.ICE: Color(0.66, 0.88, 0.95, 1.0),
	TerrainTypes.MUD: Color(0.42, 0.3, 0.16, 1.0),
	TerrainTypes.WATER: Color(0.15, 0.4, 0.8, 1.0),
	TerrainTypes.MOUNTAIN: Color(0.5, 0.5, 0.52, 1.0),
	TerrainTypes.BLOCK: Color(0.7, 0.56, 0.34, 1.0),
}
const AUTUMN_GRASS := Color(0.72, 0.45, 0.2, 1.0)
const AUTUMN_TREE := Color(0.55, 0.22, 0.1, 1.0)
const WINTER_GRASS := Color(0.78, 0.84, 0.86, 1.0)

var failures := 0

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[170] ", name, " -> PASS")
	else:
		failures += 1
		print("[170] ", name, " -> FAIL")

func _initialize() -> void:
	_check(TerrainSeason.for_seed(42) == TerrainSeason.for_seed(42), "for_seed deterministic for the same seed")
	_check(TerrainSeason.for_seed(1) == TerrainSeason.Season.SUMMER, "seed 1 is summer")
	_check(TerrainSeason.for_seed(2) == TerrainSeason.Season.AUTUMN, "seed 2 is autumn")
	_check(TerrainSeason.for_seed(3) == TerrainSeason.Season.WINTER, "seed 3 is winter")
	var seen := {}
	for s in range(1, 21):
		seen[TerrainSeason.for_seed(s)] = true
	_check(seen.size() == 4, "all four seasons occur over seeds 1..20")

func _process(_delta: float) -> bool:
	var map := TerrainMap.new()
	root.add_child(map)
	TerrainGen.generate(map, MAP_SEED, SIZE)
	_check(map.season == TerrainSeason.Season.SUMMER, "a new map starts in summer")
	for type: StringName in TerrainTypes.ALL:
		_check(_same(_drawn(map, type), BASE_COLORS[type]), "summer draws the base color for %s" % type)

	var cells_before := _cells(map)
	var props_before := _props(map)
	var ground_before := map.debug_layer_cells(true).size()
	var obstacle_before := map.debug_layer_cells(false).size()
	_check(ground_before > 0 and obstacle_before > 0, "generated map populates both layers")
	for season in SEASONS:
		map.season = season
		var label: String = TerrainSeason.NAMES[season]
		_check(_cells(map) == cells_before, "%s leaves every cell's type unchanged" % label)
		_check(_props(map) == props_before, "%s leaves walkability/speed/friction/tags of every cell unchanged" % label)
		_check(map.debug_layer_cells(true).size() == ground_before, "%s keeps the ground layer cell count" % label)
		_check(map.debug_layer_cells(false).size() == obstacle_before, "%s keeps the obstacle layer cell count" % label)

	map.season = TerrainSeason.Season.AUTUMN
	_check(_same(_drawn(map, TerrainTypes.GRASS), AUTUMN_GRASS), "autumn draws GRASS orange-brown")
	_check(_same(_drawn(map, TerrainTypes.TREE), AUTUMN_TREE), "autumn draws TREE rust")
	_check(_same(_drawn(map, TerrainTypes.SNOW), BASE_COLORS[TerrainTypes.SNOW]), "autumn keeps the base SNOW color")
	map.season = TerrainSeason.Season.WINTER
	_check(_same(_drawn(map, TerrainTypes.GRASS), WINTER_GRASS), "winter draws GRASS pale frost")
	map.season = TerrainSeason.Season.SUMMER
	_check(_same(_drawn(map, TerrainTypes.GRASS), BASE_COLORS[TerrainTypes.GRASS]), "back to summer restores the base GRASS color")

	print("[170] ", "ALL PASS" if failures == 0 else "%d FAILED" % failures)
	quit(0 if failures == 0 else 1)
	return true

## Samples the center pixel of the type's atlas column in the texture the
## layers actually draw from.
func _drawn(map: TerrainMap, type: StringName) -> Color:
	var layer := map.get_node("Ground") as TileMapLayer
	var src := layer.tile_set.get_source(0) as TileSetAtlasSource
	var img := src.texture.get_image()
	var cs := map.cell_size
	var col := TerrainTypes.ALL.find(type)
	return img.get_pixel(col * cs + cs / 2, cs / 2)

func _cells(map: TerrainMap) -> Array[StringName]:
	var out: Array[StringName] = []
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			out.append(map.tile_type_at_cell(Vector2i(x, y)))
	return out

func _props(map: TerrainMap) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			out.append(map.properties_at(map.cell_to_world(Vector2i(x, y))))
	return out

## The atlas is RGBA8, so a drawn channel can sit one 8-bit step from the
## float literal.
func _same(drawn: Color, want: Color) -> bool:
	return absf(drawn.r - want.r) <= 1.0 / 255.0 and absf(drawn.g - want.g) <= 1.0 / 255.0 \
		and absf(drawn.b - want.b) <= 1.0 / 255.0 and drawn.a == want.a
