extends SceneTree
## #441 demo (real scene, real input events through Input.parse_input_event,
## exactly what a player's mouse does): the Tab menu hugs its content (no
## empty block below the slots), upgrade cards are slimmer, and slot
## rearrange is hold-and-drag - drag onto a slot swaps, onto an empty slot
## moves; a plain click only selects. Run under xvfb with --write-movie;
## quits itself.

var _panel: EquipPanel
var _caster: SpellCaster
var _label: Label
var _phase := ""

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1152, 648)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	for i in 10:
		await process_frame
	_panel = main.get_node("EquipPanel")
	_caster = main.get_node("Player/SpellCaster")
	# Three spells slotted, fireball qualified for upgrades.
	var heavy: Spell = load("res://resources/spells/bolt_heavy.tres")
	var flurry: Spell = load("res://resources/spells/bolt_flurry.tres")
	_caster.unlock_spell(heavy)
	_caster.unlock_spell(flurry)
	var slots: Array = _caster.get_slots()
	if not slots.has(heavy):
		_caster.clear_slot(1)
		_caster.assign_slot(1, heavy)
	if not slots.has(flurry):
		_caster.clear_slot(2)
		_caster.assign_slot(2, flurry)
	var fire: Spell = load("res://resources/spells/fire_ball.tres")
	for i in 10:
		_caster.spell_cast.emit(fire)
	var hud := CanvasLayer.new()
	hud.layer = 50
	root.add_child(hud)
	_label = Label.new()
	_label.position = Vector2(24, 12)
	_label.add_theme_font_size_override("font_size", 26)
	hud.add_child(_label)

	_phase = "opening the Tab menu: no empty block under the slots"
	await _tap_key(KEY_TAB)
	await _run_frames(100)

	_phase = "click a slot: selects its spell (slimmer upgrade cards)"
	await _click(_slot_center(0))
	await _run_frames(110)

	_phase = "click another slot: only the selection moves (no click-swap)"
	await _click(_slot_center(1))
	await _run_frames(90)

	_phase = "hold and drag onto a slot: the two spells swap"
	await _drag(_slot_center(1), _slot_center(0))
	await _run_frames(90)

	_phase = "drag onto an empty slot: the spell moves there"
	await _drag(_slot_center(2), _slot_center(4))
	await _run_frames(100)

	_phase = ""
	await _tap_key(KEY_TAB)
	await _run_frames(40)
	quit(0)

func _slot_center(i: int) -> Vector2:
	return _panel._slot_buttons[i].get_global_rect().get_center()

func _run_frames(n: int) -> void:
	for i in n:
		await physics_frame
		_label.text = "#441 Tab menu polish\n%s" % _phase
		await process_frame

func _ev_key(k: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = k
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _tap_key(k: Key) -> void:
	_ev_key(k, true)
	await _run_frames(2)
	_ev_key(k, false)
	await _run_frames(2)

func _ev_mouse_button(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	Input.parse_input_event(ev)

func _ev_mouse_move(pos: Vector2, held: bool) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	if held:
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(ev)

func _click(pos: Vector2) -> void:
	_ev_mouse_move(pos, false)
	await _run_frames(2)
	_ev_mouse_button(pos, true)
	await _run_frames(2)
	_ev_mouse_button(pos, false)
	await _run_frames(4)

func _drag(from: Vector2, to: Vector2) -> void:
	_ev_mouse_move(from, false)
	await _run_frames(3)
	_ev_mouse_button(from, true)
	await _run_frames(16) # hold before moving: press-and-hold
	for i in 14:
		_ev_mouse_move(from.lerp(to, float(i + 1) / 14.0), true)
		await _run_frames(2)
	_ev_mouse_button(to, false)
	await _run_frames(4)
