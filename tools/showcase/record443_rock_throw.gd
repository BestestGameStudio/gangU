extends SceneTree
## #443 recording fixture (synthetic, NOT natural gameplay): production
## Player + two enemy.tscn mustache men on a 32px TerrainMap.
##   top mob    - hides behind an overworld-style tree (OBSTACLE cell + #407
##                canopy circle, drawn green): throws rocks over it.
##   bottom mob - hides behind a maze-wall OBSTACLE (drawn grey, no canopy):
##                holds, but throws nothing into high cover.
## The player aims between them (both "pointed at", so both keep holding).
## Run under xvfb with --write-movie; quits itself.

const STATE_NAMES := ["SEEK", "DASH", "HOLD", "CHARGE", "ENGAGED"]

var _map: TerrainMap
var _p: Player
var _top: Enemy
var _bot: Enemy
var _label: Label

func _initialize() -> void:
	var stage := Node2D.new()
	stage.name = "Stage"
	root.add_child(stage)
	var bg := ColorRect.new()
	bg.color = Color(0.2, 0.34, 0.18)
	bg.size = Vector2(1600, 1400)
	stage.add_child(bg)
	_map = TerrainMap.new()
	_map.name = "Terrain"
	_map.cell_size = 32
	stage.add_child(_map)
	var tree_cell := Vector2i(20, 18)
	var wall_cell := Vector2i(20, 22)
	var tree := _map.cell_to_world(tree_cell)
	var wall := _map.cell_to_world(wall_cell)
	_map.set_cell(tree_cell, TerrainTypes.OBSTACLE)
	var blockers: Array[Vector3] = [Vector3(tree.x, tree.y, 18.0)]
	_map.set_projectile_blockers(blockers)
	_map.set_cell(wall_cell, TerrainTypes.OBSTACLE)
	var canopy := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 24:
		pts.append(tree + Vector2.from_angle(TAU * i / 24.0) * 22.0)
	canopy.polygon = pts
	canopy.color = Color(0.1, 0.45, 0.15)
	canopy.z_index = 2
	stage.add_child(canopy)
	var wr := ColorRect.new()
	wr.color = Color(0.5, 0.48, 0.45)
	wr.size = Vector2(32, 32)
	wr.position = wall - Vector2(16, 16)
	wr.z_index = 2
	stage.add_child(wr)
	_p = load("res://scenes/player.tscn").instantiate()
	_p.name = "Player"
	_p.set_process(false)
	stage.add_child(_p)
	_p.set_physics_process(false)
	_p.terrain = _map
	_top = _mk_enemy(stage)
	_bot = _mk_enemy(stage)
	var cam := Camera2D.new()
	cam.position = (tree + wall) * 0.5 + Vector2(10, -30)
	cam.zoom = Vector2(1.9, 1.9)
	stage.add_child(cam)
	cam.make_current()
	var hud := CanvasLayer.new()
	stage.add_child(hud)
	_label = Label.new()
	_label.position = Vector2(24, 24)
	_label.add_theme_font_size_override("font_size", 26)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 8)
	hud.add_child(_label)
	await process_frame
	_top.global_position = tree + Vector2(-200, 0)
	_bot.global_position = wall + Vector2(-200, 0)
	_p.global_position = (tree + wall) * 0.5 + Vector2(210, 0)
	_top.set_physics_process(true)
	_bot.set_physics_process(true)
	var hp0 := _p.hp
	for i in 330:
		var mid := (_top.global_position + _bot.global_position) * 0.5
		_p.global_rotation = (mid - _p.global_position).angle()
		_p.hp = maxi(_p.hp, 20) # recording only: keep the player alive
		await physics_frame
		_overlay(i, hp0)
		await process_frame
	quit(0)

func _mk_enemy(stage: Node2D) -> Enemy:
	var e: Enemy = load("res://scenes/enemy.tscn").instantiate()
	e.player_path = NodePath("../Player")
	e.terrain = _map
	stage.add_child(e)
	e.set_physics_process(false)
	return e

func _cov(e: Enemy) -> EnemyBehaviorCover:
	return (e.get("_behavior") as RefCounted).get("_cover") as EnemyBehaviorCover

func _overlay(i: int, hp0: int) -> void:
	var ct := _cov(_top)
	var cb := _cov(_bot)
	_label.text = "#443 frame %d   player hp %d/%d\nbehind TREE: %s, rocks thrown %d\nbehind WALL: %s, rocks thrown %d" % [
		i, _p.hp, hp0, STATE_NAMES[ct._state], ct.rocks_thrown, STATE_NAMES[cb._state], cb.rocks_thrown]
	if i % 30 == 0:
		print("[443rec] f=%d top=%s/%d bot=%s/%d hp=%d" % [i, STATE_NAMES[ct._state], ct.rocks_thrown, STATE_NAMES[cb._state], cb.rocks_thrown, _p.hp])
