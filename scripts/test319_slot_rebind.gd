extends SceneTree
## #319 harness: slot cast keys are LMB, RMB, Q, E, R, F (re-settled by Daniel
## 2026-11-08 from digits 1-6); the legacy generic `cast` keeps Space only
## (LMB is slot 1 now, a press must not double-fire).
##
## Coverage:
##   1. spell_slot_1 binds mouse LEFT, spell_slot_2 binds mouse RIGHT.
##   2. spell_slot_3..6 bind physical Q, E, R, F.
##   3. No spell_slot action binds digit keys 1-6 anymore.
##   4. The legacy `cast` action has NO mouse-button events (Space preserved).
##   5. Functional: pressing spell_slot_1 casts slot 1 (Fire Ball) exactly once.
##   6. Modal UI suppression still gates input-driven slot casts.
##   7. After the modal closes, spell_slot_2 casts slot 2 (Mana Shot).
var scene: Node
var p: Player
var caster: SpellCaster
var modal: Control
var cast_log: Array = []
var phase := 0
var t := 0.0
var ok := true

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	p = scene.get_node("Player")
	caster = p.get_node("SpellCaster")
	caster.spell_cast.connect(func(s: Spell): cast_log.append(s.spell_name))

func _fail(msg: String, extra: Variant = null) -> void:
	print("[319] FAIL ", msg, "" if extra == null else str(": ", extra))
	ok = false

func _pass(msg: String) -> void:
	print("[319] ", msg, " -> PASS")

func _mouse_button(action: StringName) -> int:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventMouseButton:
			return ev.button_index
	return 0

func _keycodes(action: StringName) -> Array:
	var out: Array = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			out.append(ev.physical_keycode)
	return out

func _process(delta: float) -> bool:
	t += delta
	match phase:
		0:
			# Main._ready (hub load + slot seeding + action registration).
			if scene.current_area == null:
				return false
			phase = 1; t = 0
		1:
			if t > 0.3:
				# 1-3: slot action bindings.
				if _mouse_button(&"spell_slot_1") == MOUSE_BUTTON_LEFT:
					_pass("slot 1 bound to left mouse button")
				else:
					_fail("slot 1 mouse binding", _mouse_button(&"spell_slot_1"))
				if _mouse_button(&"spell_slot_2") == MOUSE_BUTTON_RIGHT:
					_pass("slot 2 bound to right mouse button")
				else:
					_fail("slot 2 mouse binding", _mouse_button(&"spell_slot_2"))
				var want := [KEY_Q, KEY_E, KEY_R, KEY_F]
				var keys_ok := true
				for i in 4:
					if _keycodes(StringName("spell_slot_%d" % (i + 3))) != [want[i]]:
						keys_ok = false
						_fail("slot %d keycode" % (i + 3), _keycodes(StringName("spell_slot_%d" % (i + 3))))
				if keys_ok:
					_pass("slots 3-6 bound to physical Q, E, R, F")
				var digits_ok := true
				for i in SpellCaster.SLOT_COUNT:
					for kc in _keycodes(StringName("spell_slot_%d" % (i + 1))):
						if kc >= KEY_1 and kc <= KEY_6:
							digits_ok = false
							_fail("slot %d still binds a digit" % (i + 1), kc)
				if digits_ok:
					_pass("no slot binds digit keys 1-6")
				# 4: legacy cast has no mouse events.
				if _mouse_button(&"cast") == 0:
					_pass("legacy cast has no mouse button (LMB moved to slot 1)")
				else:
					_fail("legacy cast still binds a mouse button", _mouse_button(&"cast"))
				# 4b: consumable-use moved to C (E is slot 4 now).
				var use_keys := _keycodes(&"use_consumable")
				if use_keys == [KEY_C]:
					_pass("use_consumable bound to physical KEY_C")
				else:
					_fail("use_consumable keycodes", use_keys)
				phase = 2; t = 0
		2:
			# 5: one LMB press casts slot 1 exactly once.
			Input.action_press(&"spell_slot_1")
			phase = 3; t = 0
		3:
			if t > 0.3:
				Input.action_release(&"spell_slot_1")
				if cast_log == ["Fire Ball"]:
					_pass("LMB slot-1 press cast Fire Ball exactly once")
				else:
					_fail("slot-1 press cast log", cast_log)
				# 6: modal UI suppresses input-driven slot casts.
				modal = Control.new()
				modal.add_to_group("modal_ui")
				scene.add_child(modal)
				Input.action_press(&"spell_slot_2")
				phase = 4; t = 0
		4:
			if t > 0.3:
				Input.action_release(&"spell_slot_2")
				if cast_log == ["Fire Ball"]:
					_pass("modal UI suppresses slot casts")
				else:
					_fail("slot cast fired while modal open", cast_log)
				# 7: after the modal closes, slot 2 casts.
				modal.queue_free()
				Input.action_press(&"spell_slot_2")
				phase = 5; t = 0
		5:
			if t > 0.3:
				Input.action_release(&"spell_slot_2")
				if cast_log == ["Fire Ball", "Mana Shot"]:
					_pass("slot-2 press casts Mana Shot after modal closes")
				else:
					_fail("slot-2 press cast log", cast_log)
				# 8: Q (slot 3) casts a newly auto-bound spell (#262 funnel).
				caster.unlock_spell(load("res://resources/spells/placeholder_bolt.tres"))
				Input.action_press(&"spell_slot_3")
				phase = 6; t = 0
		6:
			if t > 0.3:
				Input.action_release(&"spell_slot_3")
				if cast_log == ["Fire Ball", "Mana Shot", "Placeholder Bolt"]:
					_pass("Q slot-3 press casts the auto-bound Bolt")
				else:
					_fail("slot-3 press cast log", cast_log)
				print("[319] RESULT: ", "ALL PASS" if ok else "FAILURES")
				quit(0 if ok else 1)
	return not ok
