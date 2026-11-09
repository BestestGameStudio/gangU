extends CanvasLayer
class_name EquipPanel
## #375 Tab menu (Daniel, 2026-11-09): "spell menu should only show your
## slots and allow you to rearrange the 6 spells ... You can still upgrade
## currently equipped spells from the tab menu." The panel shows ONLY the
## six slots (plus the #376 stat grid); the old Unlocked column is gone -
## equipping from the unlock inventory lives at the hub spell directory
## (#375 directory slice, #393).
##
## Interaction: click an occupied slot to SELECT its spell - the stat grid
## swaps to that spell's stats and its upgrade buttons appear. Click a
## second slot to REARRANGE: the two occupants swap, or the spell moves
## into an empty slot. Clicking the same slot again deselects.
##
## Rearrange is composed out of the pinned strict slot primitives
## (REFUSAL semantics): the selection is validated BEFORE any clear_slot(),
## then the panel clears and re-assigns; a refusal rolls the layout back
## toward its prior state (best effort) and refreshes from caster truth.
## Move-not-copy and one-spell-one-slot stay the caster's own refusals,
## never hidden panel behavior.
##
## SETTLED (Daniel's user, 11:05:49 EST): Tab toggles the panel; NO pause -
## combat stays live ("players should find a safe space"); this panel is
## ALSO the manual upgrade UI. Panel owns its own input (equip_panel/Tab),
## kept clear of the caster's spell_slot_1..6 bindings.
##
## STILL BOUNDED:
##   - Mounted in production by main.gd (ONE persistent child); harness
##     mounts (test_e_mount et al.) keep working the same way.
##   - Style is provisional (pending the open human style choice).
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

var _slots_box: VBoxContainer
var _stats_box: StatGrid
var _player: Player = null
var _slot_buttons: Array[Button] = []
var _slot_icons: Array[SpellIcon] = []
var _status: Label

## Slot button state channels: occupied vs empty border, and a bright
## selected / move-source highlight on the slot whose spell is selected.
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
	icon.offset_bottom = -half
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
	# #376: keep the stat grid live while open (HP, buffs, hammer crit/combo).
	_player.stats.changed.connect(_on_live_stat_change)
	_player.health_changed.connect(func(_hp, _max): _on_live_stat_change())
	if _caster.hammer_state != null:
		_caster.hammer_state.crit_changed.connect(_on_live_stat_change)
		_caster.hammer_state.combo_changed.connect(_on_live_stat_change)
	_hook_relics()

## Relics hooked to a spell's tags change its crit/amp totals, so a relic
## gained while the menu is open refreshes the grid too. OwnedRelics is
## mounted on Main after this panel, so this is retried in show_panel.
func _hook_relics() -> void:
	var relics := get_tree().get_first_node_in_group("owned_relics") as OwnedRelics
	if relics != null and not relics.changed.is_connected(_on_live_stat_change):
		relics.changed.connect(_on_live_stat_change)

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
	title.text = "Spells"
	title.add_theme_font_size_override("font_size", 26)
	vbox.add_child(title)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	vbox.add_child(cols)
	# #375: the ONLY spell column is the six slots. Buttons stay DIRECT
	# children of _slots_box (harnesses white-box that structure for
	# keyboard focus).
	_slots_box = VBoxContainer.new()
	_slots_box.add_theme_constant_override("separation", 4)
	cols.add_child(_slots_box)
	var slots_header := Label.new()
	slots_header.text = "Slots"
	slots_header.add_theme_font_size_override("font_size", 22)
	_slots_box.add_child(slots_header)
	for i in 6:
		var b := Button.new()
		b.add_theme_font_size_override("font_size", 22)
		b.custom_minimum_size = Vector2(220, 0)
		var idx := i
		b.pressed.connect(func(): _on_slot_pressed(idx))
		_slots_box.add_child(b)
		_slot_buttons.append(b)
		_slot_icons.append(_pin_icon(b, SLOT_ICON_LEFT))
	# #269 stats block, restyled by #376 (Daniel, 2026-11-09): a TFT-style
	# grid of icon + value cells (details on hover) on the RIGHT side of the
	# Tab menu, as the second column after the slots. Shows the player's
	# stats; while a slot's spell is selected it shows that spell's stats
	# instead (StatSheet builds both, read-only).
	var divider := VSeparator.new()
	cols.add_child(divider)
	_stats_box = StatGrid.new()
	cols.add_child(_stats_box)
	_upgrade_box = VBoxContainer.new()
	_upgrade_box.add_theme_constant_override("separation", 4)
	vbox.add_child(_upgrade_box)
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
	_hook_relics()
	_refresh()
	visible = true
	add_to_group("modal_ui") # caster cast-guard hook (coordinated with B)

