extends SceneTree
## #420 recording fixture (synthetic, NOT natural gameplay): production
## Player + one Mustache Barricader (scenes/enemy_barricader.tscn) on an empty
## 32px TerrainMap - open ground, no cover anywhere toward the player.
##   1. The barricader finds no cover, deploys a barricade toward the
##      player and holds behind it (and lobs rocks over it).
##   2. The fixture fires player Fire Balls at it (blocked + damaged), then a
##      piercing beam (passes through).
## The player aims at the mob so it keeps holding. Run under xvfb with
## --write-movie; quits itself.

const STATE_NAMES := ["SEEK", "DASH", "HOLD", "CHARGE", "ENGAGED"]
const FIRE := preload("res://resources/spells/fire_ball.tres")
const PIERCE := preload("res://resources/spells/fire_ball_beam_piercing.tres")

var _stage: Node2D
var _map: TerrainMap
var _p: Player
var _e: Enemy
var _label: Label

func _initialize() -> void:
	_stage = Node2D.new()
	_stage.name = "Stage"
	root.add_child(_stage)
	var bg := ColorRect.new()
	bg.color = Color(0.2, 0.34, 0.18)
	bg.size = Vector2(1600, 1400)
	_stage.add_child(bg)
	_map = TerrainMap.new()
	_map.name = "Terrain"
	_map.cell_size = 32
	_stage.add_child(_map)
	_p = load("res://scenes/player.tscn").instantiate()
	_p.name = "Player"
	_p.set_process(false)
	_stage.add_child(_p)
	_p.set_physics_process(false)
	_p.terrain = _map
	_e = load("res://scenes/enemy_barricader.tscn").instantiate()
	_e.player_path = NodePath("../Player")
	_e.terrain = _map
	_stage.add_child(_e)
	_e.set_physics_process(false)
	var cam := Camera2D.new()
	cam.position = Vector2(740, 640)
	cam.zoom = Vector2(2.4, 2.4)
	_stage.add_child(cam)
	cam.make_current()
	var hud := CanvasLayer.new()
	_stage.add_child(hud)
	_label = Label.new()
	_label.position = Vector2(24, 24)
	_label.add_theme_font_size_override("font_size", 26)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 8)
	hud.add_child(_label)
	await process_frame
	_e.global_position = Vector2(620, 640)
	_p.global_position = Vector2(900, 640)
	_e.set_physics_process(true)
	for i in 330:
		_p.global_rotation = (_e.global_position - _p.global_position).angle()
		_p.hp = maxi(_p.hp, 20) # recording only: keep the player alive
		if i == 120 or i == 150 or i == 180:
			_shoot(FIRE)
		if i == 230:
			_shoot(PIERCE)
		await physics_frame
		_overlay(i)
		await process_frame
	quit(0)

func _shoot(spell: Spell) -> void:
	var pr: Projectile = load("res://scenes/projectile.tscn").instantiate()
	pr.setup(spell, _e.global_position - _p.global_position, _p)
	_stage.add_child(pr)
	pr.global_position = _p.global_position

func _overlay(i: int) -> void:
	var beh := _e.get("_behavior") as EnemyBehaviorBarricader
	var cov := beh.get("_cover") as EnemyBehaviorCover
	var b: Barricade = null
	for n in get_nodes_in_group(&"barricades"):
		if is_instance_valid(n):
			b = n
	var bt := "none"
	if b != null:
		bt = "HP %d/%d, %.1fs left" % [b.hp, b.max_hp, b.time_left()]
	_label.text = "#420 frame %d   Mustache Barricader: %s, barricades deployed %d\nbarricade: %s\nrocks thrown over it: %d" % [
		i, STATE_NAMES[cov._state], beh.deployed, bt, cov.rocks_thrown]
	if i % 30 == 0:
		print("[420rec] f=%d state=%s deployed=%d barricade=%s rocks=%d" % [i, STATE_NAMES[cov._state], beh.deployed, bt, cov.rocks_thrown])
