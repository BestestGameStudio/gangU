extends SceneTree
## #323 harness: Spirit Punch Signature renamed to "The World". Casting the
## Signature spell spawns the freeze bubble at the cast point and does
## nothing else: no launch, no fists (no projectiles at all). Specialization
## (burst) and Mastery (launch) behaviour is unchanged.
## Run headless:
##   godot --headless --script scripts/test323_the_world.gd

const SIG_PATH := "res://resources/spells/spirit_punch_bubble.tres"
const SIG_UP_PATH := "res://resources/upgrades/spirit_punch_bubble.tres"
const BURST_PATH := "res://resources/spells/spirit_punch_burst.tres"
const LAUNCH_PATH := "res://resources/spells/spirit_punch_launch.tres"

var _area: Node2D
var _player: Node2D
var _caster: SpellCaster
var _checks := 0
var _failures := 0
var _casts := 0
var _cooldowns := 0
var _launch_starts := 0
var _seen: Dictionary = {}

func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if ok:
		print("PASS: %s" % msg)
	else:
		_failures += 1
		print("FAIL: %s" % msg)

func _collect() -> void:
	for c in _area.get_children():
		if c is Projectile:
			_seen[c.get_instance_id()] = true

func _reset() -> void:
	_casts = 0
	_cooldowns = 0
	_launch_starts = 0
	_seen.clear()

func _use(spell: Spell) -> void:
	_caster.spells.clear()
	_caster.current_index = 0
	_caster.add_spell(spell)

func _initialize() -> void:
	print("test323: Spirit Punch Signature 'The World' (#323)")
	var up: SpellUpgrade = load(SIG_UP_PATH)
	var sig: Spell = load(SIG_PATH)
	_check(up.display_name == "The World", "Signature upgrade is named The World")
	_check(up.tier == 3 and up.result_spell == sig, "still the tier-3 Signature upgrade")
	_check(sig.launch_speed == 0.0, "Signature has no launch")
	_check(sig.projectile_count == 0, "Signature throws no fists")
	_check(sig.freeze_radius > 0.0 and is_equal_approx(sig.freeze_duration, 5.0), "Signature keeps the 5s freeze")

	_area = Node2D.new()
	get_root().add_child(_area)
	current_scene = _area
	_player = load("res://scenes/player.tscn").instantiate()
	_player.position = Vector2(400, 300)
	_area.add_child(_player)
	_caster = _player.get_node("SpellCaster")
	_caster.spell_cast.connect(func(_s: Spell) -> void: _casts += 1)
	_caster.cooldown_started.connect(func(_s: Spell, _d: float) -> void: _cooldowns += 1)
	_player.launch_started.connect(func(_d: Vector2) -> void: _launch_starts += 1)

	# Signature cast: bubble only.
	_use(sig)
	await physics_frame
	var start: Vector2 = _player.global_position
	_caster.cast()
	await physics_frame
	for i in 45:
		await physics_frame
		_collect()
	var bubbles := get_nodes_in_group(&"freeze_bubbles")
	_check(bubbles.size() == 1, "cast spawns exactly one bubble")
	if bubbles.size() == 1:
		_check((bubbles[0] as Node2D).global_position.distance_to(start) < 1.0, "bubble anchored at the cast point")
	_check(_launch_starts == 0, "Signature cast does not launch the player")
	_check(_player.global_position.distance_to(start) < 1.0, "player did not move")
	_check(_seen.is_empty(), "Signature cast throws no fists")
	_check(_casts == 1 and _cooldowns == 1, "one cast, one cooldown")
	for b in bubbles:
		b.queue_free()
	await physics_frame
	await physics_frame

	# Specialization unchanged: 3 burst punches, no launch.
	_reset()
	_use(load(BURST_PATH))
	await physics_frame
	_caster.cast()
	for i in 45:
		await physics_frame
		_collect()
	_check(_seen.size() == 3 and _launch_starts == 0, "Specialization still bursts 3 punches, no launch")

	# Mastery unchanged: launch + 3 punches.
	_reset()
	_use(load(LAUNCH_PATH))
	await physics_frame
	_caster.cast()
	for i in 50:
		await physics_frame
		_collect()
	_check(_launch_starts == 1 and _seen.size() == 3, "Mastery still launches and bursts 3 punches")

	print("test323: %d checks, %d failures" % [_checks, _failures])
	print("RESULT: %s" % ("ALL PASS" if _failures == 0 else "FAILURES PRESENT"))
	quit(1 if _failures > 0 else 0)

func _process(_delta: float) -> bool:
	return false
