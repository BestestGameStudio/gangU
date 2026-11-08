extends SceneTree
## DamageCalc harness: pure composition legs, then real Projectile -> Enemy
## hits (forced crit, per-target piercing rolls) and real enemy contact
## against a Player whose incoming side carries a reduction.

const CRIT_SEED: int = 135
const CRIT_COUNT_1000: int = 606
const PIERCE_SEED: int = 7
const PIERCE_DELTA_A: int = 15
const PIERCE_DELTA_B: int = 5

var failures := 0
var phase := 0
var t := 0.0
var _root2d: Node2D
var _caster: Player
var _target: Player
var _e1: Enemy
var _e2: Enemy
var _direct: Enemy
var _hits: Array = []
var _contact_hp: Array[int] = []

func _check(cond: bool, name: String) -> void:
	if not cond:
		failures += 1
	print("[135] ", name, " -> ", "PASS" if cond else "FAIL")

func _mods(list: Array) -> DamageModifiers:
	var m := DamageModifiers.new()
	for x in list:
		m.add(x)
	return m

func _amount(base: float, attacker: DamageModifiers, receiver: DamageModifiers) -> int:
	return DamageCalc.compute(base, attacker, receiver, RandomNumberGenerator.new()).amount

func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	var empty := DamageModifiers.new()

	_check(_amount(10.0, empty, empty) == 10, "zero modifiers: 10.0 -> 10")
	_check(_amount(7.9, empty, empty) == 7, "zero modifiers: 7.9 -> 7 (truncated)")
	_check(_amount(10.0, null, null) == 10, "null attacker and receiver: 10.0 -> 10")
	_check(_amount(7.9, null, null) == 7, "null attacker and receiver: 7.9 -> 7")

	var forced := DamageCalc.compute(10.0, _mods([DamageModifier.crit(1.0, 2.0)]), null, rng)
	_check(forced.amount == 20 and forced.crit, "forced crit (1.0, x2.0): 10 -> 20, crit true")
	var never := DamageCalc.compute(10.0, _mods([DamageModifier.crit(0.0, 2.0)]), null, rng)
	_check(never.amount == 10 and not never.crit, "forced non-crit (0.0): 10 -> 10, crit false")
	_check(_amount(10.0, _mods([DamageModifier.crit(1.0, 2.0), DamageModifier.crit(0.0, 3.0)]), null) == 30,
		"two crits: multiplier is the largest (x3.0): 10 -> 30")

	_check(_amount(10.0, _mods([DamageModifier.amp(0.25)]), null) == 12, "amp +0.25: 10 -> 12 (12.5 truncated)")
	_check(_amount(10.0, _mods([DamageModifier.amp(0.2), DamageModifier.amp(0.3)]), null) == 15, "amps add (+0.2 +0.3): 10 -> 15")

	_check(_amount(10.0, null, _mods([DamageModifier.reduction(0.25)])) == 7, "reduction 0.25: 10 -> 7 (7.5 truncated)")
	_check(_amount(10.0, null, _mods([DamageModifier.reduction(0.5), DamageModifier.reduction(0.5)])) == 2,
		"reductions multiply (0.5, 0.5): 10 -> 2 (2.5 truncated)")
	_check(_amount(10.0, null, _mods([DamageModifier.reduction(1.5)])) == 0, "reduction above 1.0 clamps to 0, never negative")
	_check(_amount(10.0, null, _mods([DamageModifier.amp(0.5)])) == 10, "receiver AMP is ignored")
	_check(_amount(10.0, _mods([DamageModifier.reduction(0.5)]), null) == 10, "attacker REDUCTION is ignored")

	var composed := DamageCalc.compute(10.0,
		_mods([DamageModifier.amp(0.2), DamageModifier.amp(0.3), DamageModifier.crit(1.0, 2.0)]),
		_mods([DamageModifier.reduction(0.25)]), rng)
	_check(composed.amount == 22 and composed.crit, "composed: 10 * 1.5 * 2.0 * 0.75 = 22.5 -> 22, crit true")

	var seeded := RandomNumberGenerator.new()
	seeded.seed = CRIT_SEED
	var two_crits := _mods([DamageModifier.crit(0.3, 2.0), DamageModifier.crit(0.3, 2.0)])
	var crits := 0
	for i in 1000:
		if DamageCalc.compute(10.0, two_crits, null, seeded).crit:
			crits += 1
	print("[135] crit count over 1000 hits at 0.3 + 0.3 (seed %d): %d" % [CRIT_SEED, crits])
	_check(crits == CRIT_COUNT_1000, "crit chances add to 0.6: %d crits in 1000 for seed %d" % [CRIT_COUNT_1000, CRIT_SEED])

	var untouched := RandomNumberGenerator.new()
	untouched.seed = 99
	var before: int = untouched.state
	DamageCalc.compute(10.0, empty, empty, untouched)
	DamageCalc.compute(10.0, _mods([DamageModifier.amp(0.5), DamageModifier.crit(0.0, 2.0)]), null, untouched)
	_check(untouched.state == before, "zero total crit chance never advances the rng")

	_root2d = Node2D.new()
	root.add_child(_root2d)
	_direct = _spawn_enemy(Vector2(-2000, -2000), 30)

	_caster = load("res://scenes/player.tscn").instantiate()
	_caster.damage_modifiers.add(DamageModifier.crit(1.0, 2.0))
	_e1 = _spawn_enemy(Vector2(100, 0), 30)
	_fire(_spell(10.0, []))

