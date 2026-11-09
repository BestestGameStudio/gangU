class_name FastTravelRoutes
extends RefCounted
## #349: stateless catalog for confirmed hub -> cleared-dungeon routes.
## The caller supplies IDs from the canonical clear record (#353). This
## object never remembers clears, chooses safe areas, or decides whether a
## previously cleared dungeon may return during a new encounter.

const HUB_SCENE := "res://scenes/hub.tscn"
const DUNGEONS := {
	&"dungeon_a": {"label": "Dungeon A", "scene": "res://scenes/dungeon_a.tscn"},
	&"dungeon_b": {"label": "Dungeon B", "scene": "res://scenes/dungeon_b.tscn"},
	&"dungeon_c": {"label": "Dungeon C", "scene": "res://scenes/dungeon_c.tscn"},
	&"dungeon_d": {"label": "Beast's Den", "scene": "res://scenes/dungeon_d.tscn"},
	&"dungeon_e": {"label": "Defense", "scene": "res://scenes/dungeon_e.tscn"},
	&"dungeon_maze": {"label": "Maze Defense", "scene": "res://scenes/dungeon_maze.tscn"},
}

## Stable catalog order, no duplicates or unknown destinations. The
## generated dungeon currently has no completable objective/clear ID.
static func destinations(cleared_ids: Array[StringName]) -> Array[StringName]:
	var result: Array[StringName] = []
	for id: StringName in DUNGEONS:
		if cleared_ids.has(id):
			result.append(id)
	return result

## Recheck the current provider's IDs on selection, not a cached UI list.
## Hub-only selection prevents direct dungeon-to-dungeon travel.
static func scene_from_hub(origin_is_hub: bool, target: StringName, cleared_ids: Array[StringName]) -> String:
	if not origin_is_hub or not DUNGEONS.has(target) or not cleared_ids.has(target):
		return ""
	return DUNGEONS[target]["scene"]

static func label_for(target: StringName) -> String:
	return DUNGEONS[target]["label"] if DUNGEONS.has(target) else ""

## Owner definition: BOTH no enemies present AND enemies cannot spawn.
## The host must establish the second fact from area spawn capabilities,
## not from a proximity scan or a momentarily empty enemy group.
static func is_safe_area(enemies_present: bool, enemies_can_spawn: bool) -> bool:
	return not enemies_present and not enemies_can_spawn
