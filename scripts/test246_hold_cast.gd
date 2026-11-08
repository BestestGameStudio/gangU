extends SceneTree
## #246: holding a cast button auto-refires the spell the moment its cooldown
## completes - no re-click. Covers the generic Space/LMB "cast" action and
## the direct slot keys 1-6, and proves that releasing the button stops the
## auto-refire. Real player.tscn caster, real Input.action_press frames.
##
## Timeline (fire_ball cooldown 1.2s, mana_shot cooldown 0.35s):
##   0.05s hold "cast"        -> exactly one fire_ball cast, none while cooling
##   1.6s  still held         -> a second cast happened with no re-press
##   release, wait past 2.4s  -> no further casts (release stops auto-refire)
##   then hold "spell_slot_2" (mana_shot) -> same pattern on the slot path.

var _area: Node2D
var _player: Node2D
var _caster: SpellCaster
var _casts: Array = []
var _fails := 0
var _t := 0.0
var _phase := 0
var _count_mark := -1

func _initialize() -> void:
	_area = Node2D.new()
	get_root().add_child(_area)
	current_scene = _area
	_player = load("res://scenes/player.tscn").instantiate()
	_player.position = Vector2(400, 300)
	_area.add_child(_player)
	_caster = _player.get_node("SpellCaster")
	_caster.spell_cast.connect(func(s: Spell) -> void: _casts.append(s))

func _setup_slots() -> void:
	# Slot 2 holds mana_shot (0.35s) for the slot-key leg; fire_ball stays
	# unslotted so the two legs never share a cooldown entry. Runs on the
	# first process frame: _ready (which fills spells[]) has not fired yet
	# during _initialize.
	if _caster.spells.size() < 2 or _caster.assign_slot(1, _caster.spells[1]) == false:
		print("[246] FAIL setup: mana_shot missing or slot 2 refused it")
		_fails += 1

func _check(label: String, ok: bool) -> void:
	if not ok:
		_fails += 1
	print("[246] ", label, " -> ", "PASS" if ok else "FAIL")

func _process(delta: float) -> bool:
	_t += delta
	match _phase:
		0:
			if _t >= 0.05:
				_setup_slots()
				Input.action_press(&"cast")
				_phase = 1
		1:
			if _t >= 0.3:
				_check("held cast: exactly one fire_ball cast, no refire during cooldown",
					_casts.size() == 1)
				_phase = 2
		2:
			if _t >= 1.6:
				_check("held cast: auto-refire after 1.2s cooldown with no re-press",
					_casts.size() == 2)
				Input.action_release(&"cast")
				_count_mark = _casts.size()
				_phase = 3
		3:
			if _t >= 2.7:
				_check("released cast: no auto-refire once the button is up",
					_casts.size() == _count_mark)
				_count_mark = _casts.size()
				Input.action_press(&"spell_slot_2")
				_phase = 4
		4:
			if _t >= 2.9:
				_check("held slot key: exactly one mana_shot cast on press",
					_casts.size() == _count_mark + 1)
				_phase = 5
		5:
			if _t >= 3.3:
				_check("held slot key: auto-refire after 0.35s cooldown with no re-press",
					_casts.size() >= _count_mark + 2)
				Input.action_release(&"spell_slot_2")
				_count_mark = _casts.size()
				_phase = 6
		6:
			if _t >= 4.2:
				_check("released slot key: no auto-refire once the key is up",
					_casts.size() == _count_mark)
				print("[246] DONE fails=", _fails)
				quit(1 if _fails > 0 else 0)
				return true
	if _t > 8.0:
		print("[246] FAIL timeout in phase ", _phase)
		quit(1)
		return true
	return false
