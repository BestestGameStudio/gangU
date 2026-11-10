extends SceneTree
## #450 rendered fixture (synthetic): two players dash right from the same
## start line. Top lane uses the OLD duration (0.15s = 135 px), bottom lane
## the NEW base (0.09s = 81 px). Marker posts sit at +81 and +135 px.
## Run under xvfb with --write-movie; quits itself.

const START_X := 300.0
var _old: Player
var _new: Player
var _label: Label
var _phase := ""

func _initialize() -> void:
	var stage := Node2D.new()
	root.add_child(stage)
	current_scene = stage
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.16, 0.12)
	bg.position = Vector2(-400, -200)
	bg.size = Vector2(1800, 1200)
	stage.add_child(bg)
	for lane_y in [300.0, 460.0]:
		_post(stage, START_X, lane_y, Color(1, 1, 1))
		_post(stage, START_X + 81.0, lane_y, Color(0.3, 1.0, 0.4))
		_post(stage, START_X + 135.0, lane_y, Color(1.0, 0.35, 0.3))
	_old = _spawn(stage, Vector2(START_X, 300), 0.15)
	_new = _spawn(stage, Vector2(START_X, 460), 0.09)
	var cam := Camera2D.new()
	cam.position = Vector2(START_X + 70.0, 380)
	cam.zoom = Vector2(3.0, 3.0)
	stage.add_child(cam)
	cam.make_current()
	var hud := CanvasLayer.new()
	stage.add_child(hud)
	_label = Label.new()
	_label.position = Vector2(24, 24)
	_label.add_theme_font_size_override("font_size", 36)
	hud.add_child(_label)
	_phase = "ready (posts: white start, green +81 px, red +135 px)"
	await _run_frames(10)
	_phase = "dashing"
	_old.try_dash(Vector2.RIGHT)
	_new.try_dash(Vector2.RIGHT)
	await _run_frames(30)
	_phase = "done"
	await _run_frames(15)
	quit(0)

func _spawn(stage: Node2D, pos: Vector2, duration: float) -> Player:
	var p: Player = load("res://scenes/player.tscn").instantiate()
	p.dash_duration = duration
	stage.add_child(p)
	p.global_position = pos
	return p

func _post(stage: Node2D, x: float, y: float, c: Color) -> void:
	var r := ColorRect.new()
	r.color = c
	r.position = Vector2(x - 1.0, y - 40.0)
	r.size = Vector2(2.0, 80.0)
	stage.add_child(r)

func _run_frames(n: int) -> void:
	for i in n:
		await physics_frame
		_label.text = "%s\nOLD 0.15s (top): moved %.0f px\nNEW 0.09s (bottom, #450): moved %.0f px" % [
			_phase, _old.global_position.x - START_X, _new.global_position.x - START_X]
		await process_frame
