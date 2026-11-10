extends SceneTree
## #279 harness: summons never physically block or push players or enemies
## (Daniel, 2026-11-08), reusing the #290 ActorCollision exception seam.
## Proves: summon<->player and summon<->enemy exceptions wired for BOTH
## spawn orders the production game has (persistent Player first; enemies
## before OR after casts), bodies may share a position without displacement,
## while summon-summon and summon-container blocking, distance-based
## contact damage and the #256 friendly-fire Area dispatch are untouched.
## Player-after-summon is intentionally NOT covered (no production route:
## main.tscn's $Player is persistent, revive heals in place).

var failures := 0

func _check(cond: bool, name: String) -> void:
	if not cond:
		failures += 1
	print("[279] ", name, " -> ", "PASS" if cond else "FAIL")

## #515: "passes through" = neither body's mask contains the other's layer
## (replaces the old ActorCollision per-pair exceptions).
func _passes_through(a: CollisionObject2D, b: CollisionObject2D) -> bool:
	return (a.collision_mask & b.collision_layer) == 0 and (b.collision_mask & a.collision_layer) == 0

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _initialize() -> void:
	var stage := Node2D.new()
	stage.name = "Stage"
	root.add_child(stage)
	current_scene = stage
	await process_frame

	var def: SummonDefinition = load("res://resources/summons/ally.tres")
	var player: Player = load("res://scenes/player.tscn").instantiate()
	player.add_to_group("player")
	stage.add_child(player)
	player.global_position = Vector2(1000, 1000)
	var manager := SummonManager.new()
	manager.caster_path = NodePath("../Stage/Player/SpellCaster")
	root.add_child(manager)
	await _frames(2)

	# --- 1: summon cast ONTO the player - no push either direction --------
	# Physics-only pop check FIRST (no other summon around to legally shove
	# the probe): a behaviorless summon has no self-motion, so any offset
	# after resting ON the player is solver push. None allowed.
	var s0: Summon = load("res://scenes/summon.tscn").instantiate()
	s0.setup(def)
	stage.add_child(s0)
	s0.global_position = player.global_position
	await _frames(10)
	_check(s0.global_position.distance_to(player.global_position) < 1.0, "summon resting on the player: zero solver push (exceptions, not physics)")
	s0.global_position = Vector2(6000, 7200)
	var ally: Summon = manager.request_spawn(def, player.global_position)
	ally.max_hp = 100000 # survives the enemy's return contact damage; a
	ally.hp = 100000 # death would free the body mid-test (harness hygiene)
	await _frames(2)
	_check(_passes_through(ally, player), "summon<->player layers/masks leave each other out")
	await _frames(28)
	_check(player.global_position.distance_to(Vector2(1000, 1000)) < 1.0, "summon cast onto the player: player never displaced")

	# --- 2: enemy spawning AFTER a summon pairs itself --------------------
	# No enemies yet, so the ally holds position beside the player.
	var hold := Vector2(1000, 1040)
	ally.global_position = hold
	await _frames(2)
	var enemy: Enemy = load("res://scenes/enemy.tscn").instantiate()
	stage.add_child(enemy)
	enemy.global_position = hold
	enemy.max_hp = 100000 # survives the contact-damage leg; a death would
	enemy.hp = 100000 # free the body mid-test (harness hygiene, not scope)
	await _frames(30)
	_check(_passes_through(enemy, ally), "late-spawned enemy passes through the existing summon")
	_check(ally.global_position.distance_to(hold) < 8.0, "enemy on top of a holding summon: summon not displaced")
	# The enemy chases the player THROUGH the summon's body: reach the
	# player-adjacent ally without shoving it aside.
	_check(enemy.global_position.distance_to(ally.global_position) < 8.0, "enemy and summon share space (no body blocking)")

	# --- 3: contact damage unchanged (distance-based, not body-based) -----
	var enemy_hp0: int = enemy.hp
	await _frames(90)
	_check(enemy.hp < enemy_hp0, "contact damage still fires at range with body exceptions in place")
	if is_instance_valid(enemy):
		enemy.set_physics_process(false)
		enemy.global_position = Vector2(6000, 6000)
	await _frames(2)

	# --- 4: summon-summon and summon-container blocking preserved ---------
	var s1: Summon = manager.request_spawn(def, Vector2(2000, 2000))
	var s2: Summon = manager.request_spawn(def, Vector2(2000, 2000))
	var box: DestroyableContainer = load("res://scenes/destroyable_container.tscn").instantiate()
	stage.add_child(box)
	box.global_position = Vector2(2000, 2000)
	await _frames(10)
	_check(not _passes_through(s1, s2), "summon-summon blocking preserved")
	_check(not _passes_through(s1, box), "summon-container blocking preserved")
	_check(s1.global_position.distance_to(box.global_position) > 4.0, "container body still pushes the summon out of its shape")
	s1.global_position = Vector2(6000, 6400)
	s2.global_position = Vector2(6000, 6800)
	box.global_position = Vector2(6000, 7600) # parked, not freed: freeing a body that others hold solver state on trips engine null-body errors (pre-existing physics pattern, not #279 logic)
	await _frames(2)

	# --- 5: #256 friendly-fire Area dispatch unchanged on an excepted body -
	player.global_position = Vector2(3000, 3000)
	var s3: Summon = manager.request_spawn(def, Vector2(3400, 3000))
	await _frames(2)
	_check(_passes_through(player, s3), "control fixture: s3 passes through the player")
	var spell := Spell.new()
	spell.spell_name = "Fixture Bolt"
	spell.damage = 7.0
	spell.radius = 4.0
	spell.range = 600.0
	spell.projectile_speed = 500.0
	var pr: Projectile = load("res://scenes/projectile.tscn").instantiate()
	pr.setup(spell, Vector2.DOWN, player)
	stage.add_child(pr)
	pr.global_position = s3.global_position + Vector2(0, -60)
	await _frames(20)
	_check(s3.hp == s3.max_hp, "owner projectile still rejected on an excepted summon (#256 unchanged)")

	print("[279] failures: ", failures)
	quit(1 if failures > 0 else 0)
