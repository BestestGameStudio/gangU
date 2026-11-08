class_name TerrainTypes
## Tile-type data model: the controlled vocabulary of terrain types and
## their pure data properties. GROUND and OBSTACLE are the flat-map
## foundation; GRASS/TREE (grass/forest biome) and SNOW/ICE (snow/ice biome)
## are the generated biome types. Element tags are classification metadata
## (the SpellTags #66 idiom): they describe, nothing executes them yet.
## MUD/WATER/MOUNTAIN are placeable movement types the generator does not
## emit yet. friction 1.0 is full grip; swimmable lets a swim-capable mover
## enter a non-walkable cell, where speed_multiplier is its swim speed.
## A destroyable type turns into its destroyed_into type when any damage
## hits it.
##
## #266: every type carries a movement category. WALKABLE is ground a mover
## can cross; BLOCKING cannot be entered (walls, forest, mountains; a
## swimmable BLOCKING type still admits swimmers); FALLING is pits/cliffs
## and for now is never entered by anything, swimmers included. FALLING is
## kept separate so a later issue can give it its own outcome. "walkable"
## in properties() is derived: movement == WALKABLE.
##
## Authority split: TerrainMap owns cell -> type assignments; this registry
## owns type -> properties. Downstream issues (A2/A4/B1/B3/C1/C2) consume
## ONLY the TerrainMap lookup seam built on this registry, never TileMap
## internals and never this file's DEFS directly.

enum Movement { WALKABLE, BLOCKING, FALLING }

const MOVEMENT_NAMES: Dictionary = {
	Movement.WALKABLE: "walkable",
	Movement.BLOCKING: "blocking",
	Movement.FALLING: "falling",
}

const GROUND: StringName = &"ground"
const OBSTACLE: StringName = &"obstacle"
const GRASS: StringName = &"grass"
const TREE: StringName = &"tree"
const SNOW: StringName = &"snow"
const ICE: StringName = &"ice"
const MUD: StringName = &"mud"
const WATER: StringName = &"water"
const MOUNTAIN: StringName = &"mountain"

## Placeable type vocabulary.
const ALL: Array[StringName] = [GROUND, OBSTACLE, GRASS, TREE, SNOW, ICE, MUD, WATER, MOUNTAIN]

## type -> properties. Data only; no behavior lives here.
const DEFS: Dictionary = {
	GROUND: {
		"movement": Movement.WALKABLE,
		"speed_multiplier": 1.0,
		"friction": 1.0,
		"swimmable": false,
		"destroyable": false,
		"destroyed_into": &"",
		"element_tags": [],
	},
	OBSTACLE: {
		"movement": Movement.BLOCKING,
		"speed_multiplier": 0.0,
		"friction": 1.0,
		"swimmable": false,
		"destroyable": false,
		"destroyed_into": &"",
		"element_tags": [],
	},
	GRASS: {
		"movement": Movement.WALKABLE,
		"speed_multiplier": 1.0,
		"friction": 1.0,
		"swimmable": false,
		"destroyable": false,
		"destroyed_into": &"",
		"element_tags": [],
	},
	TREE: {
		"movement": Movement.BLOCKING,
		"speed_multiplier": 0.0,
		"friction": 1.0,
		"swimmable": false,
		"destroyable": true,
		"destroyed_into": GRASS,
		"element_tags": [],
	},
	SNOW: {
		"movement": Movement.WALKABLE,
		"speed_multiplier": 1.0,
		"friction": 1.0,
		"swimmable": false,
		"destroyable": false,
		"destroyed_into": &"",
		"element_tags": [],
	},
	ICE: {
		"movement": Movement.WALKABLE,
		"speed_multiplier": 1.0,
		"friction": 0.12,
		"swimmable": false,
		"destroyable": false,
		"destroyed_into": &"",
		"element_tags": [&"ice"],
	},
	MUD: {
		"movement": Movement.WALKABLE,
		"speed_multiplier": 0.5,
		"friction": 1.0,
		"swimmable": false,
		"destroyable": false,
		"destroyed_into": &"",
		"element_tags": [],
	},
	WATER: {
		"movement": Movement.BLOCKING,
		"speed_multiplier": 0.6,
		"friction": 1.0,
		"swimmable": true,
		"destroyable": false,
		"destroyed_into": &"",
		"element_tags": [&"water"],
	},
	MOUNTAIN: {
		"movement": Movement.BLOCKING,
		"speed_multiplier": 0.0,
		"friction": 1.0,
		"swimmable": false,
		"destroyable": false,
		"destroyed_into": &"",
		"element_tags": [],
	},
}

## Safe fallback for an UNREGISTERED type id: never walkable, never a speed
## bonus, no tags. Unknown types BLOCK - downstream must never guess.
const UNKNOWN_PROPS: Dictionary = {
	"movement": Movement.BLOCKING,
	"speed_multiplier": 0.0,
	"friction": 1.0,
	"swimmable": false,
	"destroyable": false,
	"destroyed_into": &"",
	"element_tags": [],
}

static func is_valid(type: StringName) -> bool:
	return ALL.has(type)

## A fresh copy of the type's properties; unknown ids get the blocking
## fallback. Callers may mutate the result - the registry is unaffected.
static func properties(type: StringName) -> Dictionary:
	var src: Dictionary = DEFS.get(type, UNKNOWN_PROPS)
	return {
		"movement": src["movement"],
		"walkable": src["movement"] == Movement.WALKABLE,
		"speed_multiplier": src["speed_multiplier"],
		"friction": src["friction"],
		"swimmable": src["swimmable"],
		"destroyable": src["destroyable"],
		"destroyed_into": src["destroyed_into"],
		"element_tags": (src["element_tags"] as Array).duplicate(),
	}

static func is_walkable(type: StringName) -> bool:
	return properties(type)["walkable"]

static func movement(type: StringName) -> Movement:
	return properties(type)["movement"]

## Applies a movement category to a property set in place, keeping the
## derived fields consistent: "walkable" follows the category, a FALLING
## tile is never swimmable, and a WALKABLE tile never has zero speed.
static func apply_movement(props: Dictionary, category: Movement) -> void:
	props["movement"] = category
	props["walkable"] = category == Movement.WALKABLE
	if category == Movement.FALLING:
		props["swimmable"] = false
	if category == Movement.WALKABLE and float(props["speed_multiplier"]) <= 0.0:
		props["speed_multiplier"] = 1.0

static func speed_multiplier(type: StringName) -> float:
	return properties(type)["speed_multiplier"]

static func friction(type: StringName) -> float:
	return properties(type)["friction"]

static func is_swimmable(type: StringName) -> bool:
	return properties(type)["swimmable"]

static func is_destroyable(type: StringName) -> bool:
	return properties(type)["destroyable"]

## The type a destroyed tile becomes; empty for a non-destroyable type.
static func destroyed_into(type: StringName) -> StringName:
	return properties(type)["destroyed_into"]

static func element_tags(type: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(properties(type)["element_tags"])
	return out
