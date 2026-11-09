extends SceneTree
## RECORDING-ONLY driver for #367 (not a test, not loaded by the game).
## Boots main.tscn, mounts DungeonMaze on a pinned seed, frames the whole
## maze, draws each entrance's FlowNav route to the core as an overlay line,
## spawns wave 1 and lets it walk; from frame CLOSEUP_AT the camera follows
## the lead enemy at normal zoom.
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 \
##     --path . --resolution 1920x1080 --write-movie /tmp/ci/shots/f.png \
##     --fixed-fps 30 --quit-after 330 --script res://tools/showcase/maze_overview.gd

const MAZE_SEED := 22
const CLOSEUP_AT := 210
const TIME_SCALE := 3.0

var main: Node
var cam: Camera2D
var area: Node2D
var frame := 0
var lead: Enemy = null

func _initialize() -> void:
	MazeDefenseDungeon.forced_seed = MAZE_SEED
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main

func _process(_delta: float) -> bool:
	frame += 1
	if frame == 2:
		main._entry_gate_type = Gate.GateType.NORMAL
		main._swap(load("res://scenes/dungeon_maze.tscn").instantiate())
		area = main.current_area
		var p: Player = main.get_node("Player")
		p.max_hp = 100000
		p.hp = 100000
		cam = main.find_child("*Camera*", true, false) as Camera2D
		var maze: Dictionary = area.maze
		var terrain := area.get_node("Terrain") as TerrainMap
		var size_px := Vector2(maze["size"]) * float(terrain.cell_size)
		cam.set("target", null)
		cam.global_position = terrain.to_global(size_px * 0.5)
		var view := root.get_visible_rect().size # stretch base, not the window
		var z := minf(view.x / size_px.x, view.y / size_px.y) * 0.97
		cam.zoom = Vector2(z, z)
		_draw_routes(terrain, area.get_node("FlowNav") as FlowNav, area.get_node("DefenseCore") as Node2D)
		var obj := area.get_node("DungeonObjective") as DungeonObjective
		obj.spawn_next_wave()
		obj.set_physics_process(false)
		Engine.time_scale = TIME_SCALE
		print("[maze_overview] seed ", MAZE_SEED, " size ", maze["size"], " zoom ", z)
	if frame == CLOSEUP_AT and area != null:
		var best := INF
		var core := area.get_node("DefenseCore") as Node2D
		for e in get_nodes_in_group(&"enemies"):
			var d := (e as Node2D).global_position.distance_to(core.global_position)
			if d < best:
				best = d
				lead = e
		cam.zoom = Vector2.ONE
	if frame >= CLOSEUP_AT and lead != null and is_instance_valid(lead):
		cam.global_position = lead.global_position
	return false

func _draw_routes(terrain: TerrainMap, nav: FlowNav, core: Node2D) -> void:
	var goal := terrain.world_to_cell(core.global_position)
	var colors := [Color(1, 0.85, 0.2), Color(1, 0.4, 0.8), Color(0.5, 1, 0.5), Color(0.6, 0.7, 1)]
	var i := 0
	for m in area.get_node("WaveSpawns").get_children():
		var line := Line2D.new()
		line.width = 6.0
		line.default_color = Color(colors[i % colors.size()], 0.75)
		line.z_index = -10
		for c in nav.path(terrain.world_to_cell((m as Node2D).global_position), goal):
			line.add_point(area.to_local(terrain.cell_to_world(c)))
		area.add_child(line)
		i += 1
