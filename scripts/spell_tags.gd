class_name SpellTags
## Controlled spell tag vocabulary (#66, approved foundation 2026-11-07).
## Tags are classification metadata; effect parameters live on the spells.
## #37: PIERCING and HOMING are the FIRST behavior-keyed tags, read directly
## by Projectile. Provenance: peer-lead design choices worked under Daniel's
## standing grant for Colin-instinct gangU tasks - NOT owner-picked design,
## and they do not settle the #37 issue. All other tags remain metadata only.

const PROJECTILE: StringName = &"projectile"
const AOE: StringName = &"aoe"
const MELEE: StringName = &"melee"
const BURN: StringName = &"burn"
const MANA: StringName = &"mana"
const PIERCING: StringName = &"piercing"
const HOMING: StringName = &"homing"
## #167: element tag read by the TerrainInteractions registry (cold + water
## tile -> ice). Behavior lives in the rule data, not in this file.
const COLD: StringName = &"cold"
## #331: element tag for the Water Ball tree. Metadata only today.
const WATER: StringName = &"water"

const ALL: Array[StringName] = [PROJECTILE, AOE, MELEE, BURN, MANA, PIERCING, HOMING, COLD, WATER]

static func is_valid(tag: StringName) -> bool:
	return ALL.has(tag)

## Returns the subset of `tags` not in the vocabulary; empty means all known.
static func unknown_tags(tags: Array[StringName]) -> Array[StringName]:
	var out: Array[StringName] = []
	for t in tags:
		if not ALL.has(t):
			out.append(t)
	return out

## Pure query helpers for the future buff-match seam (#66 foundation).
## No ANY-vs-ALL policy is chosen here: the buff system picks the rule when
## it exists. Both are simple membership tests over spell tags.
static func match_any(match_tags: Array[StringName], spell_tags: Array[StringName]) -> bool:
	for t in match_tags:
		if spell_tags.has(t):
			return true
	return false

static func match_all(match_tags: Array[StringName], spell_tags: Array[StringName]) -> bool:
	for t in match_tags:
		if not spell_tags.has(t):
			return false
	return true
