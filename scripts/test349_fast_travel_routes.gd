extends SceneTree
## #349 preparation harness: stateless route catalog only. Production
## travel/return eligibility awaits #353 integration and the owner rule.
var failures := 0

func _check(ok: bool, label: String) -> void:
	print("[349 routes] ", label, " -> ", "PASS" if ok else "FAIL")
	if not ok:
		failures += 1

func _initialize() -> void:
	var empty: Array[StringName] = []
	var cleared: Array[StringName] = [&"dungeon_a", &"dungeon_c", &"dungeon_a", &"unknown"]
	_check(FastTravelRoutes.destinations(empty).is_empty(), "fresh run has no destination")
	_check(FastTravelRoutes.destinations(cleared) == [&"dungeon_a", &"dungeon_c"], "known cleared IDs only, stable and unique")
	_check(FastTravelRoutes.scene_from_hub(true, &"dungeon_a", cleared) == "res://scenes/dungeon_a.tscn", "hub to cleared dungeon")
	_check(FastTravelRoutes.scene_from_hub(true, &"dungeon_b", cleared) == "", "uncleared dungeon denied")
	_check(FastTravelRoutes.scene_from_hub(true, &"unknown", cleared) == "", "unknown dungeon denied even in supplied IDs")
	_check(FastTravelRoutes.scene_from_hub(false, &"dungeon_a", cleared) == "", "non-hub origin cannot select a dungeon")
	_check(FastTravelRoutes.scene_from_hub(true, &"dungeon_a", empty) == "", "selection rechecks cleared IDs after reset")
	for id: StringName in FastTravelRoutes.DUNGEONS:
		var ids: Array[StringName] = [id]
		_check(ResourceLoader.exists(FastTravelRoutes.scene_from_hub(true, id, ids)), "production scene exists for " + str(id))
		_check(not FastTravelRoutes.label_for(id).is_empty(), "destination has label " + str(id))
	_check(FastTravelRoutes.label_for(&"unknown") == "", "no fabricated label for unknown ID")
	_check(FastTravelRoutes.is_safe_area(false, false), "safe area has neither enemies nor spawn capability")
	_check(not FastTravelRoutes.is_safe_area(true, false), "enemy present denies safe origin")
	_check(not FastTravelRoutes.is_safe_area(false, true), "empty but spawn-capable area is not safe")
	_check(not FastTravelRoutes.is_safe_area(true, true), "populated spawn-capable area is not safe")
	print("[349 routes] failures=", failures)
	quit(1 if failures else 0)
