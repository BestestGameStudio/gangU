class_name OverworldEvent
extends Resource
## #365: base class for what a LocationTrigger starts.
##
## FOUNDATION ONLY. Subclass it and override start(). The resource is shared
## data (one .tres can sit on many triggers), so keep per-run or per-visit
## state out of it: the context carries the live nodes, and Main keeps the
## run-scoped fire history (Main.location_event_fire_count).
##
## AmbushEvent is the first example. No production area places an event yet:
## trigger spots, repeat/reset rules, ambush composition and rewards are
## undesigned (#365), so content is left to the issues that decide them.

## Optional label for logs, the HUD or later UI. Not used by the foundation.
@export var display_name: String = ""

## Called once each time a trigger holding this event fires.
func start(_context: OverworldEventContext) -> void:
	pass
