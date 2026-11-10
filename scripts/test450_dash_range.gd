extends SceneTree
## #450: player dash range nerfed 40% (135 px -> 81 px). Distance only:
## dash speed (900) and cooldown (0.6s) are unchanged, and the distance is
## exactly dash_speed * dash_duration (no rounding up to a whole frame).

var _area: Node2D
var _player: Player
var _frames := 0
var _fails := 0
var _start := Vector2.ZERO

func _initialize() -> void:
	_area = Node2D.new()
	get_root().add_child(_area)
	current_scene = _area
	_player = load("res://scenes/player.tscn").instantiate()
	_player.position = Vector2(400, 300)
	_area.add_child(_player)

func _check(label: String, ok: bool) -> void:
	if not ok:
		_fails += 1
	print("[450] ", label, " -> ", "PASS" if ok else "FAIL")

func _physics_process(_dt: float) -> bool:
	_frames += 1
	match _frames:
		2:
			_check("dash_speed unchanged at 900", is_equal_approx(_player.dash_speed, 900.0))
			_check("dash_cooldown unchanged at 0.6s", is_equal_approx(_player.dash_cooldown, 0.6))
			var base := _player.dash_speed * _player.dash_duration
			print("[450] base dash distance ", base)
			_check("base dash distance is 81 px (135 - 40%)", absf(base - 81.0) < 0.01)
			_start = _player.global_position
			_check("dash starts", _player.try_dash(Vector2.RIGHT))
		20:
			var moved := _player.global_position - _start
			print("[450] moved ", moved)
			_check("dash finished", not _player.is_dashing())
			_check("travelled 81 px (+-1)", absf(moved.x - 81.0) <= 1.0 and absf(moved.y) < 0.01)
			_start = _player.global_position
		60:
			_check("dash ready again after cooldown", _player.try_dash(Vector2.LEFT))
		80:
			var moved_left := _player.global_position - _start
			print("[450] moved left ", moved_left)
			_check("second dash also 81 px", absf(moved_left.x + 81.0) <= 1.0)
			print("[450] DONE fails=", _fails)
			print("RESULT: ", "ALL PASS" if _fails == 0 else "FAIL")
			quit(1 if _fails > 0 else 0)
			return true
	return false
