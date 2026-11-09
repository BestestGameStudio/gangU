extends SceneTree
## #305 harness: Spirit Punch launch - Mastery tier (PR-C).
## Contract under test: a launch spell moves the player forward BEFORE
## attacking (Daniel's Mastery spec), the attack fires at the settled
## post-movement position, a refused launch is not a cast (no cooldown, no
## signals - the #216 refused-placement convention), dash input mid-launch
## is refused without consuming dash cooldown, death mid-launch cancels the
## deferred attack with no stale volley after a revive, casting mid-dash is
## coherent (dash clocks/signals untouched), and the whole launch costs ONE
## cooldown/signal pair including the cumulative burst. Punch lifetime
## (0.1s) is shorter than the burst interval (0.15s), so punches are
## counted cumulatively, never simultaneously.
## Run headless:
##   godot --headless --script scripts/test305_spirit_punch_launch.gd

const LAUNCH_PATH := "res://resources/spells/spirit_punch_launch.tres"
const BASE_PATH := "res://resources/spells/spirit_punch.tres"
const BURST_PATH := "res://resources/spells/spirit_punch_burst.tres"

var _area: Node2D
var _player: Node2D
var _caster: SpellCaster
var _checks := 0
var _failures := 0
var _casts: Array = []
var _cooldowns: Array = []
var _launch_starts := 0
var _launch_ends := 0
var _launch_cancels := 0
var _dash_starts := 0
var _dash_ends := 0
var _seen_punches: Dictionary = {}
var _end_pos := Vector2.ZERO

func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if ok:
		print("PASS: %s" % msg)
	else:
		_failures += 1
		print("FAIL: %s" % msg)

func _collect_punches() -> void:
	for c in _area.get_children():
		if c is Projectile:
			_seen_punches[c.get_instance_id()] = true

func _aim_dir() -> Vector2:
	var dir: Vector2 = _caster.global_position.direction_to(_caster.get_global_mouse_position())
	if dir.length_squared() == 0.0:
		dir = Vector2.RIGHT.rotated(_player.rotation)
	return dir

func _reset_counters() -> void:
	_casts.clear()
	_cooldowns.clear()
	_seen_punches.clear()
	_launch_starts = 0
	_launch_ends = 0
	_launch_cancels = 0
	_dash_starts = 0
	_dash_ends = 0

