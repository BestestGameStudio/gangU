extends SceneTree
## #437 rendered fixture (synthetic placement through the #216 seam, real
## overworld scene): the Stone Block spell's terrain now RENDERS in the
## overworld - the same rock-wall sprite as in dungeons. Blocks appear with
## their build-up animation, the player cannot walk through one, and a
## destroyed block collapses into rubble. Run under xvfb with
## --write-movie; quits itself.

var _p: Player
var _map: TerrainMap
var _label: Label
var _phase := ""

func _initialize() -> void:
	var area: Node2D = load("res://scenes/overworld.tscn").instantiate()
	root.add_child(area)
	current_scene = area
	_map = area.get_node("Terrain") as TerrainMap
	_p = load("res://scenes/player.tscn").instantiate()
	_p.name = "Player"
	area.add_child(_p)
	_p.global_position = Vector2(370, 560)
	var cam := Camera2D.new()
	cam.position = Vector2(450, 540)
	area.add_child(cam)
	cam.make_current()
	var hud := CanvasLayer.new()
	area.add_child(hud)
	_label = Label.new()
	_label.position = Vector2(24, 24)
	_label.add_theme_font_size_override("font_size", 30)
	hud.add_child(_label)

	_phase = "overworld: casting Stone Block"
	await _run_frames(90)
	# The placement seam the spell uses (#216), aimed just ahead of the player.
	var spell: Spell = load("res://resources/spells/stone_block.tres")
	var cells := [Vector2i(13, 17), Vector2i(14, 17), Vector2i(15, 17)]
	for c in cells:
		var placed: Variant = TerrainBlock.place(_map, _p.global_position, _map.cell_to_world(c), spell.range, spell.terrain_block, [])
		print("[rec437] place ", c, " -> ", placed)
		await _run_frames(30)
	_phase = "blocks render (were invisible before #437)"
	await _run_frames(120)

	_phase = "still blocks movement (walk seam cannot cross)"
	# Drive the player through the walk seam toward the wall: it stops at it.
	var vel := Vector2.ZERO
	for i in 80:
		var want := (Vector2(464, 560) - _p.global_position).normalized() * 90.0
		vel = TerrainMotion.resolve(_map, _p.global_position, vel, want, 1.0 / 60.0, false)
		_p.global_position += vel * (1.0 / 60.0)
		await _run_frames(1)
	print("[rec437] walked to ", _p.global_position, " cell ", _map.world_to_cell(_p.global_position))
	await _run_frames(90)

	_phase = "destroyed block collapses"
	_map.destroy_at(_map.cell_to_world(cells[1]))
	await _run_frames(120)
	quit(0)

func _run_frames(n: int) -> void:
	for i in n:
		await physics_frame
		_label.text = "#437: Stone Block terrain in the overworld\n%s" % _phase
		await process_frame
