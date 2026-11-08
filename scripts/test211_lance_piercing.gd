extends SceneTree
## #211 Lance behavior harness (headless, same bare-world fixture style as
## test37_piercing.gd - main.tscn enemies would break alignment; physics is
## real Area2D body_entered). Proves the Mana Lance result spell's claimed
## piercing OUTCOME, not just its tag: one cast damages two aligned enemies
## exactly once each, continues past the first body, and still expires at
## range. Untagged Mana Shot keeps despawn-on-first-hit.

const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const MANA_SHOT := preload("res://resources/spells/mana_shot.tres")
const LANCE := preload("res://resources/spells/mana_shot_lance.tres")

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
	check(LANCE.tags.has(SpellTags.PIERCING), "lance carries PIERCING")
	check(not MANA_SHOT.tags.has(SpellTags.PIERCING), "base mana shot has no piercing tag")
	world = Node2D.new()
	root.add_child(world)

func _process(delta: float) -> bool:
	t += delta
	match phase:
		0:
			# Untagged base Mana Shot: hits ONLY the first enemy and despawns.
			e1 = spawn_enemy(200)
			e2 = spawn_enemy(350)
			p = spawn_projectile(MANA_SHOT)
			phase = 1; t = 0.0
		1:
			if t > 0.3:
				check(e1.hp == 22.0, "base mana shot: first enemy damaged once (30-8=22)")
				check(e2.hp == 30.0, "base mana shot: second enemy untouched")
				check(not is_instance_valid(p), "base mana shot: projectile despawned on first hit")
				e1.queue_free(); e2.queue_free()
				phase = 2; t = 0.0
		2:
			# Mana Lance: same two enemies, projectile must pass through.
			e1 = spawn_enemy(200)
			e2 = spawn_enemy(350)
			p = spawn_projectile(LANCE)
			phase = 3; t = 0.0
		3:
			if t > 0.25: # speed 1800: passes both enemies well before expiry
				check(e1.hp == 8.0, "lance: first enemy damaged exactly once (30-22=8, no double-hit)")
				check(e2.hp == 8.0, "lance: second enemy damaged exactly once (continued past first)")
				check(is_instance_valid(p), "lance: projectile still flying after both hits")
				phase = 4; t = 0.0
		4:
			if t > 0.6: # range 900 at speed 1800 -> expires ~0.5s after spawn
				check(not is_instance_valid(p), "lance: projectile freed by range expiry")
				e1.queue_free(); e2.queue_free()
				phase = 5
		5:
			print("test211_lance_piercing: %d failures" % fails)
			quit(fails)
	return false