func _initialize() -> void:
	print("test305_launch: Spirit Punch launch - Mastery (#305)")
	_area = Node2D.new()
	get_root().add_child(_area)
	current_scene = _area
	_player = load("res://scenes/player.tscn").instantiate()
	_player.position = Vector2(400, 300)
	_area.add_child(_player)
	_caster = _player.get_node("SpellCaster")
	_caster.spell_cast.connect(func(s: Spell) -> void: _casts.append(s))
	_caster.cooldown_started.connect(func(s: Spell, d: float) -> void: _cooldowns.append(d))
	_player.launch_started.connect(func(_d: Vector2) -> void: _launch_starts += 1)
	_player.launch_ended.connect(func() -> void:
		_launch_ends += 1
		_end_pos = _player.global_position)
	_player.launch_cancelled.connect(func() -> void: _launch_cancels += 1)
	_player.dash_started.connect(func(_d: Vector2) -> void: _dash_starts += 1)
	_player.dash_ended.connect(func() -> void: _dash_ends += 1)

	var spell: Spell = load(LAUNCH_PATH)
	_check(spell != null, "spirit_punch_launch.tres loads")
	if spell == null:
		quit(1)
		return
	_check(spell.spell_name == "Spirit Punch", "launch spell keeps the Spirit Punch name")
	_check(spell.icon_upgraded, "launch resource is marked as an upgrade result")
	_check(is_equal_approx(spell.launch_speed, 700.0), "launch speed 700 (provisional)")
	_check(is_equal_approx(spell.launch_duration, 0.12), "launch duration 0.12s (provisional)")
	_check(spell.burst_count == 3 and is_equal_approx(spell.burst_interval, 0.15), "launch is cumulative with the burst (3x0.15s)")
	var base: Spell = load(BASE_PATH)
	_check(base.launch_speed == 0.0, "base Spirit Punch has launch_speed 0 (no launch)")
	var burst: Spell = load(BURST_PATH)
	_check(burst.launch_speed == 0.0, "burst resource has launch_speed 0 (no launch)")

	_caster.add_spell(spell)
	await physics_frame

	# Phase A: launch-first sequencing, settled position, cumulative burst.
	var start_pos: Vector2 = _player.global_position
	_caster.cast()
	await physics_frame
	_collect_punches()
	_check(_launch_starts == 1, "cast starts the launch BEFORE any attack")
	_check(_casts.size() == 1, "one spell_cast for the whole launch+burst")
	_check(_cooldowns.size() == 1 and is_equal_approx(_cooldowns[0], 0.8), "one cooldown of spell length at cast time")
	_check(_seen_punches.is_empty(), "no punch spawns while the launch runs")
	# Dash input mid-launch is refused and wastes no dash cooldown (phase C).
	var dash_refused: bool = not _player.try_dash(Vector2.RIGHT)
	_check(dash_refused, "dash mid-launch is refused")
	_check(_dash_starts == 0 and _player.dash_cooldown_remaining() == 0.0, "refused dash consumes no dash cooldown")
	# A second cast mid-launch is refused: already launching.
	_caster.cast()
	await physics_frame
	_check(_casts.size() == 1 and _cooldowns.size() == 1, "cast mid-launch refused (no extra cast/cooldown)")
	# Run past launch end (0.12s ~ 8 frames) and both burst intervals.
	for i in 45:
		await physics_frame
		_collect_punches()
	_check(_launch_ends == 1, "launch_ended fires once")
	var traveled: float = start_pos.distance_to(_end_pos)
	_check(traveled > 80.0 and traveled < 110.0, "player actually launches ~700px/s*0.12s (got %.1f)" % traveled)
	var along: float = (_end_pos - start_pos).dot(_aim_dir())
	_check(along > 75.0, "launch travels along the aim direction (dot %.1f)" % along)
	_check(_seen_punches.size() == 3, "exactly 3 punches total (cumulative launch+burst)")
	# The attack spawns at the settled position: punches are 900px/s, so any
	# live punch is at most a frame (15px) past its spawn point near the end.
	var nearest := INF
	for c in _area.get_children():
		if c is Projectile:
			nearest = minf(nearest, c.global_position.distance_to(_end_pos))
	# All 3 expired by now (0.1s lifetime); verify via spawn record instead:
	# re-run one cast and capture the first punch's spawn frame position.
	_reset_counters()
	_caster.cast()
	await physics_frame
	for i in 20:
		await physics_frame
		if _launch_ends == 1:
			break
	await physics_frame
	var spawn_d := INF
	for c in _area.get_children():
		if c is Projectile:
			spawn_d = minf(spawn_d, c.global_position.distance_to(_end_pos))
	_check(spawn_d < 20.0, "first punch spawns at the settled launch position (d=%.1f)" % spawn_d)
	for i in 40:
		await physics_frame

	# Phase B: dead player - refused launch is not a cast at all.
	_reset_counters()
	_player.hp = 0
	await physics_frame
	_caster.cast()
	await physics_frame
	for i in 10:
		await physics_frame
		_collect_punches()
	_check(_casts.is_empty() and _cooldowns.is_empty(), "dead cast: no cooldown, no signals (#216 refusal convention)")
	_check(_launch_starts == 0 and _seen_punches.is_empty(), "dead cast: no launch, no attack")
	_player.hp = 100
	await physics_frame

	# Phase D: death mid-launch cancels the deferred attack; no stale volley.
	_reset_counters()
	_caster.cast()
	await physics_frame
	for i in 3:
		await physics_frame
	_check(_launch_starts == 1 and _launch_ends == 0, "mid-launch state reached")
	_player.hp = 0
	await physics_frame
	await physics_frame
	_check(_launch_cancels == 1, "death mid-launch cancels the launch")
	_check(_launch_ends == 0, "cancelled launch never emits launch_ended")
	for i in 20:
		await physics_frame
		_collect_punches()
	_check(_seen_punches.is_empty(), "cancelled launch fires no attack")
	_player.hp = 100
	await physics_frame
	_caster.cast()
	await physics_frame
	for i in 45:
		await physics_frame
		_collect_punches()
	_check(_seen_punches.size() == 3, "after revive, a new launch fires exactly its own 3 punches (no stale volley)")
	_check(_launch_ends == 1 and _launch_cancels == 1, "no leftover connection from the cancelled launch")

	# Phase E: cast mid-dash - dash clocks/signals untouched, launch wins motion.
	_reset_counters()
	_player.try_dash(Vector2.DOWN)
	_caster.cast()
	await physics_frame
	_check(_dash_starts == 1 and _launch_starts == 1, "cast mid-dash: dash kept, launch accepted")
	var dash_pos: Vector2 = _player.global_position
	for i in 12:
		await physics_frame
		_collect_punches()
	_check(_launch_ends == 1, "launch ends on its own clock during the dash")
	var moved: Vector2 = _player.global_position - dash_pos
	_check(moved.dot(_aim_dir()) > moved.dot(Vector2.DOWN), "launch motion wins over the dash while both run")
	for i in 10:
		await physics_frame
		_collect_punches()
	_check(_dash_ends == 1, "dash_ended still fires on schedule")
	for i in 40:
		await physics_frame
		_collect_punches()
	_check(_seen_punches.size() == 3, "mid-dash cast still fires its full burst")

	# Phase F: base spell unchanged - immediate punch, no launch.
	_reset_counters()
	_caster.spells.clear()
	_caster.current_index = 0
	_caster.add_spell(base)
	await physics_frame
	_caster.cast()
	await physics_frame
	_collect_punches()
	_check(_launch_starts == 0 and _launch_ends == 0, "base spell never launches")
	_check(_seen_punches.size() == 1, "base spell punches immediately")
	_check(_casts.size() == 1 and _cooldowns.size() == 1, "base spell: one cast, one cooldown")

	print("test305_launch: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

func _process(_delta: float) -> bool:
	return false
