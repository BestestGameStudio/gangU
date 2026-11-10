extends SceneTree
## #463 rendered fixture (real overworld scene, real Mustache Warrior art;
## straight-line chase - terrain steering off in this fixture, the radius
## logic is terrain-independent). A mustache patroller drops its route,
## chases, and KEEPS CHASING at ~1000px (past the old 900 give-up) while
## the player is still on screen; past the new 1350 it gives up and
## returns to its route. Chase speed is raised for watchability (the
## logic is speed-independent; test463 covers real speed). Run under xvfb
## with --write-movie; quits itself.

var _p: Player
var _e: Enemy
var _b: EnemyBehaviorPatrol
var _cam: Camera2D
var _label: Label
var _phase := ""
var _engaged_from := Vector2.ZERO

func _initialize() -> void:
	var area: Node2D = load("res://scenes/overworld.tscn").instantiate()
	root.add_child(area)
	current_scene = area
	_p = load("res://scenes/player.tscn").instantiate()
	_p.name = "Player"
	_p.collision_layer = 0
	_p.collision_mask = 0
	area.add_child(_p)
	_p.global_position = Vector2(7000, 7000) # parked far away
	_p.set_physics_process(false)
	_e = load("res://scenes/enemy.tscn").instantiate()
	_e.collision_layer = 0
	_e.collision_mask = 0
	_e.player_path = NodePath("../Player")
	_e.definition = load("res://resources/enemies/overworld_patrol.tres")
	area.add_child(_e)
	_e.global_position = Vector2(500, 560)
	_cam = Camera2D.new()
	area.add_child(_cam)
	_cam.global_position = _e.global_position
	_cam.make_current()
	var hud := CanvasLayer.new()
	area.add_child(hud)
	_label = Label.new()
	_label.position = Vector2(24, 24)
	_label.add_theme_font_size_override("font_size", 26)
	hud.add_child(_label)
	await _run_frames(30) # let _ready build the behavior
	_b = _e._behavior as EnemyBehaviorPatrol
	_b.configure_route(PackedVector2Array([Vector2(500, 560), Vector2(620, 560), Vector2(620, 660), Vector2(500, 660)]))

	_phase = "patrolling its loop"
	await _run_frames(60)

	_p.global_position = _e.global_position + Vector2(140, 0)
	_phase = "player in aggro range: drops the route, chases"
	await _run_frames(40)
	_engaged_from = _b.engaged_from

	# ~1000px away - past the OLD 900 give-up, inside the new 1350.
	_p.global_position = _engaged_from + Vector2(1000, 0)
	_e.speed = 700.0 # watchability only; the radius logic is speed-independent
	_phase = "1000px away (past the old 900 give-up): KEEPS CHASING while the player is on screen"
	for i in 100:
		_track()
		await _run_frames(1)
	_phase = "reached the player - the old 900 would have given up halfway"
	await _run_frames(60)

	# Past the NEW 1350: gives up and returns to its route.
	_p.global_position = _engaged_from + Vector2(1450, 0)
	_track()
	_phase = "past the new 1350 give-up: disengages, returns to its old route"
	await _run_frames(110)
	_cam.global_position = Vector2(560, 610) # the route beat
	_phase = "back on patrol (slime patrollers keep the old 900 - mustache men only)"
	await _run_frames(60)
	quit(0)

func _track() -> void:
	_cam.global_position = (_p.global_position + _e.global_position) * 0.5

func _run_frames(n: int) -> void:
	for i in n:
		await physics_frame
		_p.hp = _p.max_hp
		_label.text = "#463: mustache men chase while you're on screen\n%s" % _phase
		await process_frame
