class_name SpellTriggerRouter
extends RefCounted
## One input state machine for every cast key. No scene, clock or input
## singleton dependency: callers sample keys and consume typed commands.
enum Command { CAST, BEGIN_CHARGE, RELEASE_CHARGE, CANCEL_CHARGE }
var _held: Dictionary = {}

func _event(command: Command, state: Dictionary) -> Dictionary:
	return {"command": command, "spell": state.spell, "mode": state.mode,
		"alternate": state.alternate, "seconds": state.seconds}

func sample(action: StringName, spell: Spell, pressed: bool, alternate: bool, delta: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _held.has(action) and _held[action].spell != spell:
		out.append_array(cancel(action))
	if spell == null:
		return out
	if not _held.has(action):
		if not pressed: return out
		var alt := alternate and spell.supports_trigger(Spell.TriggerMode.ALTERNATE)
		var mode := Spell.TriggerMode.ALTERNATE if alt else Spell.TriggerMode.DEFAULT
		var charging := spell.supports_trigger(Spell.TriggerMode.CHARGING) and (not alt or spell.alternate_can_charge)
		_held[action] = {"spell": spell, "mode": mode, "alternate": alt,
			"seconds": 0.0, "can_charge": charging, "charging": false}
	var state: Dictionary = _held[action]
	if not pressed:
		if state.charging:
			out.append(_event(Command.RELEASE_CHARGE, state))
		elif state.can_charge and spell.supports_trigger(state.mode):
			out.append(_event(Command.CAST, state))
		_held.erase(action)
		return out
	state.seconds += maxf(delta, 0.0)
	if state.can_charge:
		if not state.charging and state.seconds >= maxf(spell.charge_delay, 0.0):
			state.charging = true
			state.mode = Spell.TriggerMode.CHARGING
			out.append(_event(Command.BEGIN_CHARGE, state))
	elif spell.supports_trigger(state.mode):
		# No charge mode: preserve held auto-refire; caster owns cooldown.
		out.append(_event(Command.CAST, state))
	return out

func cancel(action: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _held.has(action):
		if _held[action].charging:
			out.append(_event(Command.CANCEL_CHARGE, _held[action]))
		_held.erase(action)
	return out

func cancel_all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for action: StringName in _held.keys(): out.append_array(cancel(action))
	return out
