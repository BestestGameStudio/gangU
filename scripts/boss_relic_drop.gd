class_name BossRelicDrop
extends RefCounted
## (#426) Boss relic drops. Daniel, 2026-11-09: "add a relic that has a chance
## to be dropped by a boss" / "dash twice is two charges, any boss, drop
## chance 50%".
##
## "Any boss" = any Enemy in the "boss" group when it dies (DungeonObjective
## adds every spawned boss to it; hand-placed bosses carry it in the scene).
## The roll is made per boss kill, ON TOP of the boss's own reward table
## (the upgrade token is unaffected). A relic the player already owns is not
## rolled, so the 50% only applies while it is still missing; owned-relic
## uniqueness itself stays in OwnedRelics.add (the universal gate).
##
## Persistence follows the existing relic rule (owned_relics.gd): relics are
## run-scoped and reset with the run. Nothing new is persisted here.

## Chance per boss kill. A static var (not const) only so harnesses can force
## the roll; production code never writes it.
static var drop_chance: float = 0.5

## Relics a boss can drop. One today; the roll picks uniformly among the ones
## the player does not own yet.
const RELICS: Array[Relic] = [preload("res://resources/relics/twin_dash.tres")]

## Returns the relic to drop for this boss kill, or null for no drop.
## `roll` is a uniform [0, 1) sample (randf() in production).
static func pick(owned: OwnedRelics, roll: float) -> Relic:
	if owned == null or roll >= drop_chance:
		return null
	var candidates: Array[Relic] = []
	for r in RELICS:
		if not owned.has_id(r.id):
			candidates.append(r)
	if candidates.is_empty():
		return null
	return candidates[randi() % candidates.size()]

## Builds the ground-pickup entry for a relic (RewardDrop renders/grants it).
static func entry_for(relic: Relic) -> RewardEntry:
	var e := RewardEntry.new()
	e.kind = RewardEntry.Kind.RELIC
	e.relic = relic
	return e
