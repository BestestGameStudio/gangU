class_name TerrainInteraction
extends Resource
## #167 (Terrain B1): one spell -> terrain interaction rule, pure data.
## A spell carrying `spell_tag` (SpellTags vocabulary) that hits a tile
## carrying `tile_tag` (a TerrainTypes element tag) turns that tile into
## `result_type`. Rules are matched by tags only - never by spell name or
## tile id - so a new interaction is a new .tres in the
## TerrainInteractions registry, not new code.
##
## `consumes_projectile`: when true a non-piercing projectile stops on the
## first cell it transforms; when false (the default) it keeps flying and
## transforms every matching cell along its path.

@export var id: StringName = &""
@export var spell_tag: StringName = &""
@export var tile_tag: StringName = &""
@export var result_type: StringName = &""
@export var consumes_projectile: bool = false

## True iff this rule fires for a spell with `spell_tags` hitting a tile
## with `tile_tags`.
func matches(spell_tags: Array, tile_tags: Array) -> bool:
	return spell_tag != &"" and tile_tag != &"" and spell_tags.has(spell_tag) and tile_tags.has(tile_tag)

## Human-readable problems; empty means the rule is usable.
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == &"":
		errors.append("interaction with an empty id")
	if not SpellTags.is_valid(spell_tag):
		errors.append("'%s': unknown spell tag '%s'" % [id, spell_tag])
	if tile_tag == &"":
		errors.append("'%s': empty tile tag" % id)
	if not TerrainTypes.is_valid(result_type):
		errors.append("'%s': unknown result type '%s'" % [id, result_type])
	elif TerrainTypes.element_tags(result_type).has(tile_tag):
		errors.append("'%s': result '%s' still carries '%s' (rule would re-fire)" % [id, result_type, tile_tag])
	return errors
