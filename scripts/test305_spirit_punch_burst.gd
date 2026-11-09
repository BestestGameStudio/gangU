extends SceneTree
## #305 harness: Spirit Punch burst - Specialization tier (PR-B).
## Contract under test: burst_count repeats the fan-out in a short burst at
## burst_interval spacing, re-aimed per shot like a repeated cast (#246);
## ONE cooldown and one spell_cast/cooldown_started pair per cast; the
## burst runs on the player-owned caster's clock, so it continues while a
## freeze holds everything else. burst_count 1 (every existing spell)
## stays exactly single-fan-out. Punch lifetime (0.1s) is shorter than the
## burst interval (0.15s), so punches are counted cumulatively, never
## simultaneously.
## Run headless:
##   godot --headless --script scripts/test305_spirit_punch_burst.gd

const BURST_PATH := "res://resources/spells/spirit_punch_burst.tres"
const BASE_PATH := "res://resources/spells/spirit_punch.tres"

var _area: Node2D
var _player: Node2D
var _caster: SpellCaster
var _checks := 0
var _failures := 0
var _casts: Array = []
var _cooldowns: Array = []
var _seen_punches: Dictionary = {}

func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if ok:
		print("PASS: %s" % msg)
	else:
		_failures += 1
		print("FAIL: %s" % msg)

func _collect_punches() -> int:
	var alive := 0
	for c in _area.get_children():
		if c is Projectile:
			_seen_punches[c.get_instance_id()] = true
			alive += 1
	return alive

func _initialize() -> void:
	print("test305_burst: Spirit Punch burst - Specialization (#305)")
	_area = Node2D.new()
	get_root().add_child(_area)
	current_scene = _area
	_player = load("res://scenes/player.tscn").instantiate()
	_player.position = Vector2(400, 300)
	_area.add_child(_player)
	_caster = _player.get_node("SpellCaster")
	_caster.spell_cast.connect(func(s: Spell) -> void: _casts.append(s))
	_caster.cooldown_started.connect(func(s: Spell, d: float) -> void: _cooldowns.append(d))

	var spell: Spell = load(BURST_PATH)
	_check(spell != null, "spirit_punch_burst.tres loads")
	if spell == null:
		quit(1)
		return
	_check(spell.spell_name == "Spirit Punch", "burst spell keeps the Spirit Punch name")
	_check(spell.icon_upgraded, "burst resource is marked as an upgrade result")
	_check(spell.burst_count == 3, "burst resource fires 3 punches (provisional)")
	_check(is_equal_approx(spell.burst_interval, 0.15), "burst interval 0.15s (provisional)")
	_check(spell.tags.has(&"melee") and spell.projectile_count == 1, "still a single melee punch per fan-out")

	var base: Spell = load(BASE_PATH)
	_check(base.burst_count == 1, "base Spirit Punch has burst_count 1 (no burst)")

	_caster.add_spell(spell)
	await physics_frame
	_caster.cast()
	await physics_frame
	_collect_punches()
	_check(_casts.size() == 1 and _casts[0] == spell, "one spell_cast for the whole burst")
	_check(_cooldowns.size() == 1 and is_equal_approx(_cooldowns[0], 0.8), "one cooldown of spell length, not per punch")
	_check(_seen_punches.size() == 1, "first punch spawns immediately")

	# ~0.15s interval = ~9 physics frames at 60fps; run well past both intervals.
	for i in 30:
		await physics_frame
		_collect_punches()
	_check(_seen_punches.size() == 3, "burst fires exactly 3 punches total (cumulative)")
	_check(_casts.size() == 1 and _cooldowns.size() == 1, "no extra cast/cooldown signals from the burst")
	_check(_caster.cooldown_remaining(spell) > 0.0, "single cooldown still ticking after the burst")

	# after 0.8s the one cooldown expires and the spell is castable again
	for i in 30:
		await physics_frame
	_check(_caster.cooldown_remaining(spell) <= 0.0, "cooldown expires after the single 0.8s entry")

	print("---\ntest305_burst: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
