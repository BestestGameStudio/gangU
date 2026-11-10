extends SceneTree
## #514: authored spell modes preserve the shipped resource behavior.
## The field-to-mode reference below validates real data only. There is no
## runtime inference contract and no synthetic precedence fixture.

var _fails := 0
var _checks := 0

func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("[514] ", label, " -> ", "PASS" if ok else "FAIL")

## Asset-only reference: existing authored values must keep their cast shape.
func _reference_asset_mode(s: Spell) -> int:
	if s.hammer_radius > 0.0:
		return Spell.CastMode.HAMMER
	elif s.shield_radius > 0.0:
		return Spell.CastMode.SHIELD
	elif s.rain_duration > 0.0:
		return Spell.CastMode.RAIN
	elif s.splash_radius > 0.0:
		return Spell.CastMode.SPLASH
	elif s.projectile_count > 0:
		return Spell.CastMode.PROJECTILE
	return Spell.CastMode.NONE

func _collect(res: Resource, out: Array, seen: Dictionary) -> void:
	if res == null or seen.has(res):
		return
	seen[res] = true
	if res is Spell:
		out.append(res)
	for p in res.get_property_list():
		if p["type"] == TYPE_OBJECT:
			var v = res.get(p["name"])
			if v is Resource and not (v is Texture2D) and not (v is SpriteFrames) and not (v is PackedScene):
				_collect(v, out, seen)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var spells: Array = []
	var seen := {}
	for dir in ["res://resources/spells", "res://resources/upgrades"]:
		for fn in DirAccess.get_files_at(dir):
			if fn.ends_with(".tres"):
				_collect(load(dir + "/" + fn) as Resource, spells, seen)
	_check("spell data found (%d)" % spells.size(), spells.size() >= 42)
	var mismatches := 0
	var counts := {}
	for s: Spell in spells:
		var m := s.cast_mode()
		counts[m] = counts.get(m, 0) + 1
		if m != _reference_asset_mode(s):
			mismatches += 1
	_check("authored modes match the reference shape on every spell", mismatches == 0)
	for m in [Spell.CastMode.HAMMER, Spell.CastMode.SHIELD, Spell.CastMode.PROJECTILE]:
		_check("mode %d is used by real data" % m, counts.get(m, 0) > 0)
	print("test514 done: %d checks, %d failures" % [_checks, _fails])
	print("[514] RESULT: ", "ALL PASS" if _fails == 0 else "FAIL")
	quit(0 if _fails == 0 else 1)
