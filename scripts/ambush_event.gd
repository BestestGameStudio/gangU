class_name AmbushEvent
extends OverworldEvent
## #365 example event: an ambush spawns the enemies it is given.
##
## Mechanism only. Which enemies, how many, where, whether it repeats and
## what it rewards are all data (or later rules), not defaults chosen here.
## `entries` are SpawnEntry resources (position in the area's local space),
## so any behaviour slot the overworld already has works for ambushers too.
## Set `relative_to_trigger` to read each position and route as an offset
## from the trigger instead, so one ambush resource can sit on several triggers.

@export var entries: Array[SpawnEntry] = []
@export var relative_to_trigger: bool = false

## Emitted with the spawned enemies, so a later encounter rule (rewards,
## "ambush cleared", music) can follow them without touching this class.
signal ambush_started(context: OverworldEventContext, enemies: Array[Enemy])

func start(context: OverworldEventContext) -> void:
	var batch: Array[SpawnEntry] = []
	for entry: SpawnEntry in entries:
		var e := entry.duplicate() as SpawnEntry
		if relative_to_trigger and context.trigger != null and context.area is Node2D:
			var local := (context.area as Node2D).to_local(context.trigger.global_position)
			e.position = local + entry.position
			var pts := PackedVector2Array()
			for p in entry.route:
				pts.append(local + p)
			e.route = pts
		batch.append(e)
	var enemies := context.spawn(batch)
	ambush_started.emit(context, enemies)
