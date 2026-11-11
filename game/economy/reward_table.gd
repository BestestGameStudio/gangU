class_name RewardTable
extends Resource
## Reward table (track A, #59): the set of rewards an enemy can drop.
## Approved direction (Daniel, 2026-11-07): enemies carry a reward table of
## spells and items; a spell leaves the pool once picked up. Table contents,
## weights and drop chances remain human-open - placeholder data only.

@export var entries: Array[RewardEntry] = []

## Weighted pick among entries the pool still marks eligible. Returns null
## when nothing is eligible (pool exhausted) - callers treat null as no drop.
func roll(granted: Array) -> RewardEntry:
	var pool: Array[RewardEntry] = []
	var total := 0.0
	for e in entries:
		if not granted.has(e):
			pool.append(e)
			total += maxf(e.weight, 0.0)
	if pool.is_empty() or total <= 0.0:
		return null
	var r := randf() * total
	for e in pool:
		r -= maxf(e.weight, 0.0)
		if r <= 0.0:
			return e
	return pool[-1]
