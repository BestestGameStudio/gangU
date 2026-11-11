class_name DungeonCatalog
extends RefCounted
## #512: every DungeonDefinition, looked up by area root name. Adding a
## dungeon = a .tres in data/dungeons/ plus one path in PATHS.

const PATHS: Array[String] = [
	"res://data/dungeons/dungeon_a.tres",
	"res://data/dungeons/dungeon_b.tres",
	"res://data/dungeons/dungeon_c.tres",
	"res://data/dungeons/dungeon_d.tres",
	"res://data/dungeons/dungeon_e.tres",
	"res://data/dungeons/dungeon_maze.tres",
]

static var _loaded: Array[DungeonDefinition] = []

## Loaded on first use (not preloaded: DungeonDefinition names DungeonObjective,
## and Main preloads this script).
static func definitions() -> Array[DungeonDefinition]:
	if _loaded.is_empty():
		for p in PATHS:
			_loaded.append(load(p) as DungeonDefinition)
	return _loaded

## The definition of the area whose root node is named `area_name`, or null
## (hub, overworld, generated and test areas have none).
static func for_name(area_name: StringName) -> DungeonDefinition:
	for d: DungeonDefinition in definitions():
		if d.area_name == area_name:
			return d
	return null

static func for_area(area: Node) -> DungeonDefinition:
	return for_name(area.name) if area != null else null
