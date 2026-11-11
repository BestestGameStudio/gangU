extends SceneTree
## #549 Stage 1: EncounterState clear-record semantics. complete() returns
## the first-clear bool and emits encounter_cleared on the first clear only,
## cleared_ids() reflects the records, reset_run() drops them. Pure: no
## scenes, no loader, no DungeonObjective.

var failures := 0


func _check(cond: bool, name: String) -> void:
	if not cond:
		failures += 1
	print("[549] ", name, " -> ", "PASS" if cond else "FAIL")


func _initialize() -> void:
	var es := EncounterState.new()
	var emitted: Array[StringName] = []
	es.encounter_cleared.connect(func(id: StringName) -> void: emitted.append(id))

	_check(not es.is_cleared(&"dungeon_a"), "uncleared before complete")
	_check(es.cleared_ids().is_empty(), "no ids before complete")

	_check(es.complete(&"dungeon_a"), "first complete returns true")
	_check(es.is_cleared(&"dungeon_a"), "cleared after complete")
	_check(es.cleared_ids() == [&"dungeon_a"], "cleared_ids lists dungeon_a")
	_check(emitted == [&"dungeon_a"], "encounter_cleared emitted on first clear")

	_check(not es.complete(&"dungeon_a"), "repeat complete returns false")
	_check(emitted.size() == 1, "no emission on repeat clear")

	_check(es.complete(&"dungeon_maze"), "second id is its own first clear")
	_check(es.cleared_ids().size() == 2, "two cleared ids")
	_check(emitted.size() == 2, "second id emitted")

	es.reset_run()
	_check(not es.is_cleared(&"dungeon_a"), "reset_run drops records")
	_check(es.cleared_ids().is_empty(), "cleared_ids empty after reset")
	_check(es.complete(&"dungeon_a"), "clear after reset is a first clear again")
	_check(emitted.size() == 3, "emission after reset")

	es.free()
	print("RESULT: ", "FAIL" if failures > 0 else "PASS")
	quit(1 if failures > 0 else 0)
