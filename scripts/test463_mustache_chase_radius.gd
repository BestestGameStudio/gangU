extends SceneTree
## #463 harness: bigger chase radius for the basic mustache men (Daniel,
## 2026-11-09: "increase the chase radius of the mustache men so that they
## continue chasing the player while they're still visible on screen";
## bigger fixed number; basic mustache men only).
##   (A) radius selection: a patrol behavior gives the Mustache Warrior
##       scene (cover_seek opt-in, #406) the new 1350 leash, every other
##       patroller keeps 900, and the guard keeps 520.
##   (B) mustache patroller (fixture): engages; KEEPS CHASING at 1000px
##       (past the old 900 leash); gives up past the new 1350.
##   (C) slime patroller (fixture): unchanged - gives up past 900.
## Fixture idioms follow test414 (collisions off, real physics frames).

const DT := 1.0 / 60.0

var failures := 0
var _player_scene: PackedScene
var _enemy_scene: PackedScene
var _slime_scene: PackedScene

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[463] ", label, " -> ", "PASS" if ok else "FAIL")

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _initialize() -> void:
	_player_scene = load("res://scenes/player.tscn")
	_enemy_scene = load("res://scenes/enemy.tscn")
	_slime_scene = load("res://scenes/enemy_slime.tscn")
	_leg_a_radius_selection()
	await _leg_b_mustache_pursuit()
	await _leg_c_slime_unchanged()
	print("[463] DONE failures=", failures)
	if failures == 0:
		print("RESULT: ALL PASS")
	quit(1 if failures > 0 else 0)

func _mk_stage() -> Node2D:
	var stage := Node2D.new()
	stage.name = "Stage463"
	root.add_child(stage)
	return stage

func _mk_player(stage: Node2D, pos: Vector2) -> Player:
	var p: Player = _player_scene.instantiate()
	p.name = "Player"
	p.collision_layer = 0
	p.collision_mask = 0
	p.set_process(false)
	stage.add_child(p)
	p.global_position = pos
	p.set_physics_process(false)
	return p

func _mk_enemy(stage: Node2D, scene: PackedScene, pos: Vector2, definition: EnemyDefinition) -> Enemy:
	var e: Enemy = scene.instantiate()
	e.collision_layer = 0
	e.collision_mask = 0
	e.player_path = NodePath("../Player")
	e.definition = definition # before tree entry so _ready applies it
	e.set_physics_process(false)
	stage.add_child(e)
	e.global_position = pos
	return e

func _teardown(stage: Node2D) -> void:
	stage.queue_free()
	await process_frame
	await process_frame

# --- (A) radius selection ------------------------------------------------------

func _leg_a_radius_selection() -> void:
	var patrol_def: EnemyDefinition = load("res://resources/enemies/overworld_patrol.tres")
	var slime_patrol_def: EnemyDefinition = load("res://resources/enemies/slime_patrol.tres")
	var b := EnemyBehaviorPatrol.new()
	var mustache: Enemy = _enemy_scene.instantiate()
	_check(mustache.cover_seek, "(A) the Mustache Warrior scene opts into cover_seek (the basic mustache man)")
	_check(b._leash_radius(mustache) == EnemyBehaviorPatrol.MUSTACHE_LEASH_RADIUS, "(A) a mustache patroller gets the #463 radius (%.0f)" % b._leash_radius(mustache))
	var slime: Enemy = _slime_scene.instantiate()
	_check(not slime.cover_seek, "(A) the slime does not opt into cover_seek")
	_check(b._leash_radius(slime) == EnemyBehaviorPatrol.PATROL_LEASH_RADIUS, "(A) a slime patroller keeps the #414 radius (%.0f)" % b._leash_radius(slime))
	_check(b._leash_radius(mustache) >= 1322.0, "(A) the #463 radius clears the 1152x648 viewport diagonal")
	var g := EnemyBehaviorGuard.new()
	_check(g._leash_radius(mustache) == EnemyBehaviorGuard.LEASH_RADIUS, "(A) the posted guard keeps its 520 leash")
	mustache.free()
	slime.free()
	_check(patrol_def.behavior is EnemyBehaviorPatrol and slime_patrol_def.behavior is EnemyBehaviorPatrol and patrol_def.behavior.patrol_leash_radius == 900.0 and slime_patrol_def.behavior.patrol_leash_radius == 900.0 and patrol_def.behavior.mustache_leash_radius == 1350.0 and slime_patrol_def.behavior.mustache_leash_radius == 1350.0 and patrol_def.behavior.stroll_fraction == 0.45 and slime_patrol_def.behavior.stroll_fraction == 0.45 and patrol_def.behavior.pause_time == 0.8 and slime_patrol_def.behavior.pause_time == 0.8 and patrol_def.behavior.aggro_radius == 220.0 and slime_patrol_def.behavior.aggro_radius == 220.0 and patrol_def.behavior.leash_radius == 520.0 and slime_patrol_def.behavior.leash_radius == 520.0 and patrol_def.behavior.home_epsilon == 6.0 and slime_patrol_def.behavior.home_epsilon == 6.0, "(A) both definitions use the patrol behavior")

