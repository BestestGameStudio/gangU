class_name EntranceGuards
extends AreaSpawnData
## #346: enemies posted around ONE overworld dungeon entrance.
##
## Same entry format as AreaSpawnData ("position" in the overworld's local
## space, "enemy", "reward_table"), plus an optional "definition"
## (EnemyDefinition) that EnemySpawner assigns before tree entry - the
## overworld uses it to give guards the leashed EnemyBehaviorGuard.
##
## Main mounts these on every overworld load, but ONLY while the dungeon
## named by dungeon_id is uncleared this run (Colin, 2026-11-08: "enemies
## spawn around those entrances for uncleared dungeons"). An empty
## dungeon_id means the dungeon has no clear state (the generated dungeon has
## no objective), so its guards always spawn. What a cleared entrance looks
## or behaves like beyond "no guards" is tracked in its own issue.

@export var dungeon_id: StringName = &""
