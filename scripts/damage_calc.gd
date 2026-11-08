class_name DamageCalc
extends RefCounted
## The one damage path for every hit, either direction. Order: summed AMP,
## then CRIT, then REDUCTION. The attacker contributes AMP and CRIT, the
## receiver contributes REDUCTION; null collections count as empty.
##
## Crit chance is not capped (#206): it resolves into a rolled crit tier per
## hit. Each full 1.0 of chance guarantees one tier and the remaining fraction
## rolls for one more (1.3 -> 70% tier 1, 30% tier 2). The rolled tier drives
## the damage via crit_factor().

static func compute(base: float, attacker: DamageModifiers, receiver: DamageModifiers, rng: RandomNumberGenerator) -> DamageResult:
	var amp: float = 0.0
	var crit_chance: float = 0.0
	var crit_multiplier: float = 1.0
	if attacker != null:
		for m in attacker.items():
			match m.stage:
				DamageModifier.Stage.AMP:
					amp += m.amount
				DamageModifier.Stage.CRIT:
					crit_chance += m.chance
					crit_multiplier = maxf(crit_multiplier, m.multiplier)
	var reduction_factor: float = 1.0
	if receiver != null:
		for m in receiver.items():
			if m.stage == DamageModifier.Stage.REDUCTION:
				reduction_factor *= 1.0 - m.amount
	reduction_factor = maxf(reduction_factor, 0.0)

	var result := DamageResult.new()
	result.crit_tier = roll_crit_tier(crit_chance, rng)
	result.crit = result.crit_tier > 0
	var total: float = base * (1.0 + amp)
	total *= crit_factor(result.crit_tier, crit_multiplier)
	total *= reduction_factor
	# Truncation, matching the implicit float -> int conversion that
	# apply_damage(spell.damage) used before this path existed.
	result.amount = int(total)
	return result

## Full 1.0s of chance are guaranteed tiers; the fraction rolls for one more.
## A chance with no fractional part (0.0, 1.0, 2.0...) never advances the rng,
## so seeded runs stay stable as modifier sources come and go.
static func roll_crit_tier(chance: float, rng: RandomNumberGenerator) -> int:
	if chance <= 0.0:
		return 0
	var guaranteed: int = int(floorf(chance))
	var fraction: float = chance - guaranteed
	# Snap float noise from summed chances (e.g. 0.1 + 0.2 + 0.7).
	if is_equal_approx(fraction, 1.0):
		return guaranteed + 1
	if is_zero_approx(fraction):
		return guaranteed
	return guaranteed + (1 if rng.randf() < fraction else 0)

## Each tier adds the base crit bonus again: tier 0 -> x1, tier 1 -> xM,
## tier 2 -> x(2M - 1), so a x2.0 crit gives x2 / x3 (#206, Daniel's example).
## OPEN (#206): the general formula for multipliers other than x2.0 is not
## confirmed yet; this is the single place to change if it is decided otherwise.
static func crit_factor(tier: int, multiplier: float) -> float:
	return 1.0 + tier * (multiplier - 1.0)
