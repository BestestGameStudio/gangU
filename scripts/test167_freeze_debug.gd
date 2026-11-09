extends Node2D
## #167 (Terrain B1) standalone evidence scene - not reachable from the game
## (no gate, not the main scene). A bordered 18x10 field split by a 3-wide
## river. A NON-SWIMMING player walks right and stops at the water's edge,
## fires three Frost Shards (cold-tagged) across the river, which freeze the
## water they fly over into walkable ICE, then walks over the ice bridge.
##
## Shots are spawned as Projectiles with the player as source (the same
## setup SpellCaster uses); the mouse aim is skipped because nobody is at the
## keyboard during capture. GANGU_AUTOTEST=1 quits once the script ends.

const GRID_W := 18
const GRID_H := 10
const RIVER_X: Array[int] = [8, 9, 10]
const FROST: Spell = preload("res://resources/spells/frost_shard.tres")
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/projectile.tscn")

@onready var map: TerrainMap = $TerrainMap
@onready var player: Player = $Player
@onready var caption: Label = $UI/Caption

var _t := 0.0
var _shots_fired := 0
var _frozen := 0

func _ready() -> void:
	var cells := {}
	for x in range(GRID_W):
		cells[Vector2i(x, 0)] = TerrainTypes.OBSTACLE
		cells[Vector2i(x, GRID_H - 1)] = TerrainTypes.OBSTACLE
	for y in range(GRID_H):
		cells[Vector2i(0, y)] = TerrainTypes.OBSTACLE
		cells[Vector2i(GRID_W - 1, y)] = TerrainTypes.OBSTACLE
	for x in RIVER_X:
		for y in range(1, GRID_H - 1):
			cells[Vector2i(x, y)] = TerrainTypes.WATER
	map.set_cells(cells)
	map.cell_interacted.connect(func(_c, _o, _n, _id): _frozen += 1)
	player.terrain = map
	player.can_swim = false
	player.global_position = map.cell_to_world(Vector2i(3, 5))
	_set_caption("Non-swimmer walks right: water blocks")

func _physics_process(delta: float) -> void:
	_t += delta
	if _t < 1.4:
		Input.action_press(&"move_right")
	elif _t < 2.9:
		Input.action_release(&"move_right")
		var due := int((_t - 1.4) / 0.5) + 1
		if _shots_fired < mini(due, 3):
			_fire(_shots_fired - 1)
			_shots_fired += 1
			_set_caption("Frost Shard (cold) x%d: water -> ice  [cells frozen: %d]" % [_shots_fired, _frozen])
	elif _t < 4.3:
		Input.action_press(&"move_right")
		_set_caption("Walking over the ice bridge  [cells frozen: %d]" % _frozen)
	elif _t < 5.6:
		Input.action_release(&"move_right")
		_set_caption("Crossed on the ice; the bridge stays frozen  [cells frozen: %d]" % _frozen)
	elif OS.get_environment("GANGU_AUTOTEST") == "1":
		get_tree().quit()

func _fire(row_offset: int) -> void:
	var p: Projectile = PROJECTILE_SCENE.instantiate()
	p.setup(FROST, Vector2.RIGHT, player)
	add_child(p)
	p.global_position = player.global_position + Vector2(24, row_offset * map.cell_size)
func _set_caption(text: String) -> void:
	caption.text = "#167 spell-terrain interaction  |  " + text

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(GRID_W, GRID_H) * map.cell_size), Color(0.1, 0.12, 0.16, 1.0))
