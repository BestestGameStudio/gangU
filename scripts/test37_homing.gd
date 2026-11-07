extends SceneTree
## #37 homing harness (headless, AUTHOR-WRITTEN proof - lead reviews independently).
## Fixture: a bare Node2D world built here with idle enemies and direct
## projectile spawns. NOT the production scene (main.tscn enemies would chase
## the player); physics itself is real (Area2D body_entered, _physics_process).
## Covers: HOMING vocabulary, homing resource/upgrade validity, no-target
## straight flight, in-range steer with correct sign, per-frame turn cap
## (6 rad/s), out-of-range no steer, nearest-of-two targeting, homing-only
## first-hit despawn, homing+piercing continue with one hit per body.

const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const BASE_BEAM := preload("res://resources/spells/fire_ball_beam.tres")
const HOMING_BEAM := preload("res://resources/spells/fire_ball_beam_homing.tres")
const HOMING_UPGRADE := preload("res://resources/upgrades/fireball_m2_beam_homing.tres")

var fails := 0
var phase := 0
var t := 0.0
var world: Node2D
var e1; var e2; var p
var last_angle := 0.0
var max_turn := 0.0

func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: " + label)
	else:
		fails += 1
		printerr("FAIL: " + label)

func spawn_enemy(pos: Vector2):
	var e = ENEMY_SCENE.instantiate()
	world.add_child(e)
	e.global_position = pos
	return e

func spawn_projectile(spell: Spell, pos: Vector2, dir: Vector2 = Vector2.RIGHT):
	var pr = PROJECTILE_SCENE.instantiate()
	pr.setup(spell, dir, world)
	world.add_child(pr)
	pr.global_position = pos
	return pr

func clear_world() -> void:
	for c in world.get_children():
		c.queue_free()

func _initialize() -> void:
	# --- vocabulary + resources ---
	check(SpellTags.is_valid(SpellTags.HOMING), "HOMING in tag vocabulary")
	check(SpellTags.HOMING in SpellTags.ALL, "HOMING in ALL")
	check(SpellTags.unknown_tags(HOMING_BEAM.tags).is_empty(), "homing beam tags all known")
	check(HOMING_BEAM.tags == [&"projectile", &"burn", &"homing"], "homing beam carries projectile/burn/homing")
	check(HOMING_BEAM.cooldown == 1.2 and HOMING_BEAM.damage == 25.0 and HOMING_BEAM.radius == 14.0
		and HOMING_BEAM.range == 900.0 and HOMING_BEAM.projectile_speed == 2000.0,
		"homing beam keeps exact Beam params (speed/range/dmg/cd unchanged)")
	check(HOMING_BEAM.projectile_color == Color(0.4, 0.9, 1, 1), "homing beam color (0.4,0.9,1,1)")
	check(not BASE_BEAM.tags.has(SpellTags.HOMING), "base beam has no homing tag")
	check(HOMING_UPGRADE.id == &"fireball_m2_beam_homing" and HOMING_UPGRADE.xp_threshold == 15
		and HOMING_UPGRADE.source_spell == BASE_BEAM and HOMING_UPGRADE.result_spell == HOMING_BEAM,
		"homing upgrade mirrors piercing (source Beam, threshold 15)")
	world = Node2D.new()
	root.add_child(world)

func _physics_process(_delta: float) -> bool:
	if is_instance_valid(p):
		var a: float = p.direction.angle()
		if last_angle != 0.0 or a != 0.0:
			max_turn = max(max_turn, absf(wrapf(a - last_angle, -PI, PI)))
		last_angle = a
	return false

func _process(delta: float) -> bool:
	t += delta
	match phase:
		0:
			# No target in range: homing projectile flies straight.
			p = spawn_projectile(HOMING_BEAM, Vector2(50, 300))
			phase = 1; t = 0.0
		1:
			if t > 0.25:
				check(p.direction.is_equal_approx(Vector2.RIGHT), "no target: flies straight (direction unchanged)")
				clear_world()
				phase = 2; t = 0.0
		2:
			# Target in range, above the flight line: steer sign toward it, capped.
			e1 = spawn_enemy(Vector2(400, 100)) # above the y=300 line, within 400px
			p = spawn_projectile(HOMING_BEAM, Vector2(50, 300))
			max_turn = 0.0
			phase = 3; t = 0.0
		3:
			if t > 0.05: # a few physics frames in, before contact
				check(p.direction.y < 0.0, "in-range target above: steer sign correct (turns up)")
				var cap: float = 6.0 * (1.0 / 60.0) + 0.001
				check(max_turn <= cap, "turn capped at 6 rad/s (max per-frame turn %.4f <= %.4f)" % [max_turn, cap])
				phase = 4; t = 0.0
		4:
			if t > 0.6:
				check(e1.hp == 5.0, "homing-only: first hit damages (30-25=5)")
				check(not is_instance_valid(p), "homing-only: first hit despawns projectile")
				clear_world()
				phase = 5; t = 0.0
		5:
			# Target beyond HOMING_RANGE (400px): no steer.
			e1 = spawn_enemy(Vector2(50, -250)) # 550px straight up: stays beyond 400px while the shot flies right
			p = spawn_projectile(HOMING_BEAM, Vector2(50, 300))
			phase = 6; t = 0.0
		6:
			if t > 0.1:
				check(p.direction.is_equal_approx(Vector2.RIGHT), "out-of-range target (550px): no steer")
				clear_world()
				phase = 7; t = 0.0
		7:
			# Nearest of two: near target above, far target below; steer up.
			e1 = spawn_enemy(Vector2(400, 180)) # ~150px from spawn line
			e2 = spawn_enemy(Vector2(430, 460)) # ~330px from spawn
			p = spawn_projectile(HOMING_BEAM, Vector2(50, 300))
			phase = 8; t = 0.0
		8:
			if t > 0.05:
				check(p.direction.y < 0.0, "nearest of two: steers toward nearer (upper) enemy")
				clear_world()
				phase = 9; t = 0.0
		9:
			# Homing + PIERCING fixture spell: continue past first body, one hit each.
			var hp_spell: Spell = HOMING_BEAM.duplicate()
			hp_spell.tags = [&"projectile", &"burn", &"homing", &"piercing"]
			e1 = spawn_enemy(Vector2(250, 300))
			e2 = spawn_enemy(Vector2(450, 300))
			p = spawn_projectile(hp_spell, Vector2(50, 300))
			phase = 10; t = 0.0
		10:
			if t > 0.35:
				check(e1.hp == 5.0, "homing+piercing: first enemy damaged exactly once (no orbit rehit)")
				check(e2.hp == 5.0, "homing+piercing: second enemy damaged exactly once (continued past first)")
				phase = 11; t = 0.0
		11:
			if t > 0.6:
				check(not is_instance_valid(p), "homing+piercing: projectile still freed by range expiry")
				print("test37_homing: %d failures" % fails)
				quit(fails)
	return false
