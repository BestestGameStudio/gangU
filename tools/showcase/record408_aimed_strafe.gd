extends SceneTree
## PR #408 review repro, rendered (synthetic fixture, NOT natural gameplay):
## production Player + enemy.tscn, TerrainMap 32px, OBSTACLE at (20,20)
## plus a second OBSTACLE at (20,22). The mob settles in HOLD while aimed
## at, then the player arcs from centre+(220,0) to centre+(0,220) while
## STILL aiming at it. Overlays (recording only): green cover cells, yellow
## sightline (red when it crosses no blocking cell), state label.
## Run under xvfb with --write-movie; quits itself.

const STATE_NAMES := ["SEEK", "DASH", "HOLD", "CHARGE", "ENGAGED"]

var _map: TerrainMap
var _p: Player
var _e: Enemy
var _line: Line2D
var _label: Label

func _initialize() -> void:
	var stage := Node2D.new()
	root.add_child(stage)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.16, 0.12)
	bg.position = Vector2(0, 0)
	bg.size = Vector2(1400, 1400)
	stage.add_child(bg)
	_map = TerrainMap.new()
	_map.cell_size = 32
	stage.add_child(_map)
	for c in [Vector2i(20, 20), Vector2i(20, 22)]:
		_map.set_cell(c, TerrainTypes.OBSTACLE)
		var r := ColorRect.new()
		r.color = Color(0.2, 0.8, 0.3)
		r.size = Vector2(32, 32)
		r.position = _map.cell_to_world(c) - Vector2(16, 16)
		stage.add_child(r)
	var centre := _map.cell_to_world(Vector2i(20, 20))
	_p = load("res://scenes/player.tscn").instantiate()
	_p.name = "Player"
	_p.set_process(false)
	stage.add_child(_p)
	_p.set_physics_process(false)
	_e = load("res://scenes/enemy.tscn").instantiate()
	_e.player_path = NodePath("../Player")
	_e.terrain = _map
	stage.add_child(_e)
	_e.set_physics_process(false)
	_line = Line2D.new()
	_line.width = 3
	stage.add_child(_line)
	var cam := Camera2D.new()
	cam.position = centre + Vector2(0, 60)
	cam.zoom = Vector2(2.2, 2.2)
	stage.add_child(cam)
	cam.make_current()
	var hud := CanvasLayer.new()
	stage.add_child(hud)
	_label = Label.new()
	_label.position = Vector2(24, 24)
	_label.add_theme_font_size_override("font_size", 40)
	hud.add_child(_label)
	await process_frame
	_e.global_position = centre + Vector2(-220, 0)
	_p.global_position = centre + Vector2(220, 0)
	_e.set_physics_process(true)
	for i in 420:
		var t := clampf(float(i - 240) / 60.0, 0.0, 1.0)
		_p.global_position = centre + Vector2.from_angle(t * PI * 0.5) * 220.0
		_p.global_rotation = (_e.global_position - _p.global_position).angle()
		await physics_frame
		_overlay(i)
		await process_frame
	quit(0)

func _overlay(i: int) -> void:
	var cover = (_e.get("_behavior") as RefCounted).get("_cover")
	var st: int = cover.get("_state")
	var shielded: bool = cover._sheltered(_map, _e.global_position, _p.global_position)
	_line.points = PackedVector2Array([_e.global_position, _p.global_position])
	_line.default_color = Color(1, 0.9, 0.2) if shielded else Color(1, 0.2, 0.2)
	var phase := "aimed, player static" if i < 240 else "aimed, player strafing round the cover"
	_label.text = "frame %d  %s\nmob state: %s   sightline %s" % [i, phase, STATE_NAMES[st], "BLOCKED" if shielded else "OPEN"]
	if i % 30 == 0:
		print("[408rec] f=%d state=%s e=%s p=%s shielded=%s" % [i, STATE_NAMES[st], _e.global_position, _p.global_position, shielded])
