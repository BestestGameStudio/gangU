extends SceneTree
## #469 rendered fixture: a close player (100-150px) and the only tree
## BEHIND the mustache man. Pre-fix the mob found no "toward the player"
## cover and walked straight at the player (ENGAGED); now it falls back
## behind the tree, then keeps re-sheltering as the player circles it at
## close range. The mouse stays on the mob throughout (no 3s charge).
## TerrainMap has no visuals, so the tree cell is drawn as a green square,
## and the mob->player sightline is drawn (red = open, grey = blocked).
## Run under xvfb with --write-movie; quits itself.

var _stage: Node2D
var _map: TerrainMap
var _p: Player
var _e: Enemy
var _label: Label
var _line: Line2D
var _phase := ""
var _t := Vector2.ZERO

func _initialize() -> void:
	_stage = Node2D.new()
	root.add_child(_stage)
	current_scene = _stage
	var bg := ColorRect.new()
	bg.color = Color(0.32, 0.45, 0.28)
	bg.size = Vector2(4000, 4000)
	bg.position = Vector2(-1000, -1000)
	_stage.add_child(bg)
	_map = TerrainMap.new()
	_map.cell_size = 32
	_stage.add_child(_map)
	var cell := Vector2i(20, 20)
	_map.set_cell(cell, TerrainTypes.OBSTACLE)
	_t = _map.cell_to_world(cell)
	var tree := ColorRect.new()
	tree.color = Color(0.1, 0.3, 0.1)
	tree.size = Vector2(32, 32)
	tree.position = _t - Vector2(16, 16)
	_stage.add_child(tree)
	_line = Line2D.new()
	_line.width = 2.0
	_stage.add_child(_line)
	_p = load("res://scenes/player.tscn").instantiate()
	_p.name = "Player"
	_p.collision_layer = 0
	_p.collision_mask = 0
	_p.set_process(false)
	_stage.add_child(_p)
	_p.set_physics_process(false)
	_e = load("res://scenes/enemy.tscn").instantiate()
	_e.collision_layer = 0
	_e.collision_mask = 0
	_e.player_path = NodePath("../Player")
	_e.terrain = _map
	_stage.add_child(_e)
	var cam := Camera2D.new()
	cam.zoom = Vector2(3, 3)
	_stage.add_child(cam)
	cam.global_position = _t + Vector2(40, 0)
	cam.make_current()
	var hud := CanvasLayer.new()
	_stage.add_child(hud)
	_label = Label.new()
	_label.position = Vector2(24, 24)
	_label.add_theme_font_size_override("font_size", 28)
	hud.add_child(_label)
	await process_frame
	_e.global_position = _t + Vector2(50, 0)
	_p.global_position = _t + Vector2(150, 0)
	_phase = "player 100px away, only tree BEHIND the mob"
	await _run_frames(150)
	_phase = "player circles the tree at close range - mob re-shelters"
	for i in 150:
		var a := float(i) / 150.0 * PI * 0.6
		_p.global_position = _t + Vector2.from_angle(a) * 110.0
		await _run_frames(1)
	await _run_frames(60)
	quit(0)

func _run_frames(n: int) -> void:
	for i in n:
		_p.global_rotation = (_e.global_position - _p.global_position).angle()
		_p.hp = _p.max_hp
		await physics_frame
		var c: EnemyBehaviorCover = _e._behavior.get("_cover")
		var st: String = EnemyBehaviorCover.State.keys()[c._state]
		var blocked: bool = c._occluded(_map, _e.global_position, _p.global_position)
		_line.points = PackedVector2Array([_e.global_position, _p.global_position])
		_line.default_color = Color(0.6, 0.6, 0.6, 0.7) if blocked else Color(1, 0.2, 0.2, 0.9)
		_label.text = "#469: close player - mustache man still seeks cover\n%s\nstate: %s   dist: %d px   sightline: %s" % [
			_phase, st, int(_e.global_position.distance_to(_p.global_position)), ("BLOCKED" if blocked else "open")]
		await process_frame
