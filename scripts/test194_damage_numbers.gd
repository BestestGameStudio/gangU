extends SceneTree
## Damage numbers on enemy hits: spawn, text, position, rise, fade, cleanup,
## killing hit, dead/zero-damage no-op, never on the Player, boss coverage.
## Run: Godot --headless --path . -s res://scripts/test194_damage_numbers.gd

var _failures: int = 0
var _frames: int = 0
var _elapsed: float = 0.0
var _stage: int = 0
var _hit_area: Node2D
var _kill_area: Node2D
var _player_area: Node2D
var _boss_area: Node2D
var _enemy: Enemy
var _victim: Enemy
var _boss: Enemy
var _player: Player
var _number_ref: WeakRef
var _kill_ref: WeakRef
var _start_y: float = 0.0
var _hit_at: float = 0.0

func _check(label: String, ok: bool) -> void:
	if ok:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)

func _numbers(parent: Node) -> Array[DamageNumber]:
	var out: Array[DamageNumber] = []
	for n in parent.get_children():
		if n is DamageNumber and not n.is_queued_for_deletion():
			out.append(n)
	return out

func _texts(parent: Node) -> PackedStringArray:
	var out: PackedStringArray = []
	for n in _numbers(parent):
		out.append((n.get_child(0) as Label).text)
	return out

func _area() -> Node2D:
	var a: Node2D = Node2D.new()
	get_root().add_child(a)
	return a

func _spawn(scene: String, parent: Node2D, at: Vector2) -> Node2D:
	var n: Node2D = load(scene).instantiate()
	n.position = at
	parent.add_child(n)
	return n

func _initialize() -> void:
	_hit_area = _area()
	_kill_area = _area()
	_player_area = _area()
	_boss_area = _area()
	_enemy = _spawn("res://scenes/enemy.tscn", _hit_area, Vector2(300, 300)) as Enemy
	_victim = _spawn("res://scenes/enemy.tscn", _kill_area, Vector2(500, 200)) as Enemy
	_boss = _spawn("res://scenes/mustache_warlord.tscn", _boss_area, Vector2(700, 400)) as Enemy
	_player = _spawn("res://scenes/player.tscn", _player_area, Vector2(100, 100)) as Player

func _process(dt: float) -> bool:
	_frames += 1
	_elapsed += dt
	match _stage:
		0:
			if _frames >= 2:
				_enemy.apply_damage(7)
				_check("hit: enemy hp 30 - 7 = 23", _enemy.hp == 23)
				_enemy.apply_damage(0)
				_victim.apply_damage(30)
				_victim.apply_damage(5)
				_boss.apply_damage(7)
				_player.apply_damage(7)
				_check("player: hp math unchanged (100 - 7 = 93)", _player.hp == 93)
				_stage = 1
		1:
			var nums: Array[DamageNumber] = _numbers(_hit_area)
			_check("hit: exactly one number in the enemy's parent", nums.size() == 1)
			_check("hit: number shows \"7\"", _texts(_hit_area) == PackedStringArray(["7"]))
			_check("zero damage: shows nothing", nums.size() == 1)
			if nums.size() == 1:
				_check("hit: number at the enemy's position", nums[0].position.x == 300.0 and nums[0].position.y <= 300.0 and nums[0].position.y > 296.0)
				_check("hit: number drawn above enemies", nums[0].z_index > _enemy.z_index)
				_number_ref = weakref(nums[0])
				_start_y = nums[0].position.y
			_check("kill: victim freed", not is_instance_valid(_victim))
			_check("kill: killing hit shows \"30\", dead enemy shows nothing more",
				_texts(_kill_area) == PackedStringArray(["30"]))
			var kills: Array[DamageNumber] = _numbers(_kill_area)
			if kills.size() == 1:
				_kill_ref = weakref(kills[0])
			_check("boss: warlord hit shows \"7\"", _texts(_boss_area) == PackedStringArray(["7"]))
			_check("boss: hp math unchanged (300 - 7 = 293)", _boss.hp == 293)
			_check("player: shows nothing", _numbers(_player_area).is_empty())
			_hit_at = _elapsed
			_stage = 2
		2:
			if _elapsed - _hit_at >= 0.3:
				var n: DamageNumber = _number_ref.get_ref() if _number_ref != null else null
				_check("hit: number still alive mid-flight", n != null)
				if n != null:
					_check("hit: number rose (y decreased)", n.position.y < _start_y)
					_check("hit: number fading (alpha < 1)", n.modulate.a < 1.0)
				var k: DamageNumber = _kill_ref.get_ref() if _kill_ref != null else null
				_check("kill: number survives the freed enemy", k != null and k.is_inside_tree())
				_stage = 3
		3:
			if _elapsed - _hit_at >= 1.0:
				_check("cleanup: hit number freed within 1s", _number_ref != null and _number_ref.get_ref() == null)
				_check("cleanup: kill number freed within 1s", _kill_ref != null and _kill_ref.get_ref() == null)
				_check("cleanup: no number remnants", _numbers(_hit_area).is_empty()
					and _numbers(_kill_area).is_empty() and _numbers(_boss_area).is_empty())
				print("DONE failures=", _failures)
				quit(0 if _failures == 0 else 1)
				return true
	return false
