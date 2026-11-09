class_name SpellProgress
extends Node
## Spell progression provider (for F's panel, #62; upgrades per Daniel
## 2026-11-07: manual, via the shared Tab panel, no pause). F consumes this
## API; a missing provider leaves F inert (pinned interop).
##
## READ/API ONLY: no caster array mutation anywhere. apply_upgrade is a
## refusal-bool and stays REFUSING until B's replace_spell follow-up (Mitra,
## post-#63) lands with its final edge semantics; then it delegates to the
## caster atomically. XP is observed READ-ONLY from the caster's spell_cast
## signal - no XP spending or qualification policy is invented here.

signal upgrades_changed(spell)

## Explicit caster wiring (no-group convention from #34).
@export var caster_path: NodePath
## Available upgrade paths. Contents beyond the approved placeholder paths
## are human-open.
@export var upgrades: Array[SpellUpgrade] = []

var _cast_counts: Dictionary = {} # Spell -> int, read-only XP observation
var _tiers: Dictionary = {} # Spell -> int tier, written ONLY on successful apply (#36)
var _caster: Node

func _ready() -> void:
	add_to_group("spell_progress")
	_caster = get_node_or_null(caster_path) if not caster_path.is_empty() else null
	if _caster != null and _caster.has_signal("spell_cast"):
		_caster.spell_cast.connect(_on_spell_cast)

func _on_spell_cast(spell: Spell) -> void:
	_cast_counts[spell] = int(_cast_counts.get(spell, 0)) + 1

## Read-only XP observation for one spell (casts this run).
func cast_count(spell: Spell) -> int:
	return int(_cast_counts.get(spell, 0))

## Upgrade paths offered for a spell: [{id, name}] per the pinned provider
## shape; returns full SpellUpgrade resources, F reads id/display_name.
func get_upgrade_paths(spell: Spell) -> Array[SpellUpgrade]:
	var out: Array[SpellUpgrade] = []
	if spell == null or route_taken(spell):
		return out
	for u in upgrades:
		if u != null and u.source_spell == spell:
			out.append(u)
	return out

## #331: Water Ball alone uses ONE progression route. Once the
## player holds any upgrade descended from `spell` (e.g. Guided Water Ball
## from Water Ball), that spell's other branches stay closed, even if a
## second copy of the base is looted later. Other spell trees keep their
## existing duplicate-copy behavior. False without a caster.
func route_taken(spell: Spell) -> bool:
	if _caster == null or not _caster.has_method("get_unlocked"):
		return false
	var parent_of: Dictionary = {} # result Spell -> source Spell
	for u in upgrades:
		if u != null and u.result_spell != null and u.source_spell != null:
			parent_of[u.result_spell] = u.source_spell
	# Scope the owner-requested rule to the actual Water Ball resource and
	# its descendants, not spell names or unrelated upgrade trees.
	var water_base: Spell = load("res://resources/spells/water_ball.tres")
	var ancestor := spell
	var water_tree := ancestor == water_base
	for _i in 16:
		if water_tree or not parent_of.has(ancestor):
			break
		ancestor = parent_of[ancestor]
		water_tree = ancestor == water_base
	if not water_tree:
		return false
	for held in _caster.get_unlocked():
		if held == spell:
			continue
		var cur: Spell = held
		for _i in 16: # trees are 3 tiers deep; the cap only guards bad data
			if not parent_of.has(cur):
				break
			cur = parent_of[cur]
			if cur == spell:
				return true
	return false

## Tier of a held spell (#36): 1/2/3 = Specialization/Mastery/Signature,
## 0 = Base or never-upgraded. Written only by a successful apply_upgrade;
## #38's HUD tier display reads this accessor.
func get_tier(spell: Spell) -> int:
	return int(_tiers.get(spell, 0))

func can_upgrade(spell: Spell) -> bool:
	if _caster == null or not _caster.has_method("get_unlocked"):
		return false
	if spell not in _caster.get_unlocked():
		return false
	for u in get_upgrade_paths(spell):
		if u.result_spell != null and int(_cast_counts.get(spell, 0)) >= u.xp_threshold:
			return true
	return false

