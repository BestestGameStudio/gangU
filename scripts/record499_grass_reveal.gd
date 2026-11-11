extends SceneTree
## #499 rendered fixture (real overworld scene, scripted positions):
## attacking from tall grass reveals the player.
##   1. player hides in a grass patch; the open-field enemy's AI runs but it
##      has no target, so it stays put. The player is drawn translucent.
##   2. the player casts a spell from the grass: revealed - drawn opaque, and
##      the enemy (far outside sight range) comes after them.
##   3. the player steps out and back in: hidden again, the enemy loses them.
## Run under xvfb with --write-movie; quits itself.

var _p: Player
var _label: Label
var _phase := ""
var _open: Enemy

func _initialize() -> void:
	var area: Node2D = (load("res://scenes/overworld.tscn") as PackedScene).instantiate()
	root.add_child(area)
	current_scene = area
	await physics_frame
	var map := area.get_node("Terrain") as TerrainMap
	var ground := area.get_node("Ground") as OverworldGround
	var patch: Dictionary = ground.grass_patches[0]
	for g in ground.grass_patches:
		if (g["at"] as Vector2).distance_to(ground.spawn) < (patch["at"] as Vector2).distance_to(ground.spawn):
			patch = g
	var at: Vector2 = patch["at"]
	var r: float = patch["r"]

	_p = (load("res://scenes/player.tscn") as PackedScene).instantiate()
	_p.name = "Player"
	_p.add_to_group("player")
	area.add_child(_p)
	_p.terrain = map
	_p.set_physics_process(false)
	_p.global_position = at

	_open = (load("res://scenes/enemy.tscn") as PackedScene).instantiate()
	area.add_child(_open)
	_open.terrain = map
	_open.cover_seek = false
	_open.global_position = at + Vector2(-r - 260, 160)

	var cam := Camera2D.new()
	cam.position = at + Vector2(-160, 80)
	cam.zoom = Vector2(1.4, 1.4)
	area.add_child(cam)
	cam.make_current()
	var hud := CanvasLayer.new()
	area.add_child(hud)
	_label = Label.new()
	_label.position = Vector2(24, 24)
	_label.add_theme_font_size_override("font_size", 26)
	hud.add_child(_label)

	_phase = "1. player hidden in tall grass: enemy AI running, no target"
	await _run_frames(60)
	_phase = "2. player casts from the grass -> revealed, enemy comes after them"
	var caster := _p.get_node("SpellCaster") as SpellCaster
	caster.aim_override = _p.global_position + Vector2(200, -120)
	caster.cast()
	await _run_frames(75)
	print("[rec499] after cast: revealed ", _p.is_grass_revealed(), " enemy target ", _open._resolve_target())
	_phase = "3. player leaves the grass and comes back: hidden again"
	var back := _p.global_position
	_p.global_position = at + Vector2(r + 60, 0)
	await _run_frames(2)
	_p.global_position = back
	await _run_frames(45)
	print("[rec499] re-entered: revealed ", _p.is_grass_revealed(), " enemy target ", _open._resolve_target())
	quit(0)

func _run_frames(n: int) -> void:
	for i in n:
		await physics_frame
		_label.text = "#499: attacking from tall grass reveals the player\n%s\nplayer concealed: %s | revealed: %s | enemy target: %s" % [
			_phase, _p.is_concealed(), _p.is_grass_revealed(), "player" if _open._resolve_target() != null else "none"]
		await process_frame
