extends SceneTree
## Split/beam placeholder behavior harness (#33/#36): proves the SpellFanout
## direction math and that REAL Projectile instances driven by it actually
## diverge in flight. Fixture-labeled headless complement; the CAST loop that
## will consume this (SpellCaster._cast_spell) is the caster owner's seam,
## so production browser proof belongs to that PR's evidence.
var t := 0.0
var phase := 0
var ok := true
var origin := Vector2(576, 480)

func _initialize() -> void:
	# Math: 3-way, 18-degree fan centered on RIGHT -> RIGHT +/- 9 degrees.
	var dirs := SpellFanout.directions(Vector2.RIGHT, 3, 18.0)
	if dirs.size() != 3:
		print("[FAN] FAIL count: ", dirs.size()); ok = false
	elif dirs[1].angle_to(Vector2.RIGHT) != 0.0:
		print("[FAN] FAIL center not base: ", dirs[1]); ok = false
	elif absf(absf(rad_to_deg(dirs[0].angle_to(dirs[1]))) - 9.0) > 0.01 or absf(absf(rad_to_deg(dirs[2].angle_to(dirs[1]))) - 9.0) > 0.01:
		print("[FAN] FAIL outer angles: ", rad_to_deg(dirs[0].angle_to(dirs[1])), " ", rad_to_deg(dirs[2].angle_to(dirs[1]))); ok = false
	else:
		print("[FAN] math OK: 3-way fan centered, outer +/-9 deg")
	var single := SpellFanout.directions(Vector2.RIGHT, 1, 18.0)
	if single.size() != 1:
		print("[FAN] FAIL single-spell fan changed behavior"); ok = false
	else:
		print("[FAN] count=1 unchanged OK")
	# Real projectiles driven by the fan (fixture scene, no caster file).
	var split: Spell = load("res://resources/spells/fire_ball_split.tres")
	var pscene: PackedScene = load("res://scenes/projectile.tscn")
	var spawn_dirs := SpellFanout.directions(Vector2.RIGHT, split.projectile_count, split.spread_degrees)
	for d in spawn_dirs:
		var p: Projectile = pscene.instantiate()
		p.setup(split, d, null)
		p.position = origin
		root.add_child(p)
	phase = 1; t = 0

func _process(delta: float) -> bool:
	t += delta
	match phase:
		1:
			if t > 0.25:
				var projs: Array[Node] = []
				for c in root.get_children():
					if c is Projectile:
						projs.append(c)
				if projs.size() != 3:
					print("[FAN] FAIL live projectiles: ", projs.size()); ok = false
				else:
					var offsets := projs.map(func(p): return p.global_position - origin)
					var spread := rad_to_deg(offsets[0].angle_to(offsets[2]))
					if absf(spread - 18.0) > 1.0:
						print("[FAN] FAIL flight spread deg: ", spread); ok = false
					elif offsets.any(func(o): return o.length() < 100.0):
						print("[FAN] FAIL projectiles did not travel"); ok = false
					else:
						print("[FAN] real projectiles diverge in flight OK (spread ", snappedf(spread, 0.1), " deg)")
				print("[FAN] ", "PASS" if ok else "FAIL")
				return true
		_:
			return true
	if t > 4.0:
		print("[FAN] FAIL timeout")
		return true
	return false
