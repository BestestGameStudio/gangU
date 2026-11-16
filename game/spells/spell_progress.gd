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

signal upgrades_changed(spell: Spell)
signal cast_progress_changed(spell: Spell)

## Explicit caster wiring (no-group convention from #34).
@export var caster_path: NodePath
## Upgrade rows (one fixed linear chain per spell, #703 - no branch choice).
@export var upgrades: Array[SpellUpgrade] = []

var _cast_counts: Dictionary = {} # Spell -> int, read-only XP observation
var _tiers: Dictionary = {} # Spell -> int tier, written ONLY on successful apply (#36)
var _caster: SpellCaster

func _ready() -> void:
	add_to_group("spell_progress")
	_caster = get_node_or_null(caster_path) as SpellCaster if not caster_path.is_empty() else null
	if _caster != null:
		_caster.spell_cast.connect(_on_spell_cast)

func _on_spell_cast(spell: Spell) -> void:
	_cast_counts[spell] = int(_cast_counts.get(spell, 0)) + 1
	cast_progress_changed.emit(spell)

## Read-only XP observation for one spell (casts this run).
func cast_count(spell: Spell) -> int:
	return int(_cast_counts.get(spell, 0))

## #655: death-carry seams (ProgressionCarry). capture/restore the per-run
## cast XP, applied tiers and boss upgrade tokens verbatim; restore emits so
## the Tab panel follows. Applied upgrade RESULTS ride the caster's inventory
## (the result spell is already unlocked/slotted), so nothing re-applies here.
func capture_run_state() -> Dictionary:
	return {
		"cast_counts": _cast_counts.duplicate(),
		"tiers": _tiers.duplicate(),
		"tokens": _upgrade_tokens,
	}

func restore_run_state(state: Dictionary) -> void:
	_cast_counts = state.get("cast_counts", {})
	_tiers = state.get("tiers", {})
	_upgrade_tokens = int(state.get("tokens", 0))
	tokens_changed.emit(_upgrade_tokens)
	upgrades_changed.emit(null)

## Next upgrade in a spell's fixed linear chain (#703): the single
## SpellUpgrade whose source is `spell`, or null when the spell has none
## (chain finished or no chain). F reads id/display_name off the resource.
func next_upgrade(spell: Spell) -> SpellUpgrade:
	if spell == null:
		return null
	for u in upgrades:
		if u != null and u.source_spell == spell:
			return u
	return null

## #712: read-only full-chain view, including predecessors of an evolved
## spell. Resource identity is the same identity used by next_upgrade/cast XP.
## Guard malformed cycles so menu introspection can never loop forever.
func upgrade_chain(spell: Spell) -> Array[SpellUpgrade]:
	var rows: Array[SpellUpgrade] = []
	if spell == null:
		return rows
	var root_spell := spell
	var visited := {}
	while not visited.has(root_spell):
		visited[root_spell] = true
		var predecessor: SpellUpgrade = null
		for row in upgrades:
			if row != null and row.result_spell == root_spell:
				predecessor = row
				break
		if predecessor == null:
			break
		root_spell = predecessor.source_spell
	visited.clear()
	while root_spell != null and not visited.has(root_spell):
		visited[root_spell] = true
		var row := next_upgrade(root_spell)
		if row == null:
			break
		rows.append(row)
		root_spell = row.result_spell
	return rows

## Three display slots, not three invented upgrades. Missing catalog tiers
## remain unavailable. Progress is casts of THAT row's source / threshold;
## a token can bypass only the current next step, as in can_token_upgrade.
func upgrade_menu(spell: Spell) -> Array[Dictionary]:
	var chain := upgrade_chain(spell)
	var current_index := chain.size()
	for i in chain.size():
		if chain[i].source_spell == spell:
			current_index = i
			break
	var slots: Array[Dictionary] = []
	for tier in range(1, 4):
		var item := {"tier": tier, "upgrade": null, "state": "unavailable", "casts": 0, "threshold": 0, "prerequisite": ""}
		for i in chain.size():
			var row := chain[i]
			if row.tier != tier:
				continue
			item.upgrade = row
			item.casts = cast_count(row.source_spell)
			item.threshold = row.xp_threshold
			if i < current_index:
				item.state = "applied"
			elif i == current_index and can_upgrade(spell):
				item.state = "ready"
			elif i == current_index and can_token_upgrade(spell):
				item.state = "token"
			else:
				item.state = "locked"
				if i > current_index:
					item.prerequisite = row.source_spell.spell_name
			break
		slots.append(item)
	return slots

## Tier of a held spell (#36): 1/2/3 = Specialization/Mastery/Signature,
## 0 = Base or never-upgraded. Written only by a successful apply_upgrade;
## #38's HUD tier display reads this accessor.
func get_tier(spell: Spell) -> int:
	return int(_tiers.get(spell, 0))

func can_upgrade(spell: Spell) -> bool:
	if _caster == null:
		return false
	if spell not in _caster.get_unlocked():
		return false
	var u := next_upgrade(spell)
	return u != null and u.result_spell != null and int(_cast_counts.get(spell, 0)) >= u.xp_threshold

## Refusal-bool. Currently ALWAYS refuses: the replace_spell caster seam is
## Mitra's post-#63 follow-up and has not landed. Once it lands this
## delegates: _caster.replace_spell(u.source_spell, u.result_spell), then
## upgrades_changed.emit(spell). No direct array mutation here ever.
func apply_upgrade(spell: Spell, upgrade_id: StringName) -> bool:
	var u := next_upgrade(spell)
	if u != null and u.id == upgrade_id:
		if _caster == null:
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
##   - one token = one tier step on the spell's fixed chain
##     (no skipping: tier N -> N+1 only, same next upgrade as the cast route);
##   - the token IGNORES the upgrade's cast-count threshold, and is only spent
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

## True when this upgrade is offered only because a token is held: the
## caster has the spell, the upgrade has content, and the cast threshold
## is not met.
func upgrade_needs_token(spell: Spell, u: SpellUpgrade) -> bool:
	return u != null and int(_cast_counts.get(spell, 0)) < u.xp_threshold

## A token could advance this spell one tier right now.
func can_token_upgrade(spell: Spell) -> bool:
	if _upgrade_tokens <= 0 or _caster == null:
		return false
	if spell not in _caster.get_unlocked():
		return false
	var u := next_upgrade(spell)
	return u != null and u.result_spell != null and upgrade_needs_token(spell, u)

## Spend one token on the next chain upgrade through the SAME apply_upgrade -> replace_spell
## route; the token is consumed only when the upgrade actually applies.
func apply_upgrade_with_token(spell: Spell, upgrade_id: StringName) -> bool:
	if _upgrade_tokens <= 0:
		push_warning("SpellProgress: no upgrade token held; refusing.")
		return false
	if _caster == null or spell not in _caster.get_unlocked():
		push_warning("SpellProgress: token target spell not held; refusing.")
		return false
	if not apply_upgrade(spell, upgrade_id):
		return false
	# apply_upgrade already emitted upgrades_changed once (single-emit contract).
	_upgrade_tokens -= 1
	tokens_changed.emit(_upgrade_tokens)
	print("[315] upgrade token spent on ", spell.spell_name, " -> ", upgrade_id, " (", _upgrade_tokens, " left)")
	return true
