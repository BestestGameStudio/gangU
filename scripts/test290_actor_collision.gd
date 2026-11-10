extends SceneTree
## #290 harness: players and enemies never physically collide.
## Real engine physics (move_and_slide on physics frames, real Area2D
## projectile hits); no collision layers zeroed. Proves:
## - an enemy chasing a player overlaps it instead of stopping at the hull,
## - a moving player passes straight through an idle enemy (no block/push),
## - both spawn orders (player first / enemy first) get the exceptions,
## - production wiring (explicit player_path target; Player.find fallback) works,
## - controls: player still blocked by a StaticBody2D, contact damage and
##   projectile hits unchanged. (e) now asserts #493: enemies pass through
##   each other (see test493_enemy_overlap.gd).

var failures := 0

func _check(cond: bool, name: String) -> void:
	if not cond:
		failures += 1
	print("[290] ", name, " -> ", "PASS" if cond else "FAIL")

## #515: "passes through" = neither body's mask contains the other's layer
## (replaces the old ActorCollision per-pair exceptions).
func _passes_through(a: CollisionObject2D, b: CollisionObject2D) -> bool:
	return (a.collision_mask & b.collision_layer) == 0 and (b.collision_mask & a.collision_layer) == 0

func _frames(n: int) -> void:
	for i in range(n):
		await physics_frame

func _player(stage: Node2D, pos: Vector2) -> Player:
	var p: Player = preload("res://scenes/player.tscn").instantiate()
	p.position = pos
	stage.add_child(p)
	return p

func _enemy(stage: Node2D, pos: Vector2, target_path := NodePath("")) -> Enemy:
	var e: Enemy = preload("res://scenes/enemy.tscn").instantiate()
	e.player_path = target_path
	e.position = pos
	e.contact_damage = 0 ## movement legs: keep the player alive and still
	stage.add_child(e)
	return e

## Push `body` along `vel` for `n` physics frames with real move_and_slide.
## Returns the number of slide collisions seen against `other`.
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

func _initialize() -> void:
	var stage := Node2D.new()
	stage.name = "Stage"
	root.add_child(stage)
	await process_frame

	# --- (a) enemy chases a stationary player and overlaps it ---
	var p1 := _player(stage, Vector2(200, 200))
	var e1 := _enemy(stage, Vector2(300, 200))
	await _frames(2)
	_check(_passes_through(p1, e1),
		"player and enemy layers/masks leave each other out")
	await _frames(90) ## 110 px/s * 1.5 s > 100 px gap
	var d1 := e1.global_position.distance_to(p1.global_position)
	_check(d1 <= 10.0, "chasing enemy reaches the player's centre instead of stopping at the 29px hull (d=%.1f)" % d1)
	_check(p1.global_position.distance_to(Vector2(200, 200)) < 0.5, "enemy did not push the player")
	e1.queue_free()
	p1.queue_free()
	await _frames(2)

	# --- (b) moving player passes straight through an idle enemy ---
	var e2 := _enemy(stage, Vector2(600, 200))
	await _frames(1)
	var p2 := _player(stage, Vector2(500, 200))
	await _frames(2)
	_check(_passes_through(p2, e2),
		"enemy-first spawn: same layers/masks")
	e2.set_physics_process(false)
	p2.set_physics_process(false)
	var hits2 := await _drive(p2, Vector2(320, 0), 60, e2) ## 320 px over 1 s
	_check(hits2 == 0, "no slide collisions against the enemy while walking through it")
	_check(p2.global_position.x > 750.0, "player ended past the enemy (x=%.1f)" % p2.global_position.x)
	_check(e2.global_position.distance_to(Vector2(600, 200)) < 0.5, "player did not push the enemy")
	e2.queue_free()
	p2.queue_free()
	await _frames(2)

	# --- (c) production wiring: enemy targets via player_path ---
	var p3 := _player(stage, Vector2(200, 600))
	await _frames(1)
	var e3 := _enemy(stage, Vector2(300, 600), NodePath(p3.get_path()))
	await _frames(2)
	_check(not p3.is_in_group("player"), "fixture player is outside the legacy 'player' group")
	_check(_passes_through(e3, p3), "player_path-wired target also passes through")
	await _frames(90)
	_check(e3.global_position.distance_to(p3.global_position) <= 10.0, "production-wired enemy also overlaps the player")
	e3.queue_free()
	p3.queue_free()
	await _frames(2)

	# --- (d) control: player is still blocked by a static wall ---
	var wall := StaticBody2D.new()
	var wshape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20, 200)
	wshape.shape = rect
	wall.add_child(wshape)
	wall.position = Vector2(1100, 1000)
	stage.add_child(wall)
	var p4 := _player(stage, Vector2(1000, 1000))
	p4.set_physics_process(false)
	await _frames(2)
	var hits4 := await _drive(p4, Vector2(320, 0), 40, wall)
	_check(hits4 > 0 and p4.global_position.x < 1100.0, "player still blocked by a StaticBody2D (x=%.1f)" % p4.global_position.x)
	p4.queue_free()
	wall.queue_free()
	await _frames(2)

	# --- (e) #493 supersedes the old control: enemies pass through each other ---
	var p5 := _player(stage, Vector2(3000, 3000))
	var ea := _enemy(stage, Vector2(1500, 1500))
	var eb := _enemy(stage, Vector2(1600, 1500))
	await _frames(2)
	ea.set_physics_process(false)
	eb.set_physics_process(false)
	_check(_passes_through(ea, eb), "#493: enemy layers/masks leave each other out")
	var hits5 := await _drive(ea, Vector2(200, 0), 40, eb)
	_check(hits5 == 0 and ea.global_position.x > 1600.0, "#493: enemy passes through another enemy (x=%.1f)" % ea.global_position.x)
	ea.queue_free()
	eb.queue_free()
	p5.queue_free()
	await _frames(2)

	# --- (f) unchanged: contact damage still lands while overlapping ---
	var p6 := _player(stage, Vector2(200, 1400))
	var e6: Enemy = preload("res://scenes/enemy.tscn").instantiate()
	e6.position = Vector2(260, 1400)
	stage.add_child(e6)
	await _frames(30)
	_check(p6.hp < p6.max_hp, "contact damage still applies (hp=%d)" % p6.hp)
	e6.queue_free()
	p6.queue_free()
	await _frames(2)

	# --- (g) unchanged: a player projectile still hits an enemy ---
	var p7 := _player(stage, Vector2(2000, 2400))
	var e7 := _enemy(stage, Vector2(2000, 2000))
	e7.set_physics_process(false)
	await _frames(2)
	var s := Spell.new()
	s.mode = Spell.CastMode.PROJECTILE
	s.spell_name = "Fixture Bolt"
	s.damage = 7.0
	s.radius = 4.0
	s.range = 600.0
	s.projectile_speed = 500.0
	var pr: Projectile = preload("res://scenes/projectile.tscn").instantiate()
	pr.setup(s, Vector2.DOWN, p7)
	stage.add_child(pr)
	pr.global_position = Vector2(2000, 1940)
	await _frames(20)
	_check(e7.hp < e7.max_hp, "projectile hit on enemy unchanged (hp=%d)" % e7.hp)

	await process_frame
	await process_frame
	if failures == 0:
		print("[290] RESULT: ALL PASS")
	else:
		print("[290] FAILURES: ", failures)
	quit(failures)
