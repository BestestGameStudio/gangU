extends SceneTree
## #110 acceptance driver: combat feedback effects (death burst, ENEMY-CENTER
## hit spark, muzzle accent). Pins spawn, geometry/timing caps, lifetime and
## cleanup. Negative leg: on the pre-merge base the effect script is absent
## and every check FAILs explicitly (exit 1). Run:
##   Godot --headless --path . -s res://scripts/test110_combat_feedback.gd

var _failures: int = 0
var _checks: int = 0
var _frames: int = 0
var _stage: int = 0
var _area: Node2D
var _enemy: Node2D
var _caster: Node2D
var _spell: Resource
var _scr = null
var _spark_ref: WeakRef
var _death_ref: WeakRef
var _muzzle_ref: WeakRef

func _check(label: String, ok: bool) -> void:
	_checks += 1
	if ok:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)

func _fx_by_kind(kind: String) -> Array:
	var out: Array = []
	for n in get_nodes_in_group(&"combat_fx"):
		if n.has_meta("kind") and n.get_meta("kind") == kind:
			out.append(n)
	return out

func _initialize() -> void:
	_scr = load("res://scripts/combat_effects.gd")
	if _scr == null:
		# Negative leg (pre-merge base): every check FAILs explicitly.
		for label in [
			"effect script exists",
			"geometry: DEATH_SHARDS == 8",
			"geometry: death radius within 30px cap",
			"timing: all lifetimes <= 0.3s",
			"hit: spark spawns on non-lethal damage (ENEMY-CENTER)",
			"hit: enemy survives non-lethal damage (hp 20/30)",
			"hit: #109 flash untouched (modulate over-bright)",
			"death: burst spawns on lethal damage",
			"death: enemy freed (queue_free last)",
			"death: burst survives the enemy",
			"muzzle: accent spawns on cast",
			"muzzle: accent faces the aim direction",
			"muzzle: accent tinted with spell color",
			"cleanup: no combat_fx remnant after lifetimes",
		]:
			_check(label, false)
		quit(1)
		return
	_check("effect script exists", true)
	_check("geometry: DEATH_SHARDS == 8", _scr.DEATH_SHARDS == 8)
	_check("geometry: death radius within 30px cap", _scr.DEATH_END_R <= 30.0)
	_check("timing: all lifetimes <= 0.3s",
		_scr.DEATH_LIFETIME <= 0.3 and _scr.HIT_LIFETIME <= 0.3 and _scr.MUZZLE_LIFETIME <= 0.3)
	_area = Node2D.new()
	get_root().add_child(_area)
	current_scene = _area
	_enemy = load("res://scenes/enemy.tscn").instantiate()
	_enemy.position = Vector2(300, 300)
	_area.add_child(_enemy)
	_spell = load("res://resources/spells/fire_ball.tres")
	_caster = load("res://scripts/spell_caster.gd").new()
	_caster.projectile_scene = load("res://scenes/projectile.tscn")
	_caster.position = Vector2(400, 300)
	_area.add_child(_caster)

func _process(_dt: float) -> bool:
	_frames += 1
	match _stage:
		0:
			if _frames >= 2:
				_enemy.apply_damage(10)
				_stage = 1
		1:
			if _frames >= 4:
				var sparks: Array = _fx_by_kind("HIT_SPARK")
				_check("hit: spark spawns on non-lethal damage (ENEMY-CENTER)", sparks.size() == 1)
				_check("hit: enemy survives non-lethal damage (hp 20/30)",
					is_instance_valid(_enemy) and _enemy.hp == 20)
				_check("hit: #109 flash untouched (modulate over-bright)",
					is_instance_valid(_enemy) and _enemy.modulate == Color(2.4, 2.4, 2.4))
				if sparks.size() == 1:
					_spark_ref = weakref(sparks[0])
					_check("hit: spark parented to area (survives enemy)",
						sparks[0].get_parent() == _area)
					_check("hit: spark at enemy center",
						sparks[0].global_position.distance_to(Vector2(300, 300)) < 1.0)
				else:
					_check("hit: spark parented to area (survives enemy)", false)
					_check("hit: spark at enemy center", false)
				_enemy.apply_damage(999)
				_stage = 2
		2:
			if _frames >= 6:
				var bursts: Array = _fx_by_kind("DEATH_BURST")
				_check("death: burst spawns on lethal damage", bursts.size() == 1)
				_check("death: enemy freed (queue_free last)", not is_instance_valid(_enemy))
				if bursts.size() == 1:
					_death_ref = weakref(bursts[0])
					_check("death: burst survives the enemy",
						bursts[0].is_inside_tree() and not bursts[0].is_queued_for_deletion())
				else:
					_check("death: burst survives the enemy", false)
				_caster._cast_spell(_spell)
				_stage = 3
		3:
			if _frames >= 8:
				var muzzles: Array = _fx_by_kind("MUZZLE")
				_check("muzzle: accent spawns on cast", muzzles.size() == 1)
				if muzzles.size() == 1:
					_muzzle_ref = weakref(muzzles[0])
					var want: float = Vector2(-400, -300).normalized().angle()
					_check("muzzle: accent faces the aim direction",
						absf(wrapf(muzzles[0].rotation - want, -PI, PI)) < 0.01)
					_check("muzzle: accent tinted with spell color",
						muzzles[0].get("_color") == _spell.projectile_color)
					_check("muzzle: accent at the cast point",
						muzzles[0].global_position.distance_to(Vector2(400, 300)) < 1.0)
				else:
					_check("muzzle: accent faces the aim direction", false)
					_check("muzzle: accent tinted with spell color", false)
					_check("muzzle: accent at the cast point", false)
				_stage = 4
		4:
			if _frames >= 60:
				# All lifetimes (<= 0.3s) plus margin have passed (headless idle delta is real-time, so wait well past 0.3s of accumulated fx _process time).
				_check("cleanup: no combat_fx remnant after lifetimes",
					get_nodes_in_group(&"combat_fx").is_empty())
				_check("cleanup: spark freed", _spark_ref == null or _spark_ref.get_ref() == null)
				_check("cleanup: death burst freed", _death_ref == null or _death_ref.get_ref() == null)
				_check("cleanup: muzzle freed", _muzzle_ref == null or _muzzle_ref.get_ref() == null)
				print("DONE checks=", _checks, " failures=", _failures)
				quit(0 if _failures == 0 else 1)
				return true
	return false