# --- (B) mustache patroller keeps chasing past 900, gives up past 1350 ---------

func _leg_b_mustache_pursuit() -> void:
	var stage := _mk_stage()
	var p: Player = _mk_player(stage, Vector2(1000, 3000)) # far away at first
	var patrol_def: EnemyDefinition = load("res://resources/enemies/overworld_patrol.tres")
	var e: Enemy = _mk_enemy(stage, _enemy_scene, Vector2(1000, 1000), patrol_def)
	await _frames(2) # let _ready build the behavior
	var b := e._behavior as EnemyBehaviorPatrol
	_check(b != null, "(B) the mustache patroller builds a patrol behavior")
	b.configure_route(PackedVector2Array([Vector2(1000, 1000), Vector2(1100, 1000), Vector2(1100, 1100)]))
	await process_frame
	e.global_position = Vector2(1000, 1000)
	# Engage.
	e.set_physics_process(true)
	p.global_position = e.global_position + Vector2(0, -120)
	await _frames(20)
	_check(b.engaged, "(B) it engages a player inside its aggro radius")
	# Past the OLD 900 leash it KEEPS CHASING (Daniel: continue while visible).
	p.global_position = b.engaged_from + Vector2(0, 1000)
	var dist_at_1000: float = e.global_position.distance_to(p.global_position)
	for i in 150:
		await physics_frame
	_check(b.engaged, "(B) still chasing at 1000px (past the old 900 leash)")
	_check(e.global_position.distance_to(p.global_position) < dist_at_1000 - 100.0, "(B) it follows the player (closed > 100px)")
	# Past the NEW 1350 leash it gives up...
	p.global_position = b.engaged_from + Vector2(0, 1500)
	await _frames(4)
	_check(not b.engaged, "(B) it gives up past the 1350px chase distance")
	# ...and still returns to its old route (#414, unchanged).
	e.speed = 600.0
	var wp_before := b.waypoint
	var resumed := false
	for f in 900:
		await physics_frame
		if b.waypoint != wp_before:
			resumed = true
			break
	_check(resumed, "(B) it returns to its old route after giving up")
	await _teardown(stage)

# --- (C) slime patroller unchanged ---------------------------------------------

func _leg_c_slime_unchanged() -> void:
	var stage := _mk_stage()
	var p: Player = _mk_player(stage, Vector2(1000, 3000))
	var slime_def: EnemyDefinition = load("res://resources/enemies/slime_patrol.tres")
	var e: Enemy = _mk_enemy(stage, _slime_scene, Vector2(1000, 1000), slime_def)
	await _frames(2) # let _ready build the behavior
	var b := e._behavior as EnemyBehaviorPatrol
	_check(b != null, "(C) the slime patroller builds a patrol behavior")
	b.configure_route(PackedVector2Array([Vector2(1000, 1000), Vector2(1100, 1000), Vector2(1100, 1100)]))
	await process_frame
	e.global_position = Vector2(1000, 1000)
	e.set_physics_process(true)
	p.global_position = e.global_position + Vector2(0, -120)
	await _frames(20)
	_check(b.engaged, "(C) it engages a player inside its aggro radius")
	# At 700px (inside its 900 leash) it still chases...
	p.global_position = b.engaged_from + Vector2(0, 700)
	for i in 60:
		await physics_frame
	_check(b.engaged, "(C) still chasing at 700px (inside its 900 leash)")
	# ...and past 900 it gives up exactly as before #463.
	p.global_position = b.engaged_from + Vector2(0, 1000)
	await _frames(4)
	_check(not b.engaged, "(C) it still gives up past 900px (unchanged by #463)")
	await _teardown(stage)
