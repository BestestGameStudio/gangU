extends Node2D
## Standalone fog-of-war debug scene: a bordered terrain map under a fog
## overlay, with a marker walking from the left edge toward the centre so
## the final frame shows a VISIBLE disc, a SEEN trail, and UNSEEN beyond.
## Not reachable from the game. GANGU_AUTOTEST=1 quits once the walk ends.

const GRID_W := 18
const GRID_H := 10
const WALL_X := 9
const GAP_Y := 5
const EXTRA_OBSTACLES: Array[Vector2i] = [Vector2i(4, 2), Vector2i(4, 3), Vector2i(13, 7)]
const WALK_FROM := Vector2i(1, 5)
const WALK_TO := Vector2i(7, 5)
const WALK_SECONDS := 2.5

var walk_done := false

@onready var map: TerrainMap = $TerrainMap
@onready var fog: TerrainFog = $TerrainFog
@onready var marker: Node2D = $Marker

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
	fog.map = map
	fog.bounds = Rect2i(0, 0, GRID_W, GRID_H)
	fog.vision_radius = 3
	fog.target = marker
	marker.z_index = fog.z_index + 1
	marker.draw.connect(func(): marker.draw_circle(Vector2.ZERO, 14.0, Color(0.95, 0.85, 0.3, 1.0)))
	marker.global_position = map.cell_to_world(WALK_FROM)
	var tween := create_tween()
	tween.tween_property(marker, "global_position", map.cell_to_world(WALK_TO), WALK_SECONDS)
	tween.finished.connect(_on_walk_finished)
	queue_redraw()

func _on_walk_finished() -> void:
	walk_done = true
	if OS.get_environment("GANGU_AUTOTEST") == "1":
		get_tree().create_timer(0.5).timeout.connect(func(): get_tree().quit())

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(GRID_W, GRID_H) * map.cell_size), Color(0.1, 0.12, 0.16, 1.0))
	for x in range(GRID_W + 1):
		draw_line(Vector2(x * map.cell_size, 0), Vector2(x * map.cell_size, GRID_H * map.cell_size), Color(0.3, 0.32, 0.36, 0.6))
	for y in range(GRID_H + 1):
		draw_line(Vector2(0, y * map.cell_size), Vector2(GRID_W * map.cell_size, y * map.cell_size), Color(0.3, 0.32, 0.36, 0.6))
