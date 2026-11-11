extends SceneTree
## #268: player stats + modifier foundation. Formulas, caps, stacking,
## timed expiry, run-scoped modifiers, and the Player / DamageCalc /
## SpellCaster / HUD wiring.
var failures := 0
var checks := 0

class Target extends Node2D:
	var damage_modifiers := DamageModifiers.new()
	var received := 0
	func apply_damage(n: int) -> void:
		received += n

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("[268] ", label, " -> ", "PASS" if ok else "FAIL")

func near(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for child in root.get_children():
		child.free()

	# --- PlayerStats in isolation ---
	var s := PlayerStats.new()
	var emitted: Array[StringName] = []
	s.changed.connect(func(stat: StringName) -> void: emitted.append(stat))
	check(near(s.value(PlayerStats.MOVE_SPEED, 300.0), 300.0), "no modifiers: base value")
	s.add(StatModifier.flat(PlayerStats.MAX_HP, 20.0))
	s.add(StatModifier.percent(PlayerStats.MAX_HP, 0.5))
	check(near(s.value(PlayerStats.MAX_HP, 100.0), 180.0), "flat then percent: (100+20)*1.5 = 180")
	s.add(StatModifier.percent(PlayerStats.MAX_HP, 0.5))
	check(near(s.value(PlayerStats.MAX_HP, 100.0), 240.0), "percents stack additively: (120)*2.0")
	check(emitted.size() == 3 and emitted[0] == PlayerStats.MAX_HP, "changed emitted per add")
	check(s.add(StatModifier.flat(&"luck", 1.0)) == null, "unknown stat refused")

	# Caps.
	var c := PlayerStats.new()
	c.add(StatModifier.flat(PlayerStats.ARMOR, 2.0))
	check(near(c.value(PlayerStats.ARMOR, 0.0), PlayerStats.ARMOR_MAX), "armor capped at 0.8")
	c.add(StatModifier.flat(PlayerStats.COOLDOWN_REDUCTION, 5.0))
	check(near(c.value(PlayerStats.COOLDOWN_REDUCTION, 0.0), 0.6), "cdr capped at 0.6")
	c.add(StatModifier.flat(PlayerStats.DAMAGE_AMP, -3.0))
	check(near(c.value(PlayerStats.DAMAGE_AMP, 0.0), -0.9), "damage amp floored at -0.9")
	c.add(StatModifier.percent(PlayerStats.MOVE_SPEED, -2.0))
	check(near(c.value(PlayerStats.MOVE_SPEED, 300.0), 30.0), "move speed floored at 10% of base")
	c.add(StatModifier.percent(PlayerStats.MOVE_SPEED, 10.0))
	check(near(c.value(PlayerStats.MOVE_SPEED, 300.0), 900.0), "move speed capped at 3x base")
	c.add(StatModifier.flat(PlayerStats.MAX_HP, -1000.0))
	check(near(c.value(PlayerStats.MAX_HP, 100.0), 1.0), "max hp floored at 1")

	# Timed expiry vs run-scoped.
	var t := PlayerStats.new()
	var timed := t.add(StatModifier.flat(PlayerStats.ARMOR, 0.3, 2.0, &"shield"))
	var perm := t.add(StatModifier.flat(PlayerStats.ARMOR, 0.1, 0.0, &"relic"))
	t.tick(1.5)
	check(near(t.value(PlayerStats.ARMOR, 0.0), 0.4) and near(timed.time_left, 0.5), "timed still active at 1.5s")
	t.tick(0.6)
	check(near(t.value(PlayerStats.ARMOR, 0.0), 0.1) and t.modifiers().size() == 1 and t.modifiers()[0] == perm,
		"timed expires, run-scoped stays")
	t.tick(1000.0)
	check(t.modifiers().size() == 1, "run-scoped never expires by time")

	# add_unique refreshes instead of stacking; removal paths.
	var u := PlayerStats.new()
	u.add_unique(StatModifier.percent(PlayerStats.MOVE_SPEED, 0.2, 3.0, &"haste"))
	u.tick(2.0)
	var fresh := u.add_unique(StatModifier.percent(PlayerStats.MOVE_SPEED, 0.2, 3.0, &"haste"))
	check(u.modifiers().size() == 1 and near(fresh.time_left, 3.0), "add_unique refreshes, no stack")
	u.add(StatModifier.percent(PlayerStats.MOVE_SPEED, 0.2, 3.0, &"haste"))
	check(near(u.value(PlayerStats.MOVE_SPEED, 100.0), 140.0), "plain add stacks same source")
	check(u.remove_source(&"haste") == 2 and u.modifiers().is_empty(), "remove_source drops all from source")
	var h := u.add(StatModifier.flat(PlayerStats.DAMAGE_AMP, 0.2))
	u.add(StatModifier.flat(PlayerStats.DAMAGE_AMP, 0.1, 5.0))
	check(u.remove(h) and not u.remove(h), "remove by handle once")
	check(u.clear_timed() == 1 and u.modifiers().is_empty(), "clear_timed drops timed only")

	# --- Player wiring ---
	var main := Node2D.new()
	root.add_child(main)
	current_scene = main
	var player := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	main.add_child(player)
	await process_frame
	player.set_physics_process(false)
	var hp_events: Array = []
	player.health_changed.connect(func(cur: int, mx: int) -> void: hp_events.append([cur, mx]))
	check(player.base_max_hp == 100 and player.max_hp == 100 and player.hp == 100, "player starts at base")
	check(player.damage_modifiers.items().is_empty(), "neutral stats add no damage modifiers")

	# Example from the issue: a spell that grants max HP on kill (run-scoped).
	var foe := Enemy.new()
	foe.died.connect(func() -> void: player.stats.add(StatModifier.flat(PlayerStats.MAX_HP, 5.0, 0.0, &"fixture_kill_hp")))
	foe.died.emit()
	foe.died.emit()
	foe.free()
	check(player.max_hp == 110 and player.hp == 110, "max HP on kill: +5 per kill, healed by the gain")
	check(hp_events.size() == 2 and hp_events[-1] == [110, 110], "health_changed emitted on max HP change")
	player.apply_damage(30)
	var reduce := player.stats.add(StatModifier.flat(PlayerStats.MAX_HP, -60.0))
	check(player.max_hp == 50 and player.hp == 50, "lower max HP clamps current HP")
	player.stats.remove(reduce)
	check(player.max_hp == 110 and player.hp == 110, "restoring max HP heals by the gain (50 + 60)")
	player.stats.add(StatModifier.flat(PlayerStats.MAX_HP, -10000.0, 0.0, &"curse"))
	check(player.max_hp == 1 and player.hp == 1, "max HP floor never kills")
	player.stats.remove_source(&"curse")

	# Damage amp + armor reach DamageCalc.
	var spell := Spell.new()
	spell.mode = Spell.CastMode.PROJECTILE
	spell.damage = 20
	var target := Target.new()
	main.add_child(target)
	var projectile_scene := load("res://scenes/projectile.tscn") as PackedScene
	player.stats.add(StatModifier.flat(PlayerStats.DAMAGE_AMP, 0.5, 0.0, &"fixture_amp"))
	var p := projectile_scene.instantiate() as Projectile
	p.setup(spell, Vector2.RIGHT, player)
	main.add_child(p)
	p._on_body_entered(target)
	check(target.received == 30, "damage amp +50%: 20 -> 30 via projectile")
	player.stats.remove_source(&"fixture_amp")
	check(player.damage_modifiers.items().is_empty(), "amp bridge removed when stat returns to 0")

	var hp_before := player.hp
	player.stats.add(StatModifier.flat(PlayerStats.ARMOR, 0.25, 1.0, &"fixture_armor"))
	var rng := RandomNumberGenerator.new()
	var taken := DamageCalc.compute(40, null, player.damage_modifiers, rng).amount
	player.apply_damage(taken)
	check(taken == 30 and player.hp == hp_before - 30, "armor 25%: 40 -> 30 incoming")
	player.stats.tick(1.0)
	check(DamageCalc.compute(40, null, player.damage_modifiers, rng).amount == 40, "timed armor expired")

	# Move speed.
	player.stats.add(StatModifier.percent(PlayerStats.MOVE_SPEED, -0.5, 2.0, &"fixture_slow"))
	check(near(player.move_speed(), player.speed * 0.5), "slow halves move speed")
	player.set_physics_process(true)
	await create_timer(0.3).timeout
	check(player.stats.modifiers(PlayerStats.MOVE_SPEED).size() == 1, "player ticks timed modifiers (not yet expired)")
	player.stats.clear_timed()
	check(near(player.move_speed(), player.speed), "move speed back to base")
	player.set_physics_process(false)

	# Cooldown reduction on SpellCaster + HUD ratio source.
	var caster := player.get_node("SpellCaster") as SpellCaster
	var cd_spell := Spell.new()
	cd_spell.mode = Spell.CastMode.PROJECTILE
	cd_spell.cooldown = 2.0
	caster.add_spell(cd_spell)
	var started: Array = []
	caster.cooldown_started.connect(func(_s: Spell, d: float) -> void: started.append(d))
	player.stats.add(StatModifier.flat(PlayerStats.COOLDOWN_REDUCTION, 0.25, 0.0, &"fixture_cdr"))
	caster._cast_spell(cd_spell)
	check(started.size() == 1 and near(started[0], 1.5), "cdr 25%: 2.0s -> 1.5s")
	check(near(caster.cooldown_remaining(cd_spell), 1.5) and near(caster.cooldown_duration(cd_spell), 1.5),
		"cooldown_duration reports reduced length for HUD")

	print("[268] ", checks - failures, "/", checks, " checks passed")
	print("RESULT: ", "ALL PASS" if failures == 0 else "FAILURES")
	quit(0 if failures == 0 else 1)
