class_name DamageModifier
extends RefCounted
## One damage modifier source. AMP and REDUCTION use `amount` as a fraction
## (+0.2 = +20%); CRIT uses `chance` (0..1) and `multiplier`.

enum Stage { AMP, CRIT, REDUCTION }

var stage: Stage
var amount: float = 0.0
var chance: float = 0.0
var multiplier: float = 1.0

static func amp(p_amount: float) -> DamageModifier:
	var m := DamageModifier.new()
	m.stage = Stage.AMP
	m.amount = p_amount
	return m

static func crit(p_chance: float, p_multiplier: float) -> DamageModifier:
	var m := DamageModifier.new()
	m.stage = Stage.CRIT
	m.chance = p_chance
	m.multiplier = p_multiplier
	return m

static func reduction(p_amount: float) -> DamageModifier:
	var m := DamageModifier.new()
	m.stage = Stage.REDUCTION
	m.amount = p_amount
	return m
