class_name OwnedRelics
extends Node
## (#131, foundation C4) The run-scoped owned-relics set. Mounted ONCE on
## Main (same pattern as CurrencyWallet/ReviveSatchel/RewardPool): per-run
## reset comes free from RunManager's full scene reload - there is no reset
## code here and no persistence. An ITEM REVIVE cancels the restart
## interception (run_manager.gd) without a scene reload, so owned relics
## survive a revive exactly like the rest of the run state (Daniel,
## 2026-11-07: relics reset each new run, like the wallet).
##
## DUPLICATES (Daniel, 2026-11-08): "player should not be able to get
## duplicates from any source". add() is the single choke point EVERY
## acquisition path goes through (shop today; drops/rewards later), so the
## rule holds structurally rather than per source.
##
## The passive apply seam: consumers QUERY this set (modifiers_for) and
## build fresh values per call. Nothing here writes player state, so the
## seam cannot go stale.

signal changed

var _owned: Array[Relic] = []

func _ready() -> void:
	add_to_group("owned_relics")

## The universal duplicate gate. Returns false (and changes nothing) when a
## relic with the same logical id is already owned, whatever the source.
func add(relic: Relic) -> bool:
	if relic == null or not relic.is_valid_definition() or has_id(relic.id):
		return false
	_owned.append(relic.duplicate(true) as Relic)
	changed.emit()
	return true

func has_id(relic_id: StringName) -> bool:
	for r in _owned:
		if r.id == relic_id:
			return true
	return false

## A COPY: callers cannot mutate the owned set through the result.
func all() -> Array[Relic]:
	var result: Array[Relic] = []
	for r in _owned:
		result.append(r.duplicate(true) as Relic)
	return result

func count() -> int:
	return _owned.size()

## The passive apply seam: fresh DamageModifier values from each owned
## relic whose hooked_tags intersect the spell's tags and whose payload is
## non-neutral. A generic query - DamageCalc is today's consumer (via
## projectile setup), but nothing here is specific to it.
func modifiers_for(spell: Spell) -> Array[DamageModifier]:
	var out: Array[DamageModifier] = []
	if spell == null:
		return out
	for r in _owned:
		if r.has_neutral_payload():
			continue
		var matched := false
		for t in r.hooked_tags:
			if spell.tags.has(t):
				matched = true
				break
		if matched:
			out.append(r.to_modifier())
	return out

## Generic passive query: returns a summed scalar for a caller-selected
## effect key and tag context. No DamageCalc or summon coupling here.
func query(effect_key: StringName, tags: Array[StringName]) -> float:
	var value := 0.0
	for r in _owned:
		for tag in r.hooked_tags:
			if tags.has(tag):
				value += r.scalar_effects.get(effect_key, 0.0)
				break
	return value
