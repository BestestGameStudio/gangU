extends SceneTree
## #198: Shift dash. Checks the input binding, dash distance/direction,
## idle fallback direction, cooldown gating, and that death blocks dashing.

var _area: Node2D
var _player: Player
var _frames := 0
var _fails := 0
var _start := Vector2.ZERO
var _started_dirs: Array = []
var _ended := 0

func _initialize() -> void:
	_area = Node2D.new()
	get_root().add_child(_area)
	current_scene = _area
	_player = load("res://scenes/player.tscn").instantiate()
	_player.position = Vector2(400, 300)
	_area.add_child(_player)
	_player.dash_started.connect(func(d: Vector2) -> void: _started_dirs.append(d))
	_player.dash_ended.connect(func() -> void: _ended += 1)

func _check(label: String, ok: bool) -> void:
	if not ok:
		_fails += 1
	print("[198] ", label, " -> ", "PASS" if ok else "FAIL")

func _physics_process(_dt: float) -> bool:
	_frames += 1
	match _frames:
		2:
			var shift_bound := false
			for ev in InputMap.action_get_events(&"dash"):
				if ev is InputEventKey and ev.physical_keycode == KEY_SHIFT:
					shift_bound = true
			_check("dash action bound to Shift", shift_bound)
			_start = _player.global_position
			_check("dash starts to the right", _player.try_dash(Vector2.RIGHT))
			_check("is_dashing() true", _player.is_dashing())
			_check("second dash refused while dashing", not _player.try_dash(Vector2.UP))
		14:
			# 0.09s at 60 fps = ~6 physics frames (#450); dash is over by now.
			var moved := _player.global_position - _start
			print("[198] moved ", moved)
			_check("dash ended", not _player.is_dashing() and _ended == 1)
			_check("moved ~81 px right (#450: 60..100)", moved.x > 60.0 and moved.x < 100.0 and absf(moved.y) < 1.0)
			_check("player stops after dash (no input)", _player.velocity.length() < 1.0)
			_check("cooldown still running", _player.dash_cooldown_remaining() > 0.0)
			_check("dash refused on cooldown", not _player.try_dash(Vector2.LEFT))
		60:
			_check("cooldown expired after 0.6s", is_zero_approx(_player.dash_cooldown_remaining()))
			_check("dash with no input starts after cooldown", _player.try_dash(Vector2.ZERO))
			# No WASD input has happened in this harness, so the fallback is the
			# default last-move direction (down).
			_check("idle fallback direction is DOWN", _started_dirs.size() == 2 and _started_dirs[1] == Vector2.DOWN)
		110:
			_player.apply_damage(_player.max_hp)
		112:
			_check("dash cancelled/refused when dead", not _player.try_dash(Vector2.RIGHT) and not _player.is_dashing())
			print("[198] DONE fails=", _fails)
			print("RESULT: ", "ALL PASS" if _fails == 0 else "FAIL")
			quit(1 if _fails > 0 else 0)
			return true
	return false
