class_name TerrainTypes
## Tile-type data model: the controlled vocabulary of terrain types and
## their pure data properties. GROUND and OBSTACLE are the flat-map
## foundation; GRASS/TREE (grass/forest biome) and SNOW/ICE (snow/ice biome)
## are the generated biome types. Element tags are classification metadata
## (the SpellTags #66 idiom): they describe, nothing executes them yet.
## ICE friction is a movement rule, so its speed stays 1.0 here.
##
## Authority split: TerrainMap owns cell -> type assignments; this registry
## owns type -> properties. Downstream issues (A2/A4/B1/B3/C1/C2) consume
## ONLY the TerrainMap lookup seam built on this registry, never TileMap
## internals and never this file's DEFS directly.

const GROUND: StringName = &"ground"
const OBSTACLE: StringName = &"obstacle"
const GRASS: StringName = &"grass"
const TREE: StringName = &"tree"
const SNOW: StringName = &"snow"
const ICE: StringName = &"ice"

## Placeable type vocabulary.
const ALL: Array[StringName] = [GROUND, OBSTACLE, GRASS, TREE, SNOW, ICE]

## type -> properties. Data only; no behavior lives here.
const DEFS: Dictionary = {
	GROUND: {
		"walkable": true,
		"speed_multiplier": 1.0,
		"element_tags": [],
	},
	OBSTACLE: {
		"walkable": false,
		"speed_multiplier": 0.0,
		"element_tags": [],
	},
	GRASS: {
		"walkable": true,
		"speed_multiplier": 1.0,
		"element_tags": [],
	},
	TREE: {
		"walkable": false,
		"speed_multiplier": 0.0,
		"element_tags": [],
	},
	SNOW: {
		"walkable": true,
		"speed_multiplier": 1.0,
		"element_tags": [],
	},
	ICE: {
		"walkable": true,
		"speed_multiplier": 1.0,
		"element_tags": [&"ice"],
	},
}

## Safe fallback for an UNREGISTERED type id: never walkable, never a speed
## bonus, no tags. Unknown types BLOCK - downstream must never guess.
const UNKNOWN_PROPS: Dictionary = {
	"walkable": false,
	"speed_multiplier": 0.0,
	"element_tags": [],
}

static func is_valid(type: StringName) -> bool:
	return ALL.has(type)

## A fresh copy of the type's properties; unknown ids get the blocking
## fallback. Callers may mutate the result - the registry is unaffected.
static func properties(type: StringName) -> Dictionary:
	var src: Dictionary = DEFS.get(type, UNKNOWN_PROPS)
	return {
		"walkable": src["walkable"],
		"speed_multiplier": src["speed_multiplier"],
		"element_tags": (src["element_tags"] as Array).duplicate(),
	}

static func is_walkable(type: StringName) -> bool:
	return properties(type)["walkable"]

static func speed_multiplier(type: StringName) -> float:
	return properties(type)["speed_multiplier"]

static func element_tags(type: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(properties(type)["element_tags"])
	return out
