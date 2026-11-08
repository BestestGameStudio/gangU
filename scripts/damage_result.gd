class_name DamageResult
extends RefCounted

var amount: int = 0
## True when crit_tier > 0.
var crit: bool = false
## Rolled crit tier for this hit (#206): 0 = no crit, 1 = crit, 2+ = overflow tiers.
var crit_tier: int = 0
