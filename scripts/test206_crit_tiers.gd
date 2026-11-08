extends SceneTree
## #206: crit chance over 100% resolves into a rolled crit tier per hit.
## Daniel's confirmed examples: 30% -> 70/30 none/tier 1; 130% -> 70/30
## tier 1/tier 2; 150% at x2.0 -> half the hits x2, half x3.

const HITS: int = 10000
const SEED: int = 206
const TOLERANCE: float = 0.02

var failures := 0

func _check(cond: bool, name: String) -> void:
	if not cond:
		failures += 1
	print("[206] ", name, " -> ", "PASS" if cond else "FAIL")

func _mods(list: Array) -> DamageModifiers:
	var m := DamageModifiers.new()
	for x in list:
		m.add(x)
	return m

## Returns {tier: share of HITS} and {amount: share of HITS}.
func _distribution(base: float, attacker: DamageModifiers) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var tiers := {}
	var amounts := {}
	for i in HITS:
		var r := DamageCalc.compute(base, attacker, null, rng)
		tiers[r.crit_tier] = tiers.get(r.crit_tier, 0) + 1
		amounts[r.amount] = amounts.get(r.amount, 0) + 1
		if r.crit != (r.crit_tier > 0):
			failures += 1
			print("[206] crit flag disagrees with tier ", r.crit_tier, " -> FAIL")
	for k in tiers:
		tiers[k] = float(tiers[k]) / HITS
	for k in amounts:
		amounts[k] = float(amounts[k]) / HITS
	return [tiers, amounts]

func _near(v: float, want: float) -> bool:
	return absf(v - want) <= TOLERANCE

func _initialize() -> void:
	# 30%: 70% non-crit, 30% tier 1.
	var d30 := _distribution(10.0, _mods([DamageModifier.crit(0.3, 2.0)]))
	print("[206] 30%% tiers: %s amounts: %s" % [d30[0], d30[1]])
	_check(d30[0].keys().all(func(k): return k == 0 or k == 1), "30%: only tiers 0 and 1")
	_check(_near(d30[0].get(0, 0.0), 0.7) and _near(d30[0].get(1, 0.0), 0.3), "30%: ~70% tier 0, ~30% tier 1")

	# 130%: 70% tier 1, 30% tier 2, never a non-crit.
	var d130 := _distribution(10.0, _mods([DamageModifier.crit(1.0, 2.0), DamageModifier.crit(0.3, 2.0)]))
	print("[206] 130%% tiers: %s amounts: %s" % [d130[0], d130[1]])
	_check(d130[0].keys().all(func(k): return k == 1 or k == 2), "130%: only tiers 1 and 2 (overflow is not wasted)")
	_check(_near(d130[0].get(1, 0.0), 0.7) and _near(d130[0].get(2, 0.0), 0.3), "130%: ~70% tier 1, ~30% tier 2")

	# 150% at x2.0: half the hits 2x, half 3x.
	var d150 := _distribution(10.0, _mods([DamageModifier.crit(1.5, 2.0)]))
	print("[206] 150%% tiers: %s amounts: %s" % [d150[0], d150[1]])
	_check(d150[1].keys().all(func(k): return k == 20 or k == 30), "150% x2.0: every hit is 20 (2x) or 30 (3x)")
	_check(_near(d150[1].get(20, 0.0), 0.5) and _near(d150[1].get(30, 0.0), 0.5), "150% x2.0: ~50% at 2x, ~50% at 3x")

	# Whole chances are deterministic and never touch the rng.
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var before: int = rng.state
	var t1 := DamageCalc.compute(10.0, _mods([DamageModifier.crit(1.0, 2.0)]), null, rng)
	var t2 := DamageCalc.compute(10.0, _mods([DamageModifier.crit(1.0, 2.0), DamageModifier.crit(1.0, 2.0)]), null, rng)
	var t0 := DamageCalc.compute(10.0, _mods([DamageModifier.crit(0.0, 2.0)]), null, rng)
	_check(t1.crit_tier == 1 and t1.amount == 20, "100% x2.0: always tier 1, 10 -> 20")
	_check(t2.crit_tier == 2 and t2.amount == 30, "200% x2.0: always tier 2, 10 -> 30")
	_check(t0.crit_tier == 0 and t0.amount == 10 and not t0.crit, "0%: tier 0, 10 -> 10")
	_check(rng.state == before, "whole crit chances (0, 1.0, 2.0) never advance the rng")

	# Float noise from summed chances snaps to the whole tier.
	var noisy := DamageCalc.compute(10.0, _mods([DamageModifier.crit(0.1, 2.0), DamageModifier.crit(0.2, 2.0), DamageModifier.crit(0.7, 2.0)]), null, rng)
	_check(noisy.crit_tier == 1 and rng.state == before, "0.1 + 0.2 + 0.7 counts as exactly 100%")

	# Composition with AMP and REDUCTION is unchanged: base * (1+amp) * crit * (1-red).
	var composed := DamageCalc.compute(10.0,
		_mods([DamageModifier.amp(0.5), DamageModifier.crit(2.0, 2.0)]),
		_mods([DamageModifier.reduction(0.5)]), rng)
	_check(composed.crit_tier == 2 and composed.amount == 22, "composed: 10 * 1.5 * 3.0 * 0.5 = 22.5 -> 22, tier 2")

	print("[206] crit_factor tiers 0..3 at x2.0: ", [0, 1, 2, 3].map(func(t): return DamageCalc.crit_factor(t, 2.0)))
	print("[206] failures: ", failures)
	if failures == 0:
		print("RESULT: ALL PASS")
	quit(1 if failures > 0 else 0)
