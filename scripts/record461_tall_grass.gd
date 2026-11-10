extends SceneTree
## #461 rendered fixture (real overworld scene, scripted positions): tall
## grass hides whoever stands in it. Three beats:
##   1. player outside a grass patch: the enemy hiding in the patch is not
##      drawn; the enemy in the open is.
##   2. player steps into the patch beside the hidden enemy: it is drawn
##      again (both in grass, close by) and the player turns translucent.
##   3. the open-field enemy's AI is switched on: it has no target (the
##      player is hidden in the grass), so it does not come after them.
## Run under xvfb with --write-movie; quits itself.

var _p: Player
var _map: TerrainMap
var _label: Label
var _phase := ""
var _hidden: Enemy
var _open: Enemy

func _initialize() -> void:
	var area: Node2D = load("res://scenes/overworld.tscn").instantiate()
	root.add_child(area)
	current_scene = area
	await physics_frame
	_map = area.get_node("Terrain") as TerrainMap
	var ground := area.get_node("Ground") as OverworldGround
	# The patch nearest the arrival point.
	var patch: Dictionary = ground.grass_patches[0]
	for g in ground.grass_patches:
		if (g["at"] as Vector2).distance_to(ground.spawn) < (patch["at"] as Vector2).distance_to(ground.spawn):
			patch = g
	var at: Vector2 = patch["at"]
	var r: float = patch["r"]
	print("[rec461] patch at ", at, " r ", r)

	_p = load("res://scenes/player.tscn").instantiate()
	_p.name = "Player"
	_p.add_to_group("player")
	area.add_child(_p)
	_p.terrain = _map
	_p.set_physics_process(false)
	_p.global_position = at + Vector2(-r - 150, 0)

	_hidden = load("res://scenes/enemy.tscn").instantiate()
	area.add_child(_hidden)
	_hidden.terrain = _map
	_hidden.global_position = at + Vector2(20, 0)
	_hidden.set_physics_process(false)

	_open = load("res://scenes/enemy.tscn").instantiate()
	area.add_child(_open)
	_open.terrain = _map
	_open.global_position = at + Vector2(-r - 150, 230)
	_open.set_physics_process(false)

	var cam := Camera2D.new()
	cam.position = at + Vector2(-110, 60)
	cam.zoom = Vector2(1.6, 1.6)
	area.add_child(cam)
	cam.make_current()
	var hud := CanvasLayer.new()
	area.add_child(hud)
	_label = Label.new()
	_label.position = Vector2(24, 24)
	_label.add_theme_font_size_override("font_size", 26)
	hud.add_child(_label)

	_phase = "1. player outside the grass: the enemy hiding in it is not drawn"
	await _run_frames(60)

	_phase = "2. player steps into the grass beside it: both in grass, close -> visible"
	var target := at + Vector2(-40, 0)
	while _p.global_position.distance_to(target) > 4.0:
		_p.global_position = _p.global_position.move_toward(target, 4.0)
		await _run_frames(1)
	await _run_frames(60)

	_phase = "3. open-field enemy AI running: no target, it stays put (player hidden)"
	_open.set_physics_process(true)
	await _run_frames(90)
	print("[rec461] open enemy at ", _open.global_position, " target ", _open._resolve_target())
	quit(0)

func _run_frames(n: int) -> void:
	for i in n:
		await physics_frame
		_label.text = "#461: tall grass\n%s\nhidden enemy drawn: %s | player concealed: %s | open enemy target: %s" % [
			_phase, _hidden.visible, _p.is_concealed(), "player" if _open._resolve_target() != null else "none"]
		await process_frame
