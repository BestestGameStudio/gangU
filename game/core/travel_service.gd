class_name TravelService
extends Node
## #512: fast/map travel, split out of main.gd. Owns the #349 FastTravelPanel
## mount and the #349/#366 travel request/commit paths.
## The route policy is unchanged (FastTravelRoutes hub-spoke); AreaLoader
## owns the areas and the clear/offering records this reads. Main assigns
## area_loader/player before the first mount/refresh.

var area_loader: AreaLoader = null
var player: Player = null

## #349 travel wiring. Uses the ONE canonical dictionary above. Mount kept
## separate from the map block so exploration-map work remains independent.
var _fast_travel: FastTravelPanel

func mount() -> void:
	_fast_travel = FastTravelPanel.new()
	_fast_travel.name = "FastTravelPanel"
	add_child(_fast_travel)
	_fast_travel.destination_requested.connect(_request_fast_travel)

func refresh() -> void:
	if not is_instance_valid(_fast_travel) or area_loader.current_area == null:
		return
	_fast_travel.close()
	var choices: Array[StringName] = []
	if _is_hub_area():
		choices = area_loader.cleared_ids()
	_fast_travel.set_choices(choices)

func _is_hub_area() -> bool:
	return area_loader.current_area != null and area_loader.current_area.scene_file_path == FastTravelRoutes.HUB_SCENE

func _request_fast_travel(dungeon_id: StringName) -> void:
	_commit_fast_travel.call_deferred(dungeon_id)

func _commit_fast_travel(dungeon_id: StringName) -> void:
	var path := FastTravelRoutes.scene_from_hub(_is_hub_area(), dungeon_id, area_loader.cleared_ids())
	var p := player
	if path == "" or p == null or p.hp <= 0:
		return
	area_loader._enter_dungeon(dungeon_id, path)

## Asked by the map at click time and rechecked at commit. Same policy as the
## #349 Hub panel: origin must be the Hub, target must be cleared this run.
func can_map_travel_to(dungeon_id: StringName) -> bool:
	if area_loader.current_area == null:
		return false
	var p := player
	if p == null or p.hp <= 0:
		return false
	return FastTravelRoutes.scene_from_hub(_is_hub_area(), dungeon_id, area_loader.cleared_ids()) != ""

func _request_map_travel(dungeon_id: StringName) -> void:
	_commit_map_travel.call_deferred(dungeon_id)

## Commits through the #349 Hub commit (it rechecks scene_from_hub against the
## live clear record), so both entry points share one route policy.
func _commit_map_travel(dungeon_id: StringName) -> void:
	if not can_map_travel_to(dungeon_id): # recheck at commit, never trust the UI
		return
	_commit_fast_travel(dungeon_id)
