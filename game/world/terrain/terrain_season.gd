class_name TerrainSeason
## A dungeon's season: cosmetic only. It recolors tiles and never changes
## walkability, speed, friction or element tags. Fixed per dungeon, derived
## from the map seed.

enum Season { SPRING, SUMMER, AUTUMN, WINTER }

const NAMES: Dictionary = {
	Season.SPRING: "spring",
	Season.SUMMER: "summer",
	Season.AUTUMN: "autumn",
	Season.WINTER: "winter",
}

## Season -> { type -> Color }, listing only the types a season recolors.
## SUMMER is the base TerrainMap.TYPE_COLORS.
const PALETTES: Dictionary = {
	Season.SPRING: {
		TerrainTypes.GRASS: Color(0.45, 0.78, 0.36, 1.0),
		TerrainTypes.TREE: Color(0.16, 0.42, 0.2, 1.0),
	},
	Season.SUMMER: {},
	Season.AUTUMN: {
		TerrainTypes.GRASS: Color(0.72, 0.45, 0.2, 1.0),
		TerrainTypes.TREE: Color(0.55, 0.22, 0.1, 1.0),
	},
	Season.WINTER: {
		TerrainTypes.GRASS: Color(0.78, 0.84, 0.86, 1.0),
		TerrainTypes.TREE: Color(0.1, 0.22, 0.26, 1.0),
		TerrainTypes.WATER: Color(0.3, 0.45, 0.65, 1.0),
	},
}

## Salted string hash so the season stays independent of the generator's
## noise seeds (map_seed and map_seed + 1).
static func for_seed(map_seed: int) -> Season:
	return posmod(hash("season:%d" % map_seed), Season.size()) as Season

static func color(season: Season, type: StringName) -> Color:
	var palette: Dictionary = PALETTES[season]
	return palette.get(type, TerrainMap.TYPE_COLORS.get(type, TerrainMap.DEFAULT_TILE_COLOR))

## Parses "spring" | "summer" | "autumn" | "winter"; -1 for anything else.
static func from_name(season_name: String) -> int:
	for s: Season in NAMES:
		if NAMES[s] == season_name:
			return s
	return -1
