extends SceneTree
## #493 harness: enemies never physically collide with each other (bosses
## included), but still collide with walls/terrain. Player collision is the
## #290 behavior and is not changed here. Real engine physics (move_and_slide
## on physics frames); no collision layers zeroed.
## Proves:
## - both spawn orders pair enemies in both directions,
## - an enemy driven into another passes straight through (0 slide hits,
##   no push on the other body),
## - several chasing enemies stack on the same spot,
## - every boss scene passes through a regular enemy and vice versa,
## - control: an enemy is still blocked by a StaticBody2D wall,

var failures := 0

const BOSS_SCENES := [
	"res://scenes/head_boss.tscn",
	"res://scenes/beast_boss.tscn",
	"res://scenes/mustache_warlord.tscn",
	"res://scenes/defense_wave_boss.tscn",
]

func _check(cond: bool, name: String) -> void:
	if not cond:
		failures += 1
	print("[493] ", name, " -> ", "PASS" if cond else "FAIL")

## #515: "passes through" = neither body's mask contains the other's layer
## (replaces the old ActorCollision per-pair exceptions).
func _passes_through(a: CollisionObject2D, b: CollisionObject2D) -> bool:
	return (a.collision_mask & b.collision_layer) == 0 and (b.collision_mask & a.collision_layer) == 0

func _frames(n: int) -> void:
	for i in range(n):
		await physics_frame

func _player(stage: Node2D, pos: Vector2) -> Player:
	var p: Player = preload("res://scenes/player.tscn").instantiate()
	p.add_to_group("player")
	p.position = pos
	stage.add_child(p)
	p.set_physics_process(false)
	return p

func _enemy(stage: Node2D, pos: Vector2, scene_path := "res://scenes/enemy.tscn") -> Enemy:
	var e: Enemy = load(scene_path).instantiate()
	e.position = pos
	e.contact_damage = 0
	stage.add_child(e)
	return e

func _drive(body: CharacterBody2D, vel: Vector2, n: int, other: Node) -> int:
	var hits := 0
	for i in range(n):
		await physics_frame
		body.velocity = vel
		body.move_and_slide()
		for c in range(body.get_slide_collision_count()):
			if body.get_slide_collision(c).get_collider() == other:
				hits += 1
	return hits

func _all_valid(list: Array) -> bool:
	for e in list:
		if not is_instance_valid(e):
			return false
	return true

func _initialize() -> void:
	var stage := Node2D.new()
	stage.name = "Stage"
	root.add_child(stage)
	current_scene = stage
	await process_frame

	var player := _player(stage, Vector2(5000, 5000))
	player.max_hp = 1000000
	player.hp = 1000000

	# --- (a) spawn order: first and later enemies are paired both ways ---
	var ea := _enemy(stage, Vector2(200, 200))
	ea.set_physics_process(false)
	await _frames(2)
	var eb := _enemy(stage, Vector2(300, 200))
	eb.set_physics_process(false)
	await _frames(2)
	_check(_passes_through(ea, eb),
		"enemy-enemy layers/masks leave each other out")
	_check(_passes_through(ea, player), "#290 player still passes through enemies")

	# --- (b) driven enemy passes straight through another ---
	ea.set_physics_process(false)
	eb.set_physics_process(false)
	var hits := await _drive(ea, Vector2(300, 0), 40, eb) ## 200 px
	_check(hits == 0, "no slide collisions between enemies (hits=%d)" % hits)
	_check(ea.global_position.x > 350.0, "enemy ended past the other enemy (x=%.1f)" % ea.global_position.x)
	_check(eb.global_position.distance_to(Vector2(300, 200)) < 0.5, "other enemy was not pushed")
	ea.queue_free()
	eb.queue_free()
	await _frames(2)

	# --- (c) several chasers stack on the same spot ---
	var target := Vector2(1000, 1000)
	player.global_position = target ## the one fixture player; enemies chase it
	var chasers: Array[Enemy] = []
	for off in [Vector2(-80, 0), Vector2(80, 0), Vector2(0, -80), Vector2(0, 80)]:
		chasers.append(_enemy(stage, target + off))
	await _frames(120)
	var max_d := 0.0
	for c in chasers:
		max_d = maxf(max_d, c.global_position.distance_to(target))
	_check(max_d <= 10.0, "4 chasing enemies all stack on the player's spot (max d=%.1f)" % max_d)
	for c in chasers:
		c.queue_free()
	player.global_position = Vector2(5000, 5000)
	await _frames(2)

	# --- (d) every boss passes through a regular enemy, both directions ---
	var y := 2000.0
	for path: String in BOSS_SCENES:
		var boss := _enemy(stage, Vector2(2000, y), path)
		boss.set_physics_process(false)
		boss.set_process(false)
		var mob := _enemy(stage, Vector2(2200, y))
		mob.set_physics_process(false)
		await _frames(2)
		var name: String = String(path).get_file().get_basename()
		_check(_passes_through(boss, mob),
			"%s: paired with a regular enemy" % name)
		var start_mob := mob.global_position
		var h1 := await _drive(boss, Vector2(600, 0), 40, mob) ## 400 px
		_check(h1 == 0 and boss.global_position.x > 2300.0,
			"%s passes through an enemy (hits=%d x=%.1f)" % [name, h1, boss.global_position.x])
		_check(mob.global_position.distance_to(start_mob) < 0.5, "%s did not push the enemy" % name)
		var start_boss := boss.global_position
		var h2 := await _drive(mob, Vector2(600, 0), 40, boss)
		_check(h2 == 0 and mob.global_position.x > start_boss.x + 50.0,
			"enemy passes through %s (hits=%d)" % [name, h2])
		_check(boss.global_position.distance_to(start_boss) < 0.5, "enemy did not push %s" % name)
		boss.queue_free()
		mob.queue_free()
		await _frames(2)
		y += 400.0

	# --- (e) control: enemies still collide with walls ---
	var wall := StaticBody2D.new()
	var wshape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20, 200)
	wshape.shape = rect
	wall.add_child(wshape)
	wall.position = Vector2(3100, 600)
	stage.add_child(wall)
	var ew := _enemy(stage, Vector2(3000, 600))
	await _frames(2)
	ew.set_physics_process(false)
	var hw := await _drive(ew, Vector2(300, 0), 40, wall)
	_check(hw > 0 and ew.global_position.x < 3100.0, "enemy still blocked by a wall (x=%.1f)" % ew.global_position.x)
	ew.queue_free()
	wall.queue_free()
	await _frames(2)

	player.queue_free()

	await process_frame
	await process_frame
	if failures == 0:
		print("[493] RESULT: ALL PASS")
	else:
		print("[493] FAILURES: ", failures)
	quit(failures)