## Refusal-bool. Currently ALWAYS refuses: the replace_spell caster seam is
## Mitra's post-#63 follow-up and has not landed. Once it lands this
## delegates: _caster.replace_spell(u.source_spell, u.result_spell), then
## upgrades_changed.emit(spell). No direct array mutation here ever.
func apply_upgrade(spell: Spell, upgrade_id: StringName) -> bool:
	if route_taken(spell):
		push_warning("SpellProgress: a route from %s is already taken; refusing '%s'." % [spell, upgrade_id])
		return false
	for u in get_upgrade_paths(spell):
		if u.id == upgrade_id:
			if _caster == null or not _caster.has_method("replace_spell"):
				push_warning("SpellProgress: replace_spell seam not landed yet (Mitra post-#63 follow-up); refusing.")
				return false
			if u.result_spell == null:
				push_warning("SpellProgress: placeholder upgrade has no result_spell content yet; refusing.")
				return false
			var ok: bool = _caster.replace_spell(u.source_spell, u.result_spell)
			if ok:
				# #36: record tier ON successful apply only. The result
				# instance becomes the tier source of truth; the consumed
				# source drops back to Base (0).
				_tiers.erase(u.source_spell)
				_tiers[u.result_spell] = u.tier
				upgrades_changed.emit(spell)
			return ok
	push_warning("SpellProgress: unknown upgrade id '%s' for %s." % [upgrade_id, spell])
	return false

## --- #315 boss upgrade token ------------------------------------------------
## Daniel 2026-11-08: "a special upgrade token item dropped only by the boss, it
## can upgrade a spell by one tier". Run-scoped count (reset free with the
## RunManager reload). PROVISIONAL mechanics, all open human choices:
##   - one token = one tier step on ONE upgrade path the spell already offers
##     (no skipping: tier N -> N+1 only, same paths as the cast route);
##   - the token IGNORES the path's cast-count threshold, and is only spent
##     when that threshold is NOT yet met (a qualified spell uses the free
##     cast route, so a token is never wasted);
##   - cast counts are left untouched (the result spell starts its own count
##     at 0, exactly like the cast route).

signal tokens_changed(count: int)

var _upgrade_tokens: int = 0

func upgrade_tokens() -> int:
	return _upgrade_tokens

## Called by the boss drop on pickup (RewardEntry.Kind.UPGRADE_TOKEN).
func add_upgrade_token(n: int = 1) -> void:
	if n <= 0:
		return
	_upgrade_tokens += n
	tokens_changed.emit(_upgrade_tokens)
	upgrades_changed.emit(null)

## True when this path is offered only because a token is held: the caster
## has the spell, the path has content, and the cast threshold is not met.
func path_needs_token(spell: Spell, u: SpellUpgrade) -> bool:
	return u != null and int(_cast_counts.get(spell, 0)) < u.xp_threshold

## A token could advance this spell one tier right now.
func can_token_upgrade(spell: Spell) -> bool:
	if _upgrade_tokens <= 0 or _caster == null or not _caster.has_method("get_unlocked"):
		return false
	if spell not in _caster.get_unlocked():
		return false
	for u in get_upgrade_paths(spell):
		if u.result_spell != null and path_needs_token(spell, u):
			return true
	return false

## Spend one token on one path through the SAME apply_upgrade -> replace_spell
## route; the token is consumed only when the upgrade actually applies.
func apply_upgrade_with_token(spell: Spell, upgrade_id: StringName) -> bool:
	if _upgrade_tokens <= 0:
		push_warning("SpellProgress: no upgrade token held; refusing.")
		return false
	if _caster == null or not _caster.has_method("get_unlocked") or spell not in _caster.get_unlocked():
		push_warning("SpellProgress: token target spell not held; refusing.")
		return false
	if not apply_upgrade(spell, upgrade_id):
		return false
	# apply_upgrade already emitted upgrades_changed once (single-emit contract).
	_upgrade_tokens -= 1
	tokens_changed.emit(_upgrade_tokens)
	print("[315] upgrade token spent on ", spell.spell_name, " -> ", upgrade_id, " (", _upgrade_tokens, " left)")
	return true
