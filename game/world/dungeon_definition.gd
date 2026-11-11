class_name DungeonDefinition
extends Resource
## Region seed content catalog: layout, local boss/wave composition, revive
## item and existing music policy. No objective enum or exit-portal policy.

## The area root node's name (what Main.current_area.name is).
@export var area_name: StringName = &""
## Stable encounter clear record / fast-travel route id.
@export var id: StringName = &""
@export var label: String = ""
@export_file("*.tscn") var scene: String = ""

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
## Treated as RED when no entry gate type is known (#350 fallback).
@export var red_by_default: bool = false
## Mounts the one-time revive item (#9).
@export var revive_item: bool = false