func _spawn_enemy(at: Vector2, hp_max: int) -> Enemy:
	var e: Enemy = load("res://scenes/enemy.tscn").instantiate()
	e.speed = 0.0
	e.max_hp = hp_max
	e.position = at
	_root2d.add_child(e)
	return e

func _spell(damage: float, tags: Array[StringName]) -> Spell:
	var s := Spell.new()
	s.damage = damage
	s.tags = tags
	s.range = 400.0
	return s

func _fire(s: Spell) -> void:
	var p: Projectile = load("res://scenes/projectile.tscn").instantiate()
	p.setup(s, Vector2.RIGHT, _caster)
	p.hit_resolved.connect(func(body: Node2D, r: DamageResult) -> void: _hits.append([body, r.amount, r.crit]))
	_root2d.add_child(p)

func _process(delta: float) -> bool:
	t += delta
	match phase:
		0:
			if t > 0.6:
				var spell_damage: float = 7.9
				_direct.apply_damage(spell_damage)
				_check(30 - _direct.hp == 7 and _amount(7.9, null, null) == 7,
					"direct apply_damage(7.9) drops HP by 7, the same as the zero-modifier pipeline")
				_check(_e1.hp == 10, "projectile with forced-crit caster: enemy HP 30 -> 10 (delta 20)")
				_check(_hits.size() == 1 and _hits[0][2] == true, "hit_resolved reports crit true")
				_e1.queue_free()
				_hits.clear()
				_caster.damage_modifiers = _mods([DamageModifier.crit(0.5, 2.0)])
				_caster.damage_rng.seed = PIERCE_SEED
				_e1 = _spawn_enemy(Vector2(100, 0), 100)
				_e2 = _spawn_enemy(Vector2(200, 0), 100)
				_e1.damage_modifiers.add(DamageModifier.reduction(0.25))
				_e2.damage_modifiers.add(DamageModifier.reduction(0.5))
				_fire(_spell(10.0, [SpellTags.PIERCING]))
				phase = 1
				t = 0.0
		1:
			if t > 1.0:
				var d1: int = 100 - _e1.hp
				var d2: int = 100 - _e2.hp
				print("[135] piercing deltas (seed %d): %d, %d; hits %s" % [PIERCE_SEED, d1, d2, str(_hits.map(func(h): return [h[1], h[2]]))])
				_check(d1 == PIERCE_DELTA_A, "piercing: enemy A (reduction 0.25) crit roll -> 20 * 0.75 = %d" % PIERCE_DELTA_A)
				_check(d2 == PIERCE_DELTA_B, "piercing: enemy B (reduction 0.5) non-crit roll -> 10 * 0.5 = %d" % PIERCE_DELTA_B)
				_check(_hits.size() == 2 and _hits[0][2] == true and _hits[1][2] == false, "piercing: each target rolled its own crit (true, false)")
				_e1.queue_free()
				_e2.queue_free()
				_target = load("res://scenes/player.tscn").instantiate()
				_target.position = Vector2(0, 500)
				_target.add_to_group("player")
				_root2d.add_child(_target)
				_target.damage_modifiers.add(DamageModifier.reduction(0.5))
				_target.health_changed.connect(func(cur: int, _max: int) -> void: _contact_hp.append(cur))
				_e1 = _spawn_enemy(Vector2(20, 500), 30)
				phase = 2
				t = 0.0
		2:
			if t > 0.3:
				_check(_contact_hp.size() >= 1 and _contact_hp[0] == 95,
					"enemy contact 10 vs player reduction 0.5: player HP 100 -> 95 (got %s)" % str(_contact_hp))
				_caster.free()
				print("[135] failures: ", failures)
				quit(1 if failures > 0 else 0)
				return true
	return false
