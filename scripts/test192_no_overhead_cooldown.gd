extends SceneTree
## The player draws no cooldown bar above itself; cooldown tracking and the
## cooldown_started signal (which drives the HUD slot bars) still work.

var _area: Node2D
var _player: Node2D
var _caster: SpellCaster
var _started: Array = []
var _frames := 0
var _fails := 0

func _initialize() -> void:
	_area = Node2D.new()
	get_root().add_child(_area)
	current_scene = _area
	_player = load("res://scenes/player.tscn").instantiate()
	_player.position = Vector2(400, 300)
	_area.add_child(_player)
	_caster = _player.get_node("SpellCaster")
	_caster.cooldown_started.connect(func(s: Spell, d: float) -> void: _started.append([s, d]))

func _check(label: String, ok: bool) -> void:
	if not ok:
		_fails += 1
	print("[192] ", label, " -> ", "PASS" if ok else "FAIL")

func _cooldown_bar_nodes(n: Node) -> Array[Node]:
	var found: Array[Node] = []
	for c in n.get_children():
		if String(c.name).begins_with("CooldownBar"):
			found.append(c)
		found.append_array(_cooldown_bar_nodes(c))
	return found

func _process(_dt: float) -> bool:
	_frames += 1
	if _frames == 2:
		var spell: Spell = _caster.equipped_spell
		_check("fire ball equipped from player.tscn starting spells",
			spell != null and spell.resource_path == "res://resources/spells/fire_ball.tres")
		_caster.cast()
		_check("cooldown_started fired once with the spell's 1.2s cooldown",
			_started.size() == 1 and _started[0][0] == spell and is_equal_approx(_started[0][1], 1.2))
		_check("cooldown is tracked after the cast", _caster.cooldown_remaining(spell) > 0.0)
	elif _frames == 10:
		_check("no CooldownBar* node anywhere under the player", _cooldown_bar_nodes(_player).is_empty())
		_check("cooldown still ticking down while on cooldown",
			_caster.cooldown_remaining(_caster.equipped_spell) < 1.2
			and _caster.cooldown_remaining(_caster.equipped_spell) > 0.0)
		_check("aim indicator still present", _player.get_node_or_null("AimIndicator") != null)
		print("[192] DONE fails=", _fails)
		quit(1 if _fails > 0 else 0)
		return true
	return false
