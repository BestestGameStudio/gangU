extends CanvasLayer
class_name EquipPanel
## #10 equip panel (F): pick an unlocked spell, assign it to one of the six
## caster slots. Implements exactly the approved flow ("pick a spell and
## assign it to one of the six slots, each spell in only one slot") against
## the pinned B slot API (REFUSAL semantics): the panel composes user intent
## with clear_slot()/assign_slot() calls; the caster stays a strict
## primitive. Move-not-copy is the panel's composition, never hidden caster
## behavior.
##
## SETTLED (Daniel's user, 11:05:49 EST): Tab toggles the panel; NO pause -
## combat stays live ("players should find a safe space"); this panel is ALSO
## the manual upgrade UI. Panel owns its own input (equip_panel/Tab), kept
## clear of the caster's spell_slot_1..6 bindings.
##
## STILL BOUNDED:
##   - Not mounted in production (E window decision); harness-driven only.
##   - Style is provisional (pending the open human style choice).
##   - NO duplicate-grant policy: the panel renders get_unlocked() verbatim,
##     duplicates included (unsettled human choice, no silent dedupe).
##   - While visible the panel joins the "modal_ui" group so the caster can
##     skip casting on panel clicks (one-line guard coordinated with B).
##
## UPGRADE HOOK (contract proposed to the #36-38 writer; panel side only):
##   Optional provider node via upgrader_path. Duck-typed:
##     can_upgrade(spell) -> bool
##     get_upgrade_paths(spell) -> Array of {id, name}
##     apply_upgrade(spell, path_id) -> bool
##     signal upgrades_changed(spell)
##   When no provider is wired, no upgrade UI is rendered. Progression
##   qualification, stages and path contents are the provider writer's scope.

## Explicit wiring convention (matches HUD): set before tree entry, or the
## "player" group fallback applies. Production mount is a separate window.
@export var player_path: NodePath
## Optional upgrade provider (see header contract). Unset = equip-only panel.
@export var upgrader_path: NodePath

var _caster: SpellCaster
var _upgrader: Node = null
var _selected: Spell = null
var _upgrade_box: VBoxContainer

var _unlocked_box: VBoxContainer
var _slot_buttons: Array[Button] = []
var _status: Label

func _ready() -> void:
	visible = false
	layer = 10
	# Tab toggle, approved. Runtime registration, idempotent across reloads;
	# panel-owned action, no collision with the caster's spell_slot_1..6.
	if not InputMap.has_action(&"equip_panel"):
		InputMap.add_action(&"equip_panel")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_TAB
		InputMap.action_add_event(&"equip_panel", ev)
	_build_ui()
	var player: Player = null
	if player_path != NodePath(""):
		player = get_node_or_null(player_path) as Player
	if player == null:
		player = get_tree().get_first_node_in_group("player") as Player
	if player == null:
		push_warning("EquipPanel: no player found; panel inert.")
		return
	if upgrader_path != NodePath(""):
		_upgrader = get_node_or_null(upgrader_path)
		if _upgrader != null and _upgrader.has_signal(&"upgrades_changed"):
			_upgrader.upgrades_changed.connect(func(_s): _refresh())
	_caster = player.get_node_or_null("SpellCaster") as SpellCaster
	if _caster == null or not _caster.has_method(&"get_slots"):
		push_warning("EquipPanel: caster slot API not present; panel inert.")
		_caster = null
		return
	if _caster.has_signal(&"slot_assigned"):
		_caster.slot_assigned.connect(func(_i, _s): _refresh())
	if _caster.has_signal(&"slot_cleared"):
		_caster.slot_cleared.connect(func(_i): _refresh())

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	var title := Label.new()
	title.text = "Equip Spells"
	title.add_theme_font_size_override("font_size", 26)
	vbox.add_child(title)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	vbox.add_child(cols)
	_unlocked_box = VBoxContainer.new()
	_unlocked_box.add_theme_constant_override("separation", 4)
	cols.add_child(_unlocked_box)
	var slots_box := VBoxContainer.new()
	slots_box.add_theme_constant_override("separation", 4)
	cols.add_child(slots_box)
	for i in 6:
		var b := Button.new()
		b.add_theme_font_size_override("font_size", 22)
		b.custom_minimum_size = Vector2(220, 0)
		var idx := i
		b.pressed.connect(func(): _on_slot_pressed(idx))
		slots_box.add_child(b)
		_slot_buttons.append(b)
	_upgrade_box = VBoxContainer.new()
	_upgrade_box.add_theme_constant_override("separation", 4)
	vbox.add_child(_upgrade_box)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_status)

