extends SceneTree
## #37 piercing harness (headless, AUTHOR-WRITTEN proof - lead reviews independently).
## Fixture: a bare Node2D world built here with idle enemies and direct
## projectile spawns. NOT the production scene (main.tscn enemies would chase
## the player and break alignment); physics itself is real (Area2D body_entered).
## Covers: PIERCING vocabulary, untagged base spell unchanged (despawn on first
## hit), piercing damages two aligned enemies once each (no double-hit),
## piercing projectile continues past the first body, range expiry intact.

const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const BASE_BEAM := preload("res://resources/spells/fire_ball_beam.tres")
const PIERCING_BEAM := preload("res://resources/spells/fire_ball_beam_piercing.tres")

var fails := 0
var phase := 0
var t := 0.0
var world: Node2D
var e1; var e2; var p

func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: " + label)
	else:
		fails += 1
		printerr("FAIL: " + label)

func spawn_enemy(x: float):
	var e = ENEMY_SCENE.instantiate()
	world.add_child(e)
	e.global_position = Vector2(x, 0)
	return e

func spawn_projectile(spell: Spell):
	var pr = PROJECTILE_SCENE.instantiate()
	pr.setup(spell, Vector2.RIGHT, world)
	world.add_child(pr)
	pr.global_position = Vector2(50, 0)
	return pr

func _initialize() -> void:
	# --- vocabulary ---
	check(SpellTags.is_valid(SpellTags.PIERCING), "PIERCING in tag vocabulary")
	check(SpellTags.PIERCING in SpellTags.ALL, "PIERCING in ALL")
	check(PIERCING_BEAM.tags == [&"projectile", &"burn", &"piercing"], "piercing beam carries projectile/burn/piercing")
	check(SpellTags.unknown_tags(PIERCING_BEAM.tags).is_empty(), "piercing beam tags all known")
	check(not BASE_BEAM.tags.has(SpellTags.PIERCING), "base beam has no piercing tag")
	# --- fixture world ---
	world = Node2D.new()
	root.add_child(world)

func _process(delta: float) -> bool:
	t += delta
	match phase:
		0:
			# Untagged base beam: must hit ONLY the first enemy and despawn.
			e1 = spawn_enemy(200)
			e2 = spawn_enemy(350)
			p = spawn_projectile(BASE_BEAM)
			phase = 1; t = 0.0
		1:
			if t > 0.6:
				check(e1.hp == 5.0, "base beam: first enemy damaged once (30-25=5)")
				check(e2.hp == 30.0, "base beam: second enemy untouched")
				check(not is_instance_valid(p), "base beam: projectile despawned on first hit")
				e1.queue_free(); e2.queue_free()
				phase = 2; t = 0.0
		2:
			# Piercing beam: same two enemies, projectile must pass through.
			e1 = spawn_enemy(200)
			e2 = spawn_enemy(350)
			p = spawn_projectile(PIERCING_BEAM)
			phase = 3; t = 0.0
		3:
			if t > 0.3: # projectile has passed both enemies, not yet expired
				check(e1.hp == 5.0, "piercing: first enemy damaged exactly once (no double-hit)")
				check(e2.hp == 5.0, "piercing: second enemy damaged exactly once (continued past first)")
				phase = 4; t = 0.0
		4:
			if t > 0.6: # range 900 at speed 2000 -> expires ~0.45s after spawn
				check(not is_instance_valid(p), "piercing: projectile still expires at range")
				e1.queue_free(); e2.queue_free()
				phase = 5; t = 0.0
		5:
			# Range expiry before any body: enemy beyond range stays untouched.
			# #109 swept hits: the envelope is range + shape radius (900 + 14 from
			# x=50 = 964); a 950-center enemy's edge (937) sits INSIDE that swept
			# territory and is a legitimate hit now (the old discrete 33px steps
			# only ever missed it by step-size luck). 990 puts the edge (977)
			# beyond even the clamped final sweep, which is what "beyond range"
			# must mean for this check.
			e1 = spawn_enemy(990) # beyond range 900 + radius 14 from x=50
			p = spawn_projectile(PIERCING_BEAM)
			phase = 6; t = 0.0
		6:
			if t > 0.7:
				check(e1.hp == 30.0, "piercing: enemy beyond range untouched")
				check(not is_instance_valid(p), "piercing: projectile freed by range expiry")
				phase = 7
		7:
			print("test37_piercing: %d failures" % fails)
			quit(fails)
	return false
