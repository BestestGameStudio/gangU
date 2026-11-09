class_name MazeDefenseDungeon
extends Node2D
## #367: maze defense mission. The map comes from MazeGen: the DefenseCore
## sits in the central chamber, enemy waves come in through the entrances
## cut into the maze's outer wall, and every wave enemy finds its way through
## the corridors with the area's FlowNav. The DEFENSE objective itself is
## mounted by main.gd (_mount_objective), same as DungeonE.
## Everything is placed in _ready: Main reads PlayerSpawn, ExitPoint and
## WaveSpawns only after add_child.

## Seed of this visit's maze. With randomize_seed on (the production
## default) a fresh seed is rolled on every entry; harnesses turn it off to
## pin one layout.
@export var map_seed: int = 1
@export var randomize_seed: bool = true
@export var rooms: Vector2i = MazeGen.DEFAULT_ROOMS
@export var entrance_count: int = MazeGen.DEFAULT_ENTRANCES
@export_range(0.0, 1.0) var loop_chance: float = MazeGen.DEFAULT_LOOP_CHANCE

## Harness hook: >= 0 pins every new instance to this seed (an area entered
## through a gate is instantiated by Main, out of the harness's reach).
static var forced_seed: int = -1

@onready var _terrain: TerrainMap = $Terrain
@onready var _player_spawn: Marker2D = $PlayerSpawn
@onready var _exit_point: Marker2D = $ExitPoint
@onready var _core: DefenseCore = $DefenseCore
@onready var _wave_spawns: Node2D = $WaveSpawns
@onready var _nav: FlowNav = $FlowNav

## MazeGen's result for this visit (harness introspection).
var maze: Dictionary = {}

func _ready() -> void:
	if forced_seed >= 0:
		map_seed = forced_seed
	elif randomize_seed:
		map_seed = randi()
	maze = MazeGen.generate(_terrain, map_seed, rooms, entrance_count, loop_chance)
	print("maze defense: seed ", map_seed, ", ", maze["rooms"], " rooms, ", maze["entrances"].size(), " entrances")
	_core.position = _local(maze["objective"])
	_player_spawn.position = _local(maze["player_spawn"])
	_exit_point.position = _local(maze["exit"])
	for c in _wave_spawns.get_children():
		_wave_spawns.remove_child(c)
		c.free()
	_wave_spawns.position = Vector2.ZERO
	var i := 0
	for at: Vector2 in maze["entrances"]:
		var m := Marker2D.new()
		m.name = "Entrance%d" % i
		m.position = _local(at)
		_wave_spawns.add_child(m)
		i += 1
	_nav.bounds = maze["bounds"]
	_nav.map = _terrain

## Map-local pixels -> this area's local space.
func _local(map_px: Vector2) -> Vector2:
	return to_local(_terrain.to_global(map_px))

func nav() -> FlowNav:
	return _nav
