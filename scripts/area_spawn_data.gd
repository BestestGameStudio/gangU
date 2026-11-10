class_name AreaSpawnData
extends Node
## #100: per-area enemy spawn data carrier.
##
## An area scene (e.g. scenes/dungeon_a.tscn) attaches ONE child named
## "SpawnData" with this script. Main._mount_area_spawns reads it on every
## area swap; an area WITHOUT a SpawnData child gets NO enemies (the hub
## stays empty, and a carrier with zero entries spawns nothing). No area-name
## checks live in this mounter.
##
## Each Dictionary in `entries` carries EXACTLY these keys:
##   "position":     Vector2 - spawn position in the area's local space
##   "enemy":        PackedScene - the enemy scene to instantiate
##   "reward_table": RewardTable - that enemy's per-kill loot table
## `player_path` is a header-level setting for the whole carrier: it is
## assigned to every spawned enemy BEFORE tree entry, relative to the
## enemy itself (Main/<Area>/<Enemy> -> Main/Player = "../../Player").

@export var entries: Array[Dictionary] = []
@export var player_path: NodePath = NodePath("../../Player")
