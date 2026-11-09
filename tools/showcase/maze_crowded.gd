extends SceneTree
## RECORDING-ONLY driver for the #367 review repro (not a test, not loaded by
## the game). Same setup as test367 leg (G): production main.tscn ->
## DungeonMaze on seed 22, the player left on its chamber spawn, player/core
## HP raised only so the run lasts, and all five natural timed waves running
## with nothing frozen or removed. The whole maze is framed. A recording-only
## overlay label shows game time, waves, live enemies and how many enemies
## stand inside a wall right now / ever (the bug made that stay > 0 from
## about 69 s on).
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 \
##     --path . --resolution 1920x1080 --write-movie /tmp/ci/crowd/f.png \
##     --fixed-fps 30 --quit-after 1400 --script res://tools/showcase/maze_crowded.gd

const MAZE_SEED := 22
const TIME_SCALE := 4.0

var main: Node
var area: Node2D
var terrain: TerrainMap
var obj: DungeonObjective
var label: Label
var frame := 0
var t := 0.0
var ever_in_wall := 0

func _initialize() -> void:
	MazeDefenseDungeon.forced_seed = MAZE_SEED
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main

func _process(delta: float) -> bool:
	frame += 1
	if frame == 2:
		main._entry_gate_type = Gate.GateType.NORMAL
		main._swap(load("res://scenes/dungeon_maze.tscn").instantiate())
		area = main.current_area
		var p: Player = main.get_node("Player")
		p.max_hp = 100000
		p.hp = 100000
		var core := area.get_node("DefenseCore") as DefenseCore
		core.max_hp = 100000
		core.hp = 100000
		terrain = area.get_node("Terrain") as TerrainMap
		obj = area.get_node("DungeonObjective") as DungeonObjective
		var cam := main.find_child("*Camera*", true, false) as Camera2D
		var maze: Dictionary = area.maze
		var size_px := Vector2(maze["size"]) * float(terrain.cell_size)
		cam.set("target", null)
		cam.global_position = terrain.to_global(size_px * 0.5)
		var view := root.get_visible_rect().size
		var z := minf(view.x / size_px.x, view.y / size_px.y) * 0.93
		cam.zoom = Vector2(z, z)
		var layer := CanvasLayer.new()
		layer.layer = 100
		label = Label.new()
		label.position = Vector2(12, 8)
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_color_override("font_color", Color(1, 1, 0.4))
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 6)
		layer.add_child(label)
		root.add_child(layer)
		Engine.max_physics_steps_per_frame = 16
		Engine.time_scale = TIME_SCALE
	if area != null and label != null:
		t += delta
		var live := 0
		var in_wall := 0
		for e in get_nodes_in_group(&"enemies"):
			if e.get_parent() == area and (e as Enemy).hp > 0:
				live += 1
				if not terrain.is_walkable_at((e as Enemy).global_position):
					in_wall += 1
		ever_in_wall = maxi(ever_in_wall, in_wall)
		label.text = "[recording overlay] maze seed 22, natural waves, nothing frozen\ngame time %3.0f s   waves %d/%d   live enemies %d\nenemies inside a wall: now %d, max so far %d" % [
			t, obj.waves_spawned(), obj.wave_count, live, in_wall, ever_in_wall]
	return false
