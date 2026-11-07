extends SceneTree
## Mastery-fork (second-tier) harness: direct-call cast simulation through the
## REAL SpellProgress/SpellCaster APIs (not physical input - physical Tab /
## fanout / projectile-parameter proof rides the PR's browser probe).
## Fixture: repo main.tscn as-committed on this branch.

var scene: Node
var progress: Node
var caster: Node
var phase := 0
var t := 0.0
var fails := 0

var fireball: Spell = load("res://resources/spells/fire_ball.tres")
var split: Spell = load("res://resources/spells/fire_ball_split.tres")
var beam: Spell = load("res://resources/spells/fire_ball_beam.tres")
var wide: Spell = load("res://resources/spells/fire_ball_split_wide.tres")
var blong: Spell = load("res://resources/spells/fire_ball_beam_long.tres")
var bhom: Spell = load("res://resources/spells/fire_ball_beam_homing.tres")

func _check(label: String, ok: bool) -> void:
	if not ok:
		fails += 1
	print("[M2] ", label, " -> ", "PASS" if ok else "FAIL")

func _casts(spell: Spell, n: int) -> void:
	for i in n:
		progress._on_spell_cast(spell)

func _has_paths(spell: Spell, expected: Array) -> bool:
	var ids: Array = []
	for u in progress.get_upgrade_paths(spell):
		ids.append(u.id)
	if ids.size() != expected.size():
		return false
	for id in expected:
		if not ids.has(id):
			return false
	return true

func _boot() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene

func _grab() -> bool:
	progress = scene.get_node_or_null("SpellProgress")
	caster = scene.get_node_or_null("Player/SpellCaster")
	return progress != null and caster != null

func _initialize() -> void:
	_boot()

func _process(delta: float) -> bool:
	t += delta
	if t < 0.3:
		return false
	match phase:
		0:
			if not _grab():
				_check("mounts present", false)
				return _done()
			_check("mastery paths not offered for base fireball",
				_has_paths(fireball, [&"fireball_beam", &"fireball_split"]))
			_casts(fireball, 10)
			_check("spec fork qualifies at 10 base casts", progress.can_upgrade(fireball))
			caster._cooldowns[fireball] = 0.7
			var idx_before: int = caster.spells.find(fireball)
			_check("split apply succeeds", progress.apply_upgrade(fireball, &"fireball_split"))
			_check("split keeps fireball's equipped position", caster.spells.find(split) == idx_before and idx_before != -1 and caster.equipped_spell == split)
			_check("cooldown transfers to split", is_equal_approx(caster._cooldowns.get(split, -1.0), 0.7)
				and not caster._cooldowns.has(fireball))
			phase = 1; t = 0
		1:
			_check("fresh per-spell cast count after swap", progress.cast_count(split) == 0)
			_casts(split, 14)
			_check("mastery NOT offered at 14 upgraded-spell casts", not progress.can_upgrade(split))
			_casts(split, 1)
			_check("mastery offered at 15 upgraded-spell casts", progress.can_upgrade(split))
			_check("both split mastery paths", _has_paths(split, [&"fireball_m2_split_wide", &"fireball_m2_split_heavy"]))
			caster._cooldowns[split] = 0.9
			var idx2: int = caster.spells.find(split)
			_check("wide apply succeeds", progress.apply_upgrade(split, &"fireball_m2_split_wide"))
			_check("wide keeps the equipped position", caster.spells.find(wide) == idx2 and caster.equipped_spell == wide)
			_check("cooldown transfers to wide", is_equal_approx(caster._cooldowns.get(wide, -1.0), 0.9)
				and not caster._cooldowns.has(split))
			_check("wide cast count fresh", progress.cast_count(wide) == 0)
			_check("no further tier offered for wide", not progress.can_upgrade(wide) and progress.get_upgrade_paths(wide).is_empty())
			phase = 2; t = 0
		2:
			_check("base fire_ball.tres unmutated", fireball.damage == 25.0 and fireball.projectile_count == 1)
			_check("split.tres unmutated", split.damage == 25.0 and split.projectile_count == 3)
			_check("beam.tres unmutated", beam.projectile_speed == 2000.0 and beam.projectile_count == 1)
			scene.queue_free()
			_boot()
			phase = 3; t = 0
		3:
			if not _grab():
				_check("beam-line mounts present", false)
				return _done()
			_casts(fireball, 10)
			_check("beam apply succeeds", progress.apply_upgrade(fireball, &"fireball_beam"))
			_casts(beam, 15)
			_check("all beam mastery paths (incl. #37 piercing/homing)", _has_paths(beam, [&"fireball_m2_beam_long", &"fireball_m2_beam_heavy", &"fireball_m2_beam_piercing", &"fireball_m2_beam_homing"]))
			_check("long-beam apply succeeds", progress.apply_upgrade(beam, &"fireball_m2_beam_long"))
			_check("long beam parameters live", caster.spells.find(blong) != -1
				and caster.equipped_spell == blong
				and blong.range == 1400.0 and blong.projectile_speed == 2600.0)
			scene.queue_free()
			_boot()
			phase = 4; t = 0
		4:
			if not _grab():
				_check("homing-line mounts present", false)
				return _done()
			_casts(fireball, 10)
			_check("beam apply succeeds (homing leg)", progress.apply_upgrade(fireball, &"fireball_beam"))
			_casts(beam, 15)
			_check("homing-beam apply succeeds", progress.apply_upgrade(beam, &"fireball_m2_beam_homing"))
			_check("homing beam live: equipped, beam params kept, homing tag",
				caster.spells.find(bhom) != -1 and caster.equipped_spell == bhom
				and bhom.range == 900.0 and bhom.projectile_speed == 2000.0 and bhom.damage == 25.0
				and bhom.tags.has(SpellTags.HOMING))
			return _done()
		_:
			pass
	return false

func _done() -> bool:
	if fails == 0:
		print("[M2] ALL PASS")
	else:
		print("[M2] DONE failures=", fails)
	quit(fails)
	return true
