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
##   - Mounted in production by main.gd (ONE persistent child); harness
##     mounts (test_e_mount et al.) keep working the same way.
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
var _stats_box: VBoxContainer
var _player: Player = null
var _slot_buttons: Array[Button] = []
var _slot_icons: Array[SpellIcon] = []
var _status: Label

## Two state channels per unlocked row: left-edge chip = equipped-in-a-slot,
## border = selected / upgrade-available / normal. Slot buttons: occupied vs
## empty border, move-source highlight.
const CHIP_EQUIPPED := Color(0.5, 0.85, 0.55, 0.95)
const CHIP_NONE := Color(1.0, 1.0, 1.0, 0.08)
const ROW_ICON_LEFT := 16.0
const SLOT_ICON_LEFT := 6.0
const ICON_GAP := 4.0

## Buttons are not containers, so the icon is pinned inside the button's
## left edge (vertically centered) and the caller pads the text past it.
func _pin_icon(b: Button, left: float) -> SpellIcon:
	var icon := SpellIcon.new(UiStyle.ICON_SIZE, true)
	var half := UiStyle.ICON_SIZE * 0.5
	icon.anchor_top = 0.5
	icon.anchor_bottom = 0.5
	icon.offset_left = left
	icon.offset_right = left + UiStyle.ICON_SIZE
	icon.offset_top = -half
	icon.offset_bottom = half
	b.add_child(icon)
	return icon

## #38: compact ASCII tier suffix on upgrade-channel buttons only (lead UX
## call: [S]/[M]/[G] for Specialization/Mastery/Signature, Base shows
## nothing). Reads the path's own tier when the provider exposes one;
## providers without a tier field degrade to no suffix. Display-only.
func _tier_suffix(path) -> String:
	var tier: Variant = path.get("tier") if path is Resource else null
	match int(tier) if tier != null else 0:
		1:
			return " [S]"
		2:
			return " [M]"
		3:
			return " [G]"
	return ""

## #255: rank border tier for an owned spell (Base when the provider has no
## tier accessor); empty slots show none.
func _rank_tier(spell: Spell) -> int:
	if spell == null:
		return SpellRankBorder.NONE
	if _upgrader != null and _upgrader.has_method(&"get_tier"):
		return _upgrader.get_tier(spell)
	return 0

func _can_upgrade(spell: Spell) -> bool:
	return spell != null and _upgrader != null and _upgrader.has_method(&"can_upgrade") and (_upgrader.can_upgrade(spell) or _can_token_upgrade(spell))

## #315: optional token channel (duck-typed; providers without it are unchanged).
func _can_token_upgrade(spell: Spell) -> bool:
	return spell != null and _upgrader != null and _upgrader.has_method(&"can_token_upgrade") and _upgrader.can_token_upgrade(spell)

func _path_needs_token(spell: Spell, path) -> bool:
	return _upgrader != null and _upgrader.has_method(&"path_needs_token") and _upgrader.path_needs_token(spell, path)

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
	_player = player
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
	panel.add_theme_stylebox_override("panel", UiStyle.panel())
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
	var slots_header := Label.new() # #94: two-column readability, mirrors "Unlocked"
	slots_header.text = "Slots"
	slots_header.add_theme_font_size_override("font_size", 22)
	slots_box.add_child(slots_header)
	for i in 6:
		var b := Button.new()
		b.add_theme_font_size_override("font_size", 22)
		b.custom_minimum_size = Vector2(220, 0)
		var idx := i
		b.pressed.connect(func(): _on_slot_pressed(idx))
		slots_box.add_child(b)
		_slot_buttons.append(b)
		_slot_icons.append(_pin_icon(b, SLOT_ICON_LEFT))
	_upgrade_box = VBoxContainer.new()
	_upgrade_box.add_theme_constant_override("separation", 4)
	vbox.add_child(_upgrade_box)
	# #269: player stats block (Daniel, 2026-11-08: "Display player stats in
	# the tab menu"). Reads ONLY the public Player stat accessors
	# (move_speed/damage_amp/armor/cooldown_reduction + hp/max_hp); all stat
	# math stays in PlayerStats. Filled on every _refresh, i.e. every open.
	# Placed between the upgrade box and the status line so the #94
	# white-boxed child indices (title 0, cols 1, upgrades 2, status last)
	# stay intact.
	_stats_box = VBoxContainer.new()
	_stats_box.name = "StatsBox"
	_stats_box.add_theme_constant_override("separation", 2)
	vbox.add_child(_stats_box)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_status)

