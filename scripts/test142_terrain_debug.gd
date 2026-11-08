extends Node2D
## #142 (Terrain A1) standalone FLAT DEBUG MAP - harness/evidence scene
## only. Not reachable from the game (no gate, no mount, not the main
## scene); real dungeon wiring lands in later terrain issues (A2+).
##
## Layout: an obstacle-BORDERED 18x10 field (so the flood fill is bounded),
## one vertical wall with a single gap, and a few scattered obstacles.
## Spawn (green) and exit (blue) markers sit on open ground with a
## guaranteed walkable path between them - the acceptance leg proves that
## path with TerrainNav, it is not assumed.
## GANGU_AUTOTEST=1: quits after a moment (evidence-capture idiom).

const GRID_W := 18
const GRID_H := 10
const WALL_X := 9
const GAP_Y := 5
const EXTRA_OBSTACLES: Array[Vector2i] = [Vector2i(4, 2), Vector2i(4, 3), Vector2i(13, 7)]

var spawn_cell := Vector2i(1, 5)
var exit_cell := Vector2i(16, 5)

@onready var map: TerrainMap = $TerrainMap

func _ready() -> void:
	for x in range(GRID_W):
		map.set_cell(Vector2i(x, 0), TerrainTypes.OBSTACLE)
		map.set_cell(Vector2i(x, GRID_H - 1), TerrainTypes.OBSTACLE)
	for y in range(GRID_H):
		map.set_cell(Vector2i(0, y), TerrainTypes.OBSTACLE)
		map.set_cell(Vector2i(GRID_W - 1, y), TerrainTypes.OBSTACLE)
	for y in range(1, GRID_H - 1):
		if y != GAP_Y:
			map.set_cell(Vector2i(WALL_X, y), TerrainTypes.OBSTACLE)
	for c in EXTRA_OBSTACLES:
		map.set_cell(c, TerrainTypes.OBSTACLE)
	if OS.get_environment("GANGU_AUTOTEST") == "1":
		get_tree().create_timer(2.0).timeout.connect(func(): get_tree().quit())
	queue_redraw()

func spawn_world() -> Vector2:
	return map.cell_to_world(spawn_cell)

func exit_world() -> Vector2:
	return map.cell_to_world(exit_cell)

func _draw() -> void:
	# Background first: drawn here (not a ColorRect child) so it cannot
	# cover the grid lines and markers below.
	draw_rect(Rect2(Vector2.ZERO, Vector2(GRID_W, GRID_H) * map.cell_size), Color(0.1, 0.12, 0.16, 1.0))
	# Grid lines (first-pass square-grid presentation) behind the markers.
	for x in range(GRID_W + 1):
		draw_line(Vector2(x * map.cell_size, 0), Vector2(x * map.cell_size, GRID_H * map.cell_size), Color(0.3, 0.32, 0.36, 0.6))
	for y in range(GRID_H + 1):
		draw_line(Vector2(0, y * map.cell_size), Vector2(GRID_W * map.cell_size, y * map.cell_size), Color(0.3, 0.32, 0.36, 0.6))
	draw_circle(spawn_world(), 14.0, Color(0.3, 0.9, 0.4, 1.0))
	draw_circle(exit_world(), 14.0, Color(0.35, 0.55, 1.0, 1.0))