func hide_panel() -> void:
	visible = false
	remove_from_group("modal_ui")

## #269/#376: fill the right-side stat grid. No selection = player stats;
## a selected spell = that spell's stats (Daniel: "Clicking a spell will
## replace player stats with the spell stats and details there"). Values
## come from the live accessors via StatSheet; no stat math lives here.
func _refresh_stats() -> void:
	if _player == null:
		return
	_stats_box.set_description(SpellDescription.for_spell(_selected))
	if _selected != null:
		_stats_box.set_entries(_selected.spell_name, StatSheet.spell_entries(_selected, _player, _caster))
	else:
		_stats_box.set_entries("Stats", StatSheet.player_entries(_player))

## Live updates while the panel is open (combat keeps running under Tab).
func _on_live_stat_change(_a = null) -> void:
	if visible:
		_refresh_stats()

func _refresh() -> void:
	if _caster == null:
		return
	_refresh_stats()
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
		var scroll := ScrollContainer.new()
		scroll.name = "UpgradeScroll"
		scroll.custom_minimum_size = Vector2(472, 210)
		_upgrade_box.add_child(scroll)
		var cards := HBoxContainer.new()
		cards.name = "UpgradeCards"
		cards.add_theme_constant_override("separation", 12)
		scroll.add_child(cards)
		var token_ready := _can_token_upgrade(_selected)
		for path in _upgrader.get_upgrade_paths(_selected):
			var needs_token := _path_needs_token(_selected, path)
			# A path offered by neither route (threshold unmet, no token) is
			# not shown; with no token API this is the unchanged listing.
			if needs_token and not token_ready:
				continue
			var b := UpgradeCard.new()
			var result: Spell = path.get("result_spell")
			var description := SpellDescription.for_spell(result)
			if result != null and result.projectile_count > 0:
				description += "\nRange: %s px. Speed: %s px/s." % [result.range, result.projectile_speed]
			if description.is_empty():
				description = "Upgrade content is not available yet."
			b.setup(path.display_name + _tier_suffix(path), description, needs_token)
			var pid = path.id
			if needs_token:
				b.pressed.connect(func(): _on_token_upgrade_pressed(pid))
			else:
				b.pressed.connect(func(): _on_upgrade_pressed(pid))
			cards.add_child(b)
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

## #375 Tab interaction: one click selects a slot's spell (stats + upgrades),
## a second click on another slot rearranges (swap, or move into an empty
## slot), a second click on the SAME slot deselects. Composed from the
## strict primitives; the caster is never asked for a hidden move.
func _on_slot_pressed(index: int) -> void:
	if _caster == null:
		return
	var slots: Array = _caster.get_slots()
	if index < 0 or index >= slots.size():
		return
	if _selected == null:
		# Nothing held: an occupied slot selects its spell; an empty slot
		# has nothing to select.
		var occupant: Spell = slots[index]
		if occupant != null:
			_selected = occupant
			_refresh()
		return
	# A selection is held: this click is the rearrange target (or a
	# deselect). Validate BEFORE any clear so a failed rearrange never
	# erases an occupied slot.
	if not _caster.get_unlocked().has(_selected):
		# Stale/removed selection (e.g. a base spell consumed by an
		# upgrade): refuse before any mutation.
		_selected = null
		_refresh()
		return
	var source := slots.find(_selected)
	if source == -1:
		# The selected spell is no longer slotted; nothing to rearrange.
		_selected = null
		_refresh()
		return
	if index == source:
		_selected = null # click the same slot again: put it back / deselect
		_refresh()
		return
	var target: Spell = slots[index]
	_caster.clear_slot(source)
	if target != null:
		_caster.clear_slot(index)
	var ok := _caster.assign_slot(index, _selected)
	if ok and target != null:
		ok = _caster.assign_slot(source, target)
	if not ok:
		# Roll back toward the original layout (best effort, primitives
		# only, re-reading caster truth after each step), then refresh
		# from caster truth either way.
		push_warning("EquipPanel: rearrange refused; restoring prior layout.")
		var now: Array = _caster.get_slots()
		if not now.has(_selected) and now[source] == null:
			_caster.assign_slot(source, _selected)
			now = _caster.get_slots()
		if target != null and not now.has(target):
			if now[index] == null:
				_caster.assign_slot(index, target)
			elif now[source] == null:
				_caster.assign_slot(source, target)
	_selected = null
	_refresh()
