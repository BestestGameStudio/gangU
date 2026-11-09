extends SceneTree
## RECORDING-ONLY driver for #396 (not a test, not loaded by the game).
## Boots main.tscn and mounts each gated dungeon (A-E) in turn, framing its
## whole terrain map (walls + pillars), with the production spawns, bosses
## and objective running. The player is made unkillable so the tour never
## restarts the run.
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 \
##     --path . --resolution 1920x1080 --write-movie /tmp/ci/shots/f.png \
##     --fixed-fps 30 --quit-after 232 --script res://tools/showcase/dungeon_terrain_tour.gd
## Frame 2 + 45*i + 40 is the settled shot of dungeon i.

const DUNGEONS := [
	"res://scenes/dungeon_a.tscn",
	"res://scenes/dungeon_b.tscn",
	"res://scenes/dungeon_c.tscn",
	"res://scenes/dungeon_d.tscn",
	"res://scenes/dungeon_e.tscn",
]
const SEGMENT := 45

var main: Node
var frame := 0

func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main

func _process(_delta: float) -> bool:
	frame += 1
	var p: Player = main.get_node_or_null("Player")
	if p != null:
		p.max_hp = 100000
		p.hp = 100000
	if frame >= 2 and (frame - 2) % SEGMENT == 0:
		var i := (frame - 2) / SEGMENT
		if i < DUNGEONS.size():
			main._swap(load(DUNGEONS[i]).instantiate())
			_frame_area(main.current_area)
			print("[tour] frame ", frame, " -> ", main.current_area.name)
	return false

func _frame_area(area: Node) -> void:
	var terrain := area.get_node("Terrain") as TerrainMap
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := -lo
	for c: Vector2i in terrain.assigned_cells():
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var size_px := Vector2(hi - lo + Vector2i.ONE) * float(terrain.cell_size)
	var cam := main.find_child("*Camera*", true, false) as Camera2D
	cam.set("target", null)
	cam.global_position = terrain.to_global(Vector2(lo) * float(terrain.cell_size) + size_px * 0.5)
	var view := root.get_visible_rect().size
	var z := minf(view.x / size_px.x, view.y / size_px.y) * 0.95
	cam.zoom = Vector2(z, z)
