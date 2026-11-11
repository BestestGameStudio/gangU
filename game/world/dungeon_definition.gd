class_name DungeonDefinition
extends Resource
## #512: a dungeon as data. One .tres per dungeon under data/dungeons/,
## listed in DungeonCatalog. Main reads it to mount the objective, exit portal,
## revive item and boss theme instead of branching on the area's node name.
## Defaults describe a plain dungeon with an objective and no extras.

## The area root node's name (what Main.current_area.name is).
@export var area_name: StringName = &""
## Id of the objective / clear record / fast-travel route.
@export var id: StringName = &""
@export var label: String = ""
@export_file("*.tscn") var scene: String = ""
@export var objective_type: DungeonObjective.ObjectiveType = DungeonObjective.ObjectiveType.CLEAR_ALL_ENEMIES

@export_group("Boss (ELIMINATION)")
## Spawned when the area's mobs are cleared. Null = no boss.
@export var boss_scene: PackedScene
## Boss spawn point, in the area's local space.
@export var boss_spawn: Vector2 = Vector2.ZERO
## The boss fight plays the boss theme even for a NORMAL-entered dungeon.
@export var boss_theme: bool = false

@export_group("Defense (DEFENSE)")
@export var wave_enemy_scene: PackedScene
@export var wave_reward_table: RewardTable
@export var wave_boss_scene: PackedScene

@export_group("Portal and extras")
## Mounts an exit portal even without an "ExitPoint" marker.
@export var default_exit_portal: bool = false
## Exit portal is locked until the objective clears, whatever gate type
## entered (RED entry also locks it).
@export var locks_portal: bool = false
@export var beast_portal_look: bool = false
## Treated as RED when no entry gate type is known (#350 fallback).
@export var red_by_default: bool = false
## Mounts the one-time revive item (#9).
@export var revive_item: bool = false