func _unhandled_input(event: InputEvent) -> void:
	# No key is bound today (open human choice). If one is ever bound to an
	# "equip_panel" action, this toggles without any code change.
	if InputMap.has_action(&"equip_panel") and event.is_action_pressed(&"equip_panel"):
		if visible:
			hide_panel()
		else:
			show_panel()

func show_panel() -> void:
	_selected = null
	_refresh()
	visible = true
	add_to_group("modal_ui") # caster cast-guard hook (coordinated with B)

func hide_panel() -> void:
	visible = false
	remove_from_group("modal_ui")

func _refresh() -> void:
	if _caster == null:
		return
	for c in _unlocked_box.get_children():
		c.queue_free()
	var header := Label.new()
	header.text = "Unlocked"
	header.add_theme_font_size_override("font_size", 22)
	_unlocked_box.add_child(header)
	for s in _caster.get_unlocked():
		var b := Button.new()
		b.add_theme_font_size_override("font_size", 22)
		b.toggle_mode = true
		b.text = (s as Spell).spell_name
		b.button_pressed = (s == _selected)
		var spell: Spell = s
		b.pressed.connect(func(): _on_spell_pressed(spell))
		_unlocked_box.add_child(b)
	var slots: Array = _caster.get_slots()
	for i in _slot_buttons.size():
		var occupant: Spell = slots[i] if i < slots.size() else null
		_slot_buttons[i].text = "%d: %s" % [i + 1, occupant.spell_name if occupant != null else "(empty)"]
	# Upgrade section: only when a provider is wired AND a spell is selected.
	for c in _upgrade_box.get_children():
		c.queue_free()
	if _upgrader != null and _selected != null and _upgrader.has_method(&"can_upgrade") and _upgrader.can_upgrade(_selected):
		var uheader := Label.new()
		uheader.text = "Upgrades"
		uheader.add_theme_font_size_override("font_size", 22)
		_upgrade_box.add_child(uheader)
		for path in _upgrader.get_upgrade_paths(_selected):
			var b := Button.new()
			b.add_theme_font_size_override("font_size", 22)
			b.text = path.display_name
			var pid = path.id
			b.pressed.connect(func(): _on_upgrade_pressed(pid))
			_upgrade_box.add_child(b)
	_status.text = "Selected: %s" % (_selected.spell_name if _selected != null else "none")

func _on_upgrade_pressed(path_id) -> void:
	if _upgrader == null or _selected == null:
		return
	if not _upgrader.apply_upgrade(_selected, path_id):
		push_warning("EquipPanel: apply_upgrade refused; refreshing.")
	_refresh()

func _on_spell_pressed(spell: Spell) -> void:
	_selected = spell
	_refresh()

func _on_slot_pressed(index: int) -> void:
	if _selected == null or _caster == null:
		return
	var slots: Array = _caster.get_slots()
	# Compose the approved move semantics out of strict primitives.
	for j in slots.size():
		if slots[j] == _selected and j != index:
			_caster.clear_slot(j)
	if index < slots.size() and slots[index] != null and slots[index] != _selected:
		_caster.clear_slot(index)
	if not _caster.assign_slot(index, _selected):
		push_warning("EquipPanel: assign_slot refused; refreshing from caster state.")
	_selected = null
	_refresh()
