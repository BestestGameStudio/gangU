extends SceneTree
## #305 harness: Spirit Punch Signature freeze bubble (PR-D, new node only).
## Contract under test: an expanding bubble of fixed radius greyscales its
## area; only the player can move. Enemies, summons and projectiles -
## including ones spawned INSIDE the bubble after it forms - are frozen via
## duck-typed set_frozen(true), released with set_frozen(false) when the
## bubble ends after its duration, and the bubble then frees itself.
## Owner decision: the bubble stays anchored where it is cast.
## Run headless:
##   godot --headless --script scripts/test305_freeze_bubble.gd

const FreezeBubbleScript := preload("res://scripts/freeze_bubble.gd")

const RADIUS := 220.0
const DURATION := 0.5  # shortened for the harness; contract duration is 5s

var _checks := 0
var _failures := 0
var _root_node: Node2D
var _bubble: Area2D
var _enemy: MockFreezableBody
var _projectile: MockFreezableArea
var _player: CharacterBody2D
var _late_projectile: MockFreezableArea
var _anchored: Area2D
var _frame := 0
var _phase := 0
var _ended_emitted := false


class MockFreezableBody:
	extends CharacterBody2D
	var frozen := false
	var freeze_calls: Array[bool] = []
	func set_frozen(v: bool) -> void:
		frozen = v
		freeze_calls.append(v)


class MockFreezableArea:
	extends Area2D
	var frozen := false
	var freeze_calls: Array[bool] = []
	func set_frozen(v: bool) -> void:
		frozen = v
		freeze_calls.append(v)


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if ok:
		print("PASS: %s" % msg)
	else:
		_failures += 1
		print("FAIL: %s" % msg)


func _initialize() -> void:
	_root_node = Node2D.new()
	root.add_child(_root_node)

	_enemy = MockFreezableBody.new()
	_enemy.add_to_group(ActorCollision.ENEMY_GROUP)
	_enemy.add_child(_circle(8.0))
	_root_node.add_child(_enemy)
	_enemy.global_position = Vector2(100, 0)

	_projectile = MockFreezableArea.new()
	_projectile.add_child(_circle(4.0))
	_root_node.add_child(_projectile)
	_projectile.global_position = Vector2(50, 50)

	_player = CharacterBody2D.new()
	_player.add_to_group(ActorCollision.PLAYER_GROUP)
	_player.add_child(_circle(8.0))
	_root_node.add_child(_player)
	_player.global_position = Vector2(0, 80)

	_bubble = FreezeBubbleScript.spawn(_root_node, Vector2.ZERO, RADIUS, DURATION)
	_bubble.ended.connect(func() -> void: _ended_emitted = true)


func _circle(r: float) -> CollisionShape2D:
	var c := CollisionShape2D.new()
	var s := CircleShape2D.new()
	s.radius = r
	c.shape = s
	return c


func _physics_process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		0:  # wait for expansion to finish; everything inside at spawn
			if _frame >= 20:
				_check(_bubble.is_frozen_actor(_enemy), "enemy inside at spawn is frozen")
				_check(_bubble.is_frozen_actor(_projectile), "projectile inside at spawn is frozen")
				_check(not _bubble.is_frozen_actor(_player), "player inside bubble is NOT frozen")
				# deferred spawn: new projectile appears inside mid-life
				_late_projectile = MockFreezableArea.new()
				_late_projectile.add_child(_circle(4.0))
				_root_node.add_child(_late_projectile)
				_late_projectile.global_position = Vector2(-40, -40)
				_phase = 1
				_frame = 0
		1:  # verify the late spawn froze; bubble stays where it was cast
			if _frame >= 4:
				_check(_bubble.is_frozen_actor(_late_projectile), "projectile spawned inside mid-life is frozen")
				_check(_late_projectile.frozen, "late projectile received set_frozen(true)")
				_anchored = FreezeBubbleScript.spawn(_root_node, Vector2(900, 900), 40.0, 60.0)
				_player.global_position = Vector2(500, 500)
				_phase = 10
				_frame = 0
		10:
			if _frame >= 3:
				_check(is_equal_approx(_anchored.global_position.x, 900.0), "bubble stays anchored at cast point (player moved away)")
				_check(_bubble.global_position.distance_to(Vector2.ZERO) < 1.0, "main bubble also stays anchored")
				_anchored.queue_free()
				_phase = 2
				_frame = 0
		2:  # wait out the duration; bubble must release and free itself
			if not is_instance_valid(_bubble):
				_phase = 3
		3:
			_check(_ended_emitted, "bubble emitted ended before freeing")
			_check(_enemy.freeze_calls == [true, false], "enemy released with set_frozen(false) at end")
			_check(_projectile.freeze_calls == [true, false], "projectile released with set_frozen(false) at end")
			_check(_late_projectile.freeze_calls == [true, false], "late projectile released with set_frozen(false) at end")
			_check(not _enemy.frozen and not _projectile.frozen and not _late_projectile.frozen, "all actors unfrozen after bubble ends")
			print("---\n%d checks, %d failures" % [_checks, _failures])
			quit(1 if _failures > 0 else 0)
	return false