func _input(event: InputEvent) -> void:
	# Toggle in _input, BEFORE GUI handling: a focused panel button would
	# otherwise consume Tab as ui_focus_next and the panel could never be
	# closed from the keyboard (live bug report, Chrome).
	if InputMap.has_action(&"equip_panel") and event.is_action_pressed(&"equip_panel"):
		get_viewport().set_input_as_handled()
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

## #269: rebuild the stats block from the live Player accessors. Fractions
## render as signed percents; an empty modifier set shows the defined bases
## (0% amp/armor/CDR), which PlayerStats guarantees are grounded values.
func _refresh_stats() -> void:
	for c in _stats_box.get_children():
		c.queue_free()
	if _player == null:
		return
	var header := Label.new()
	header.text = "Stats"
	header.add_theme_font_size_override("font_size", 22)
	_stats_box.add_child(header)
	var rows: Array[String] = [
		"HP: %d / %d" % [_player.hp, _player.max_hp],
		"Damage amp: %+d%%" % roundi(_player.damage_amp() * 100.0),
		"Armor: %+d%%" % roundi(_player.armor() * 100.0),
		"Move speed: %d" % roundi(_player.move_speed()),
		"Cooldown reduction: %+d%%" % roundi(_player.cooldown_reduction() * 100.0),
	]
	for r in rows:
		var l := Label.new()
		l.text = r
		_stats_box.add_child(l)

