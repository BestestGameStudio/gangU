class_name DamageCalc
extends RefCounted
## The one damage path for every hit, either direction. Order: summed AMP,
## then CRIT, then REDUCTION. The attacker contributes AMP and CRIT, the
## receiver contributes REDUCTION; null collections count as empty.

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
	crit_chance = minf(crit_chance, 1.0)

	var result := DamageResult.new()
	# Zero-chance hits must not advance the rng, so seeded runs stay stable
	# as modifier sources come and go.
	result.crit = crit_chance > 0.0 and rng.randf() < crit_chance
	var total: float = base * (1.0 + amp)
	if result.crit:
		total *= crit_multiplier
	total *= reduction_factor
	# Truncation, matching the implicit float -> int conversion that
	# apply_damage(spell.damage) used before this path existed.
	result.amount = int(total)
	return result
