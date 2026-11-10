extends SceneTree
## #436 rendered fixture (camera flight over the real expanded overworld):
## the field now reaches 2x its old size in each direction. Red marker
## lines sit at the OLD field edges (x = 576 +/- 1200); the camera pans
## past both to the new edges, with terrain and decor continuing the whole
## way. Run under xvfb with --write-movie; quits itself.

var _cam: Camera2D
var _label: Label
var _phase := ""

func _initialize() -> void:
	var area: Node2D = load("res://scenes/overworld.tscn").instantiate()
	root.add_child(area)
	current_scene = area
	var ground := area.get_node("Ground")
	# Marker lines at the OLD field's x edges, drawn on top of the ground.
	var markers := Node2D.new()
	markers.z_index = 5
	area.add_child(markers)
	markers.draw.connect(func():
		for x in [OverworldGround.CENTER.x - 1200.0, OverworldGround.CENTER.x + 1200.0]:
			markers.draw_line(Vector2(x, OverworldGround.CENTER.y - 2200), Vector2(x, OverworldGround.CENTER.y + 2200), Color(1, 0.2, 0.2, 0.8), 6.0))
	markers.queue_redraw()
	_cam = Camera2D.new()
	_cam.zoom = Vector2(0.45, 0.45)
	area.add_child(_cam)
	await process_frame
	_cam.make_current()
	var hud := CanvasLayer.new()
	area.add_child(hud)
	_label = Label.new()
	_label.position = Vector2(24, 24)
	_label.add_theme_font_size_override("font_size", 34)
	hud.add_child(_label)

	var y := OverworldGround.CENTER.y + 400.0
	# Start inside the old field, pan west past the old edge to the new edge.
	_cam.position = Vector2(OverworldGround.CENTER.x, y)
	_phase = "center of the field (old edges marked red)"
	await _run_frames(50)
	_phase = "panning west: crossing the OLD edge"
	await _pan_to(Vector2(OverworldGround.CENTER.x - 2300, y), 170)
	_phase = "past the old edge - terrain continues to the new west edge"
	await _run_frames(50)
	# East across the whole field to the far new edge.
	_phase = "crossing the whole field east"
	await _pan_to(Vector2(OverworldGround.CENTER.x + 2300, y), 260)
	_phase = "new east edge - 2x in each direction, 4x the area"
	await _run_frames(50)
	# Wide shot of the whole field.
	var tween_zoom := 0.0
	_phase = "whole field, zoomed out"
	for i in 40:
		tween_zoom = lerpf(0.45, 0.19, float(i) / 40.0)
		_cam.zoom = Vector2(tween_zoom, tween_zoom)
		_cam.position = _cam.position.lerp(OverworldGround.CENTER, 0.06)
		await _run_frames(1)
	await _run_frames(60)
	quit(0)

func _pan_to(target: Vector2, frames: int) -> void:
	var from := _cam.position
	for i in frames:
		_cam.position = from.lerp(target, float(i) / float(frames))
		await _run_frames(1)

func _run_frames(n: int) -> void:
	for i in n:
		await physics_frame
		_label.text = "#436: overworld 2x in each direction\n%s\nworld x: %d" % [_phase, int(_cam.position.x)]
		await process_frame
