extends Node2D
## Test dungeon whose map comes from TerrainGen instead of hand-placed tiles.
## Everything placed here derives from `map_seed`, so one seed is one map.
## Main reads SpawnData only after add_child, so _ready fills it in time.

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")
const FISHY_SCENE: PackedScene = preload("res://scenes/enemy_fishy.tscn")
## #490: one waypoint in FISHY_EVERY gets a Fishy instead of a warrior.
const FISHY_EVERY := 3
const REWARD_TABLE: RewardTable = preload("res://resources/rewards/demo_table.tres")
## Waypoints closer than this (Chebyshev cells) to the spawn get no enemy,
## so arriving players are not attacked before they can move.
const MIN_ENEMY_SPAWN_DISTANCE := 6

@export var map_seed: int = 1
@export var layout: TerrainLayout
## #266: this dungeon's own terrain tiles (looks + movement categories).
## Null keeps the built-in grass/forest + snow/ice tiles.
@export var tile_palette: TerrainPalette

@onready var _terrain: TerrainMap = $Terrain
@onready var _player_spawn: Marker2D = $PlayerSpawn
@onready var _exit_point: Marker2D = $ExitPoint
@onready var _spawn_data: AreaSpawnData = $SpawnData

func _ready() -> void:
	if tile_palette != null:
		_terrain.palette = tile_palette
	var result := TerrainGen.generate(_terrain, map_seed, TerrainGen.DEFAULT_SIZE, layout)
	var spawn: Vector2i = result["spawn"]
	var exit: Vector2i = result["exit"]
	_player_spawn.global_position = _terrain.cell_to_world(spawn)
	_exit_point.global_position = _terrain.cell_to_world(exit)
	var entries: Array[Dictionary] = []
	for wp: Vector2i in result["waypoints"]:
		var from_spawn := (wp - spawn).abs()
		if wp == exit or maxi(from_spawn.x, from_spawn.y) < MIN_ENEMY_SPAWN_DISTANCE:
			continue
		# #490: enemies 2, 5, 8, ... are Fishy: about one Fishy for every two
		# Mustache Warriors (2 of the usual 5, where "every third" gives 1).
		var fishy := entries.size() % FISHY_EVERY == 1
		entries.append({
			"position": to_local(_terrain.cell_to_world(wp)),
			"enemy": FISHY_SCENE if fishy else ENEMY_SCENE,
			"reward_table": REWARD_TABLE,
		})
	_spawn_data.entries = entries
