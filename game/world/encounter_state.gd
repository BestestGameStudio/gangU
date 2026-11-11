class_name EncounterState
extends Node
## #549 (Stage 1): the run's encounter clear records and the sole truth for
## "has this encounter been cleared this run". One private Dictionary; no
## save, no static or autoload state, no duplicate copies anywhere else.
##
## Owned by the run: Stage 2 mounts one EncounterState under the run-owned
## AreaLoader; nothing reads it yet. The full Main reload at player death
## resets the records for free. Hub and region travel must NOT reset them.
##
## Keyed by the existing completable dungeon ids (data/dungeons/*.tres on
## main: dungeon_a, dungeon_b, dungeon_c, dungeon_d, dungeon_e,
## dungeon_maze) so Stage 2's fast-travel and cleared-mark consumers keep
## their ids unchanged. No dependency on DungeonObjective, scenes, UI or
## the loader.

## Emitted only when an encounter clears for the first time this run.
signal encounter_cleared(dungeon_id: StringName)

## dungeon_id -> true. The only copy of the clear records; everything else
## asks this node.
var _cleared: Dictionary = {}


func is_cleared(dungeon_id: StringName) -> bool:
	return _cleared.has(dungeon_id)


func cleared_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: StringName in _cleared:
		ids.append(id)
	return ids


## Marks `dungeon_id` cleared. Returns true on the first clear this run
## (and emits encounter_cleared); false when it was already cleared.
func complete(dungeon_id: StringName) -> bool:
	if _cleared.has(dungeon_id):
		return false
	_cleared[dungeon_id] = true
	encounter_cleared.emit(dungeon_id)
	return true


## Drops every clear record. For the death/fixture adapter only; hub and
## region travel must never call this (records persist for the run).
func reset_run() -> void:
	_cleared.clear()
