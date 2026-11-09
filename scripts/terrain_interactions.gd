class_name TerrainInteractions
## #167 (Terrain B1): the spell -> terrain interaction registry and its
## dispatch. Rules are TerrainInteraction resources listed in RULE_PATHS; the
## dispatcher picks the FIRST rule whose spell tag is on the spell and whose
## tile tag is on the tile (list order = priority). Nothing here knows about
## any specific element: freezing water is just the first entry.
##
## Callers go through TerrainMap.interact_cell / interaction_for_cell, which
## read the tile's element tags through the palette-aware lookup seam.
##
## The rule files are loaded lazily at first use rather than preloaded into a
## const: a const preload here resolves while scripts are still compiling
## (e.g. when a scene pulls in TerrainMap) and hands back script-less
## Resources.

const RULE_PATHS: Array[String] = [
	"res://resources/terrain_interactions/freeze_water.tres",
]

static var _rules: Array[TerrainInteraction] = []
static var _loaded := false

## The shared registry, in priority order.
static func rules() -> Array[TerrainInteraction]:
	if not _loaded:
		_loaded = true
		for path in RULE_PATHS:
			var r := load(path) as TerrainInteraction
			if r == null:
				push_error("TerrainInteractions: '%s' is not a TerrainInteraction" % path)
				continue
			_rules.append(r)
	return _rules

## The first rule in `list` (default: the shared registry) that fires for a
## spell with `spell_tags` hitting a tile with `tile_tags`, or null.
static func find(spell_tags: Array, tile_tags: Array, list: Array[TerrainInteraction] = []) -> TerrainInteraction:
	if spell_tags.is_empty() or tile_tags.is_empty():
		return null
	for r in (list if not list.is_empty() else rules()):
		if r != null and r.matches(spell_tags, tile_tags):
			return r
	return null

## Every problem across `list` (default: the shared registry); empty = usable.
static func validate(list: Array[TerrainInteraction] = []) -> PackedStringArray:
	var errors := PackedStringArray()
	var seen := {}
	var src := list if not list.is_empty() else rules()
	if list.is_empty() and src.size() != RULE_PATHS.size():
		errors.append("registry failed to load every rule file")
	for r in src:
		if r == null:
			errors.append("null interaction rule")
			continue
		errors.append_array(r.validate())
		if seen.has(r.id):
			errors.append("duplicate interaction id '%s'" % r.id)
		seen[r.id] = true
	return errors
