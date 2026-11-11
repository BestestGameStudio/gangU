class_name SpellFanout
extends RefCounted
## Projectile fan-out helper (progression, #33/#36): the pure direction math
## for multi-projectile placeholder spells (split shot). A static, allocation
## free-of-state helper so the CAST side stays a 3-line seam in
## SpellCaster._cast_spell - that loop is the caster owner's file (Mitra,
## post-#63 window), NOT this file. Provisional numbers live on the Spell
## resource (projectile_count/spread_degrees), never hardcoded here.

## Evenly spread `count` directions centered on `base`, total fan width
## `spread_degrees`. count <= 1 or spread <= 0 returns [base] unchanged.
static func directions(base: Vector2, count: int, spread_degrees: float) -> Array[Vector2]:
	if count <= 1 or spread_degrees <= 0.0 or base.length_squared() == 0.0:
		return [base]
	var out: Array[Vector2] = []
	var step := deg_to_rad(spread_degrees) / float(count - 1)
	var start := -deg_to_rad(spread_degrees) * 0.5
	for i in count:
		out.append(base.rotated(start + step * i).normalized())
	return out