func _refresh() -> void:
	if _caster == null:
		return
	_refresh_stats()
	for c in _unlocked_box.get_children():
		c.queue_free()
	var header := Label.new()
	header.text = "Unlocked"
	header.add_theme_font_size_override("font_size", 22)
	_unlocked_box.add_child(header)
	var slots_now: Array = _caster.get_slots()
	for s in _caster.get_unlocked():
		# #94: Button stays a DIRECT child of _unlocked_box (test_e_mount
		# white-boxes that structure for keyboard focus); the state chip is a
		# child ColorRect pinned to the button's left inner edge.
		var b := Button.new()
		b.add_theme_font_size_override("font_size", 22)
		b.custom_minimum_size = Vector2(200, 0)
		b.toggle_mode = true
		b.text = (s as Spell).spell_name
		b.button_pressed = (s == _selected)
		var border := UiStyle.B_DIM
		if _can_upgrade(s):
			border = UiStyle.B_ACCENT
		if s == _selected:
			border = UiStyle.B_SELECTED
		UiStyle.style_button(b, border, 4.0, ROW_ICON_LEFT + UiStyle.ICON_SIZE + ICON_GAP, s == _selected) # left pad clears chip + icon
		var chip := ColorRect.new()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.color = CHIP_EQUIPPED if slots_now.has(s) else CHIP_NONE
		chip.anchor_bottom = 1.0
		chip.offset_left = 2.0
		chip.offset_top = 2.0
		chip.offset_right = 12.0
		chip.offset_bottom = -2.0
		b.add_child(chip)
		var spell: Spell = s
		var row_icon := _pin_icon(b, ROW_ICON_LEFT)
		row_icon.show_spell(spell)
		row_icon.set_upgrade_available(_can_upgrade(spell))
		row_icon.set_rank_tier(_rank_tier(spell))
		b.pressed.connect(func(): _on_spell_pressed(spell))
		_unlocked_box.add_child(b)
	var slots: Array = _caster.get_slots()
	for i in _slot_buttons.size():
		var occupant: Spell = slots[i] if i < slots.size() else null
		_slot_buttons[i].text = "%s: %s" % [SpellCaster.slot_key_label(i), occupant.spell_name if occupant != null else "(empty)"] # #319: show cast key, not digit
		var move_source := occupant != null and occupant == _selected
		var sborder := UiStyle.B_ASSIGNED if occupant != null else UiStyle.B_DIM
		if move_source:
			sborder = UiStyle.B_SELECTED
		UiStyle.style_button(_slot_buttons[i], sborder, 4.0, SLOT_ICON_LEFT + UiStyle.ICON_SIZE + ICON_GAP, move_source)
		_slot_icons[i].show_spell(occupant)
		_slot_icons[i].set_upgrade_available(_can_upgrade(occupant))
		_slot_icons[i].set_rank_tier(_rank_tier(occupant))
	# Upgrade section: only when a provider is wired AND a spell is selected.
	for c in _upgrade_box.get_children():
		c.queue_free()
	if _can_upgrade(_selected):
		var uheader := Label.new()
		uheader.text = "Upgrades"
		var tokens: int = _upgrader.upgrade_tokens() if _upgrader.has_method(&"upgrade_tokens") else 0
		if tokens > 0:
			uheader.text = "Upgrades (Upgrade Tokens: %d)" % tokens
		uheader.add_theme_font_size_override("font_size", 22)
		_upgrade_box.add_child(uheader)
		var token_ready := _can_token_upgrade(_selected)
		for path in _upgrader.get_upgrade_paths(_selected):
			var needs_token := _path_needs_token(_selected, path)
			# A path offered by neither route (threshold unmet, no token) is
			# not shown; with no token API this is the unchanged listing.
			if needs_token and not token_ready:
				continue
			var b := Button.new()
			b.add_theme_font_size_override("font_size", 22)
			UiStyle.style_button(b, UiStyle.B_ACCENT)
			b.text = path.display_name + _tier_suffix(path) + (" - use token" if needs_token else "")
			var pid = path.id
			if needs_token:
				b.pressed.connect(func(): _on_token_upgrade_pressed(pid))
			else:
				b.pressed.connect(func(): _on_upgrade_pressed(pid))
			_upgrade_box.add_child(b)
	_status.text = "Selected: %s" % (_selected.spell_name if _selected != null else "none")

func _on_upgrade_pressed(path_id) -> void:
	if _upgrader == null or _selected == null:
		return
	var sel := _selected
	if not _upgrader.apply_upgrade(sel, path_id):
		push_warning("EquipPanel: apply_upgrade refused; refreshing.")
	elif _caster != null and not _caster.get_unlocked().has(sel):
		# Successful replace consumed the selected spell; drop the stale
		# selection so no later slot click can act on a removed resource.
		_selected = null
	_refresh()

## #315: same flow as _on_upgrade_pressed, spending one boss upgrade token.
func _on_token_upgrade_pressed(path_id) -> void:
	if _upgrader == null or _selected == null or not _upgrader.has_method(&"apply_upgrade_with_token"):
		return
	var sel := _selected
	if not _upgrader.apply_upgrade_with_token(sel, path_id):
		push_warning("EquipPanel: token upgrade refused; refreshing.")
	elif _caster != null and not _caster.get_unlocked().has(sel):
		_selected = null
	_refresh()

func _on_spell_pressed(spell: Spell) -> void:
	# Refuse selections the caster no longer holds (e.g. a base spell consumed
	# by an upgrade): acting on a removed resource must never reach a slot.
	if _caster != null and not _caster.get_unlocked().has(spell):
		_selected = null
		_refresh()
		return
	_selected = spell
	_refresh()

func _on_slot_pressed(index: int) -> void:
	if _selected == null or _caster == null:
		return
	if not _caster.get_unlocked().has(_selected):
		# Stale/removed selection: refuse BEFORE any clear so an occupied
		# target slot is never erased by an assign that cannot succeed.
		_selected = null
		_refresh()
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
