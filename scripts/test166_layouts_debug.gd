extends Node2D
## Standalone layout-archetype debug scene: harness/evidence only, not
## reachable from the game. Preset from GANGU_LAYOUT (default open_linear),
## seed from GANGU_SEED (default 1). Spawn marker green, exit blue,
## skeleton waypoints orange. GANGU_AUTOTEST=1 quits after a moment.

var size := TerrainGen.DEFAULT_SIZE
var map_seed := 1
var spawn_cell := Vector2i.ZERO
var exit_cell := Vector2i.ZERO
var waypoints: Array[Vector2i] = []

@onready var map: TerrainMap = $TerrainMap

func _ready() -> void:
	var preset := OS.get_environment("GANGU_LAYOUT")
	if preset.is_empty():
		preset = "open_linear"
	var env_seed := OS.get_environment("GANGU_SEED")
	if env_seed.is_valid_int():
		map_seed = env_seed.to_int()
	var layout := load("res://resources/terrain_layouts/%s.tres" % preset) as TerrainLayout
	var result := TerrainGen.generate(map, map_seed, size, layout)
	spawn_cell = result["spawn"]
	exit_cell = result["exit"]
	waypoints = result["waypoints"]
	if OS.get_environment("GANGU_AUTOTEST") == "1":
		get_tree().create_timer(2.0).timeout.connect(func(): get_tree().quit())
	queue_redraw()

func _draw() -> void:
	var cs := float(map.cell_size)
	var line := Color(0.0, 0.0, 0.0, 0.18)
	for x in range(size.x + 1):
		draw_line(Vector2(x * cs, 0), Vector2(x * cs, size.y * cs), line)
	for y in range(size.y + 1):
		draw_line(Vector2(0, y * cs), Vector2(size.x * cs, y * cs), line)
	for wp in waypoints:
		draw_circle(map.cell_to_world(wp), cs * 0.22, Color(1.0, 0.6, 0.15, 1.0))
	draw_circle(map.cell_to_world(spawn_cell), cs * 0.35, Color(0.3, 0.9, 0.4, 1.0))
	draw_circle(map.cell_to_world(exit_cell), cs * 0.35, Color(0.35, 0.55, 1.0, 1.0))
