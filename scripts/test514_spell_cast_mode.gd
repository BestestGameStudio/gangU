extends SceneTree
## #514: Spell.cast_mode() is the single place the cast shape is inferred.
## It must agree with the old inline precedence chain (hammer, shield, rain,
## splash, projectile) for EVERY spell reachable from resources/spells and
## resources/upgrades, and every mode must be exercised by real data.
## Run: godot --headless --fixed-fps 60 --path . -s scripts/test514_spell_cast_mode.gd

var _fails := 0
var _checks := 0

func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("[514] ", label, " -> ", "PASS" if ok else "FAIL")

## The pre-#514 chain, kept here as the reference.
func _old_chain(s: Spell) -> int:
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
		if m != _old_chain(s):
			mismatches += 1
	_check("cast_mode agrees with the old chain on every spell", mismatches == 0)
	for m in [Spell.CastMode.HAMMER, Spell.CastMode.SHIELD, Spell.CastMode.PROJECTILE]:
		_check("mode %d is used by real data" % m, counts.get(m, 0) > 0)
	# Precedence on synthetic specs: the earlier branch wins.
	var s := Spell.new()
	s.projectile_count = 0
	_check("no-shape spell is NONE", s.cast_mode() == Spell.CastMode.NONE)
	s.projectile_count = 1
	_check("projectile only", s.cast_mode() == Spell.CastMode.PROJECTILE)
	s.splash_radius = 10.0
	_check("splash beats projectile", s.cast_mode() == Spell.CastMode.SPLASH)
	s.rain_duration = 1.0
	_check("rain beats splash", s.cast_mode() == Spell.CastMode.RAIN)
	s.shield_radius = 10.0
	_check("shield beats rain", s.cast_mode() == Spell.CastMode.SHIELD)
	s.hammer_radius = 10.0
	_check("hammer beats shield", s.cast_mode() == Spell.CastMode.HAMMER)
	var f := Spell.new()
	f.projectile_count = 0
	f.freeze_radius = 50.0
	_check("freeze-only bubble spell is NONE", f.cast_mode() == Spell.CastMode.NONE)
	print("test514 done: %d checks, %d failures" % [_checks, _fails])
	print("[514] RESULT: ", "ALL PASS" if _fails == 0 else "FAIL")
	quit(0 if _fails == 0 else 1)
