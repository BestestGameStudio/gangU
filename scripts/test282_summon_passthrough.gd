extends SceneTree
## #282 harness: player spells IGNORE friendly summons - they pass through
## instead of being blocked (headless system contract, same bare-world
## fixture style as test256_friendly_fire.gd; real ENGINE projectile hits
## only, fixtures built in code, no production .tres loaded except the
## piercing-lance leg, which uses the same resource as test211).
##
## Side rule (mirrors #256's apply_damage_from gate): any actual Player
## source is player-side regardless of identity (production has a single
## Player in main.tscn); a Summon source is player-side only when it shares
## the target's owner. A pass-through deals no damage, emits no signals,
## never enters _hit_bodies and never despawns the shot - piercing counts
## are untouched. Enemy-sourced shots and ownerless summons keep the
## legacy behaviour: summons still tank enemy fire, and an ownerless
## summon has no side, so it still blocks and is damaged.
##
## Every check runs on its OWN x lane: pass-through shots keep flying to
## range expiry, so shared columns would let one fixture's shot wander
## into another fixture (the same isolation rule as #256's (e) fix).

var failures := 0

func _check(cond: bool, name: String) -> void:
	if not cond:
		failures += 1
	print("[282] ", name, " -> ", "PASS" if cond else "FAIL")

func _frames(n: int) -> void:
	for i in range(n):
		await physics_frame

func _spell(p_damage: float, p_range: float = 600.0, p_speed: float = 500.0) -> Spell:
	var s := Spell.new()
	s.mode = Spell.CastMode.PROJECTILE
	s.spell_name = "Fixture Bolt"
	s.damage = p_damage
	s.radius = 4.0
	s.range = p_range
	s.projectile_speed = p_speed
	return s

func _player(stage: Node2D, pos: Vector2) -> Player:
	var p: Player = preload("res://scenes/player.tscn").instantiate()
	stage.add_child(p)
	p.global_position = pos ## parked far from every hit line
	return p

func _summon(stage: Node2D, owner: Node2D, pos: Vector2) -> Summon:
	var s: Summon = preload("res://scenes/summon.tscn").instantiate()
	s.player = owner ## wired BEFORE add_child (SummonManager idiom)
	s.position = pos
	stage.add_child(s)
	return s

func _enemy(stage: Node2D, pos: Vector2) -> Enemy:
	var e: Enemy = preload("res://scenes/enemy.tscn").instantiate()
	stage.add_child(e)
	e.global_position = pos
	return e

func _fire_down(stage: Node2D, p_spell: Spell, x: float, target_y: float, p_source: Node2D) -> Projectile:
	var pr: Projectile = preload("res://scenes/projectile.tscn").instantiate()
	pr.setup(p_spell, Vector2.DOWN, p_source)
	stage.add_child(pr)
	pr.global_position = Vector2(x, target_y - 60)
	return pr

func _initialize() -> void:
	var stage := Node2D.new()
	stage.name = "Stage"
	root.add_child(stage)
	await process_frame

	var player := _player(stage, Vector2(3000, 2000))

	# --- (a) own-summon pass-through: no damage, no signal, shot continues
	# and damages the enemy aligned behind, then despawns (non-piercing) ---
	var s_a := _summon(stage, player, Vector2(400, 400))
	var emissions_a := [0]
	s_a.health_changed.connect(func(_c: int, _m: int) -> void: emissions_a[0] += 1)
	var e_a := _enemy(stage, Vector2(400, 550))
	await _frames(2)
	_fire_down(stage, _spell(7.0), 400.0, 400.0, player)
	await _frames(40)
	_check(s_a.hp == 30, "(a) own summon untouched by player shot")
	_check(emissions_a[0] == 0, "(a) pass-through emits no health_changed")
	_check(e_a.hp == 23.0, "(a) shot continues and damages enemy behind summon (30-7=23)")

	# --- (b) enemy-sourced shot: summon still TANKS it (legacy block) ---
	var enemy_source := Node2D.new()
	enemy_source.name = "EnemyStandIn"
	stage.add_child(enemy_source)
	var s_b := _summon(stage, player, Vector2(700, 400))
	var e_b := _enemy(stage, Vector2(700, 550))
	await _frames(2)
	_fire_down(stage, _spell(7.0), 700.0, 400.0, enemy_source)
	await _frames(40)
	_check(s_b.hp == 23, "(b) enemy shot still damages summon (30-7=23)")
	_check(e_b.hp == 30.0, "(b) summon still BLOCKS enemy shot: enemy behind untouched")

	# --- (c) same-owner Summon source passes through own-side summon ---
	var src_summon := _summon(stage, player, Vector2(1000, 900))
	var s_c := _summon(stage, player, Vector2(1000, 400))
	var e_c := _enemy(stage, Vector2(1000, 550))
	await _frames(2)
	_fire_down(stage, _spell(7.0), 1000.0, 400.0, src_summon)
	await _frames(40)
	_check(s_c.hp == 30, "(c) same-owner summon shot passes through own-side summon")
	_check(e_c.hp == 23.0, "(c) shot continues and damages enemy behind summon")

	# --- (d) ownerless summon has no side: legacy hit AND block ---
	var s_d := _summon(stage, null, Vector2(1300, 400))
	var e_d := _enemy(stage, Vector2(1300, 550))
	await _frames(2)
	_fire_down(stage, _spell(7.0), 1300.0, 400.0, player)
	await _frames(40)
	_check(s_d.hp == 23, "(d) ownerless summon keeps legacy damage from player shot")
	_check(e_d.hp == 30.0, "(d) ownerless summon still blocks: enemy behind untouched")

	# --- (e) foreign Player-TYPE source: side is the Player TYPE ---
	var foreign := _player(stage, Vector2(3600, 2000))
	var s_e := _summon(stage, player, Vector2(1600, 400))
	var e_e := _enemy(stage, Vector2(1600, 550))
	await _frames(2)
	_fire_down(stage, _spell(7.0), 1600.0, 400.0, foreign)
	await _frames(40)
	_check(s_e.hp == 30, "(e) foreign Player-TYPE shot passes through (side, not identity)")
	_check(e_e.hp == 23.0, "(e) shot continues and damages enemy behind summon")

	# --- (f) piercing shot: passes summon AND both enemies, one hit each ---
	var lance: Spell = preload("res://resources/spells/mana_shot_lance.tres")
	_check(lance.tags.has(SpellTags.PIERCING), "(f) fixture lance carries PIERCING")
	var s_f := _summon(stage, player, Vector2(1900, 400))
	var e_f1 := _enemy(stage, Vector2(1900, 550))
	var e_f2 := _enemy(stage, Vector2(1900, 700))
	await _frames(2)
	var p_f := _fire_down(stage, lance, 1900.0, 400.0, player)
	await _frames(25) # speed 1800: summon at 0.03s, enemies at 0.12s/0.20s
	_check(s_f.hp == 30, "(f) piercing shot ignores summon (no damage)")
	_check(e_f1.hp == 8.0, "(f) piercing damages first enemy once (30-22=8)")
	_check(e_f2.hp == 8.0, "(f) piercing damages second enemy once (no double-hit)")
	_check(is_instance_valid(p_f), "(f) piercing shot still flying after summon + both enemies")
	await _frames(30) # range 900 at speed 1800: expires ~0.5s after spawn
	_check(not is_instance_valid(p_f), "(f) piercing shot freed by range expiry")

	await process_frame
	await process_frame
	if failures == 0:
		print("[282] ALL PASS")
	else:
		print("[282] FAILURES: ", failures)
	quit(failures)
