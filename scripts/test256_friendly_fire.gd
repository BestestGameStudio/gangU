extends SceneTree
## #256 harness: summon friendly-fire gate (headless system contract).
## Summons take no damage from the player side: any actual Player source
## (owner OR a foreign Player instance - side is the Player TYPE, production
## has a single Player in main.tscn) and any Summon source sharing the
## target's owner are rejected. Enemy, null, unknown, and non-Projectile
## callers keep the legacy damage path, and an ownerless summon has no side
## to protect so it keeps legacy damage too. Plain apply_damage stays the
## one unchanged entry point. Real ENGINE projectile hits only (never manual
## callback invocation for the projectile legs); fixtures built in code, no
## production .tres loaded.

var failures := 0

func _check(cond: bool, name: String) -> void:
	if not cond:
		failures += 1
	print("[256] ", name, " -> ", "PASS" if cond else "FAIL")

func _frames(n: int) -> void:
	for i in range(n):
		await physics_frame

func _spell(p_damage: float) -> Spell:
	var s := Spell.new()
	s.spell_name = "Fixture Bolt"
	s.damage = p_damage
	s.radius = 4.0
	s.range = 600.0
	s.projectile_speed = 500.0
	return s

func _player(stage: Node2D, pos: Vector2) -> Player:
	var p: Player = preload("res://scenes/player.tscn").instantiate()
	p.add_to_group("player")
	stage.add_child(p)
	p.global_position = pos ## parked far from every hit line
	return p

func _summon(stage: Node2D, owner: Node2D, pos: Vector2) -> Summon:
	var s: Summon = preload("res://scenes/summon.tscn").instantiate()
	s.player = owner ## wired BEFORE add_child (SummonManager idiom)
	s.position = pos
	stage.add_child(s)
	return s

func _fire(stage: Node2D, p_spell: Spell, target: Vector2, p_source: Node2D) -> Projectile:
	var pr: Projectile = preload("res://scenes/projectile.tscn").instantiate()
	pr.setup(p_spell, Vector2.DOWN, p_source)
	stage.add_child(pr)
	pr.global_position = target + Vector2(0, -60)
	return pr

func _initialize() -> void:
	var stage := Node2D.new()
	stage.name = "Stage"
	root.add_child(stage)
	await process_frame

	var player := _player(stage, Vector2(2000, 2000))

	# --- (a) owner-Player projectile rejected, no health_changed emission ---
	var s1 := _summon(stage, player, Vector2(400, 400))
	var emissions1 := [0]
	s1.health_changed.connect(func(_c: int, _m: int) -> void: emissions1[0] += 1)
	await _frames(2)
	_fire(stage, _spell(7.0), Vector2(400, 400), player)
	await _frames(20)
	_check(s1.hp == 30, "owner-Player projectile rejected, summon hp unchanged")
	_check(emissions1[0] == 0, "rejected hit emits no health_changed")

	# --- (b) foreign Player-TYPE projectile rejected (side = Player type) ---
	var foreign := _player(stage, Vector2(2600, 2000))
	var s2 := _summon(stage, player, Vector2(700, 400))
	await _frames(2)
	_fire(stage, _spell(7.0), Vector2(700, 400), foreign)
	await _frames(20)
	_check(s2.hp == 30, "foreign Player-TYPE source rejected (friendly regardless of identity)")

	# --- (c) enemy-sourced projectile applies full DamageCalc damage ---
	var enemy_source := Node2D.new()
	enemy_source.name = "EnemyStandIn"
	stage.add_child(enemy_source)
	var s3 := _summon(stage, player, Vector2(400, 700))
	var emissions3 := [0]
	var last_hp := [-1]
	s3.health_changed.connect(func(c: int, _m: int) -> void:
		emissions3[0] += 1
		last_hp[0] = c)
	await _frames(2)
	_fire(stage, _spell(7.0), Vector2(400, 700), enemy_source)
	await _frames(20)
	_check(s3.hp == 23, "enemy-sourced projectile applies full flat damage (30 -> 23)")
	_check(emissions3[0] == 1 and last_hp[0] == 23, "enemy hit emits health_changed exactly once")

	# --- (d) plain apply_damage stays the unchanged legacy entry point ---
	s3.apply_damage(5)
	_check(s3.hp == 18, "plain apply_damage unchanged (23 -> 18)")

	# --- (e) ownerless summon has no side: player-sourced damage applies ---
	var s4 := _summon(stage, null, Vector2(700, 700))
	await _frames(2)
	_fire(stage, _spell(7.0), Vector2(700, 700), player)
	await _frames(20)
	_check(s4.hp == 23, "ownerless summon keeps legacy damage from a player projectile")

	# --- (f) same-owner Summon source rejected (summon-on-summon friendly) ---
	var src_summon := _summon(stage, player, Vector2(1000, 1000))
	var s5 := _summon(stage, player, Vector2(400, 1000))
	await _frames(2)
	_fire(stage, _spell(7.0), Vector2(400, 1000), src_summon)
	await _frames(20)
	_check(s5.hp == 30, "same-owner Summon-sourced projectile rejected")

	# --- (g) non-Projectile caller carrying .source is NOT trusted: legacy damage ---
	var fake := Node2D.new()
	fake.set("source", player)
	var s6 := _summon(stage, player, Vector2(700, 1000))
	await _frames(2)
	s6.apply_damage_from(7, fake)
	_check(s6.hp == 23, "non-Projectile caller falls through to legacy damage")
	fake.free()

	# --- (h) actual Projectile with null source: legacy damage applies ---
	var s7 := _summon(stage, player, Vector2(1000, 700))
	await _frames(2)
	var pr_null: Projectile = preload("res://scenes/projectile.tscn").instantiate()
	pr_null.setup(_spell(7.0), Vector2.DOWN, null)
	s7.apply_damage_from(7, pr_null)
	_check(s7.hp == 23, "Projectile with null source falls through to legacy damage")
	pr_null.free()

	await process_frame
	await process_frame
	if failures == 0:
		print("[256] ALL PASS")
	else:
		print("[256] FAILURES: ", failures)
	quit(failures)
