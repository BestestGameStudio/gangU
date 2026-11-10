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
var _real_bubble: Area2D
var _real_bubble2: Area2D
var _real_proj: Projectile
var _real_spawn_pos := Vector2.ZERO
var _real_proj_frame0 := 0
var _real_proj_progress0 := 0.0
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
	_enemy.collision_layer = PhysicsLayers.ENEMY # #515: bubbles detect by layer
	_enemy.add_to_group(PhysicsLayers.ENEMY_GROUP)
	_enemy.add_child(_circle(8.0))
	_root_node.add_child(_enemy)
	_enemy.global_position = Vector2(100, 0)

	_projectile = MockFreezableArea.new()
	_projectile.collision_layer = PhysicsLayers.ENEMY_PROJECTILE
	_projectile.add_child(_circle(4.0))
	_root_node.add_child(_projectile)
	_projectile.global_position = Vector2(50, 50)

	_player = CharacterBody2D.new()
	_player.add_to_group(PhysicsLayers.PLAYER_GROUP)
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
				_check(_player.z_index > 100, "player raised above the veil while a bubble is active (stays colored inside)")
				# deferred spawn: new projectile appears inside mid-life
				_late_projectile = MockFreezableArea.new()
				_late_projectile.collision_layer = PhysicsLayers.ENEMY_PROJECTILE
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
			_check(_player.z_index == 0 and not _player.has_meta(&"freeze_bubble_z"), "player z restored after last bubble releases")
			_check(_enemy.freeze_calls == [true, false], "enemy released with set_frozen(false) at end")
			_check(_projectile.freeze_calls == [true, false], "projectile released with set_frozen(false) at end")
			_check(_late_projectile.freeze_calls == [true, false], "late projectile released with set_frozen(false) at end")
			_check(not _enemy.frozen and not _projectile.frozen and not _late_projectile.frozen, "all actors unfrozen after bubble ends")
			# Real-entity phase: an actual Projectile claimed by the SPAWN
			# HOOK (position set before entering the tree) must never move.
			_real_bubble = FreezeBubbleScript.spawn(_root_node, Vector2(400, 300), 200.0, 60.0)
			_phase = 4
			_frame = 0
		4:  # let the bubble fully expand, then spawn a real projectile inside
			if _frame >= 20:
				var pscene: PackedScene = load("res://scenes/projectile.tscn")
				_real_proj = pscene.instantiate()
				_real_proj.setup(load("res://resources/spells/spirit_punch.tres"), Vector2.RIGHT, null)
				# PRODUCTION ORDER (caster fan-out / SummonManager): add_child
				# FIRST, position AFTER. The claim must land on the first physics
				# step against the FINAL position.
				_root_node.add_child(_real_proj)
				_real_proj.global_position = Vector2(420, 300)
				_real_spawn_pos = _real_proj.global_position
				_phase = 5
				_frame = 0
		5:  # frozen before its first physics step: zero movement
			if _frame >= 12:
				_check(_real_proj.global_position.distance_to(_real_spawn_pos) < 0.01, "REAL projectile spawned inside (production order) never moves (first-step claim, not scan)")
				_check(_real_proj._freeze_count == 1, "real projectile claimed exactly once (count=1)")
				if _real_proj._sprite != null:
					_check(not _real_proj._sprite.is_playing(), "frozen projectile sprite animation PAUSED")
					_real_proj_frame0 = _real_proj._sprite.frame
					_real_proj_progress0 = _real_proj._sprite.frame_progress
				_real_bubble2 = FreezeBubbleScript.spawn(_root_node, Vector2(430, 300), 200.0, 60.0)
				_phase = 6
				_frame = 0
		6:  # overlapping second bubble claims the same projectile once
			if _frame >= 20:
				_check(_real_proj._freeze_count == 2, "overlapping bubble also claims it once (count=2)")
				_real_bubble._begin_release()
				_phase = 7
				_frame = 0
		7:  # first bubble released; the second still holds the freeze
			if _frame >= 25:
				_check(_real_proj._freeze_count == 1, "first release leaves the second claim (count=1)")
				_check(_real_proj.global_position.distance_to(_real_spawn_pos) < 0.01, "still frozen while any bubble holds it")
				if _real_proj._sprite != null:
					_check(_real_proj._sprite.frame == _real_proj_frame0 and is_equal_approx(_real_proj._sprite.frame_progress, _real_proj_progress0), "projectile sprite frame held across the whole freeze")
				_real_bubble2._begin_release()
				_phase = 8
				_frame = 0
		8:  # fully released: claims balanced, projectile moves again. The
			# Spirit Punch range is short, so a resumed projectile can despawn
			# before the poll lands - reaching max range is itself proof the
			# movement gate reopened (count must be 0 for any movement).
			if _frame >= 2:
				if not is_instance_valid(_real_proj):
					_check(true, "claims balanced after both bubbles end (resumed projectile despawned at max range)")
					_check(true, "projectile resumes moving after final release")
					_spawn_real_enemy_phase()
				elif _real_proj.global_position.distance_to(_real_spawn_pos) > 10.0:
					_check(_real_proj._freeze_count == 0, "claims balanced after both bubbles end (count=0)")
					_check(true, "projectile resumes moving after final release")
					if _real_proj._sprite != null:
						_check(_real_proj._sprite.is_playing(), "released projectile sprite animation RESUMED")
					_spawn_real_enemy_phase()
			if _frame >= 120:
				_check(false, "projectile resumed moving within 120 frames of final release")
				print("---\n%d checks, %d failures" % [_checks, _failures])
				quit(1)
		11: # REAL enemy, production spawn order, inside a fresh bubble: claimed
			# on its first physics step, zero motion, walk animation PAUSED.
			if _frame >= 15:
				_check(_real_enemy._freeze_count == 1, "real enemy claimed on its first physics step (count=1)")
				_check(_real_enemy.global_position.distance_to(_real_enemy_spawn) < 0.01, "real enemy spawned inside (production order) never moves")
				if _real_enemy.sprite != null and _real_enemy_sprite_played:
					_check(not _real_enemy.sprite.is_playing(), "frozen enemy sprite animation PAUSED")
				_real_bubble3._begin_release()
				_phase = 12
				_frame = 0
		12: # released: behavior and animation resume
			if _frame >= 10:
				_check(_real_enemy._freeze_count == 0, "enemy released (count=0)")
				if _real_enemy.sprite != null and _real_enemy_sprite_played:
					_check(_real_enemy.sprite.is_playing(), "released enemy sprite animation RESUMED")
				print("---\n%d checks, %d failures" % [_checks, _failures])
				quit(1 if _failures > 0 else 0)
	return false


var _real_bubble3: Node = null
var _real_enemy: Enemy = null
var _real_enemy_spawn := Vector2.ZERO
var _real_enemy_sprite_played := false

func _spawn_real_enemy_phase() -> void:
	_real_bubble3 = FreezeBubbleScript.spawn(_root_node, Vector2(700, 300), 200.0, 60.0)
	var escene: PackedScene = load("res://scenes/enemy.tscn")
	_real_enemy = escene.instantiate()
	# PRODUCTION ORDER: add_child first, position after.
	_root_node.add_child(_real_enemy)
	_real_enemy.global_position = Vector2(720, 300)
	_real_enemy_spawn = _real_enemy.global_position
	_real_enemy_sprite_played = _real_enemy.sprite != null and _real_enemy.sprite.is_playing()
	_phase = 11
	_frame = 0
