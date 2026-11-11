extends ModalPanel
class_name EquipPanel
## #375 Tab menu (Daniel, 2026-11-09): "spell menu should only show your
## slots and allow you to rearrange the 6 spells ... You can still upgrade
## currently equipped spells from the tab menu." The panel shows ONLY the
## six slots (plus the #376 stat grid); the old Unlocked column is gone -
## equipping from the unlock inventory lives at the hub spell directory
## (#375 directory slice, #393).
##
## Interaction (#441, Daniel 2026-11-09): click an occupied slot to SELECT
## its spell - the stat grid swaps to that spell's stats and its upgrade
## buttons appear; clicking it again deselects. REARRANGE is hold-and-drag
## ONLY: press and hold a slot, drag onto another slot to swap the two
## spells, or onto an empty slot to move the spell there. Click-to-swap is
## gone ("Hold and drag only, works for empty space").
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
## Player.find fallback applies. Production mount is a separate window.
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
var _upgrade_scroll: ScrollContainer
var _plate: PanelContainer
var _detail_box: VBoxContainer

## #441 hold-and-drag state: where the left press started, the active drag
## source slot (-1 = none), the floating ghost icon, and a one-shot guard
## so a drag that ends on its own source slot doesn't also fire a click.
var _press_slot := -1
var _press_pos := Vector2.ZERO
var _drag_from := -1
var _drag_ghost: SpellIcon = null
var _suppress_next_click := false
const DRAG_THRESHOLD := 10.0

## #416 (Daniel, 2026-11-09): the menu must not change size when switching
## between player stats and spell stats, and the upgrades sit UNDER the
## spell stats in a column wide enough for three upgrade cards. The detail
## column has a fixed width and the plate a fixed height (capped by the
## viewport); the upgrade scroll fills whatever height is left, so content
## changes never resize the panel.
const UPGRADE_CARD_GAP := 12
# Three #441-slim cards + gaps + scrollbar, but never narrower than the
# player-stats grid's minimum width (589 measured): the #416 no-resize rule
# covers WIDTH too, so the column floor keeps the plate one fixed size.
const DETAIL_WIDTH := 600.0
## #441 (Daniel, 2026-11-09): the plate hugs its content instead of the old
## 620px fixed height ("a lot of empty vertical space below the spell
## slots"). Measured composition on the pinned harness: title 36 + sep 10 +
## columns 376 (player stats 115 + sep + upgrades header ~35 + one full
## upgrade card 216 at the #441 card width; the slots column needs 289) +
## plate margins 20. Still FIXED so the #416 no-resize rule holds.
## #427 rebase: the relics section (separator + header + one names row, 83)
## sits below the columns, so the fixed height grows 442 -> 525 to keep the
## tallest state (upgrade cards + relics) inside it without resizing.
const PANEL_HEIGHT := 525.0
const SCREEN_MARGIN := 16.0
var _relics_box: VBoxContainer
var _relics_list: HFlowContainer

func _process(_delta: float) -> void:
	if visible:
		_fit_plate()

func _fit_plate() -> void:
	if not is_instance_valid(_plate) or not is_inside_tree():
		return
	var height := minf(PANEL_HEIGHT, get_viewport().get_visible_rect().size.y - SCREEN_MARGIN)
	if not is_equal_approx(_plate.custom_minimum_size.y, height):
		_plate.custom_minimum_size.y = height

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
func _tier_suffix(path: Variant) -> String:
	match _path_tier(path):
		1:
			return " [S]"
		2:
			return " [M]"
		3:
			return " [G]"
	return ""

## Tier the path upgrades INTO (0 Base .. 3 Signature); 0 when the provider
## exposes no tier. Shared by the [S]/[M]/[G] suffix and the #451 card border.
func _path_tier(path: Variant) -> int:
	var tier: Variant = (path as Resource).get(&"tier") if path is Resource else null
	return clampi(int(tier), 0, UiStyle.RANK_COLORS.size() - 1) if tier != null else 0

## A provider path is a SpellUpgrade or a {id, display_name} Dictionary.
func _path_field(path: Variant, key: StringName) -> Variant:
	if path is Dictionary:
		return (path as Dictionary).get(key)
	if path is Object:
		return (path as Object).get(key)
	return null

## #255: rank border tier for an owned spell (Base when the provider has no
## tier accessor); empty slots show none.
func _rank_tier(spell: Spell) -> int:
	if spell == null:
		return SpellRankBorder.NONE
	if _upgrader != null and _upgrader.has_method(&"get_tier"):
		return _upgrader.call(&"get_tier", spell)
	return 0

func _can_upgrade(spell: Spell) -> bool:
	return spell != null and _upgrader != null and _upgrader.has_method(&"can_upgrade") and (_upgrader.call(&"can_upgrade", spell) or _can_token_upgrade(spell))

## #315: optional token channel (duck-typed; providers without it are unchanged).
func _can_token_upgrade(spell: Spell) -> bool:
	return spell != null and _upgrader != null and _upgrader.has_method(&"can_token_upgrade") and _upgrader.call(&"can_token_upgrade", spell)

func _path_needs_token(spell: Spell, path: Variant) -> bool:
	return _upgrader != null and _upgrader.has_method(&"path_needs_token") and _upgrader.call(&"path_needs_token", spell, path)

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
		player = Player.find(get_tree())
	if player == null:
		push_warning("EquipPanel: no player found; panel inert.")
		return
	_player = player
	if upgrader_path != NodePath(""):
		_upgrader = get_node_or_null(upgrader_path)
		if _upgrader != null and _upgrader.has_signal(&"upgrades_changed"):
			_upgrader.connect(&"upgrades_changed", func(_s: Variant) -> void: _refresh())
	_caster = player.get_node_or_null("SpellCaster") as SpellCaster
	if _caster == null:
		push_warning("EquipPanel: caster slot API not present; panel inert.")
		_caster = null
		return
	if _caster.has_signal(&"slot_assigned"):
		_caster.slot_assigned.connect(func(_i: int, _s: Spell) -> void: _refresh())
	if _caster.has_signal(&"slot_cleared"):
		_caster.slot_cleared.connect(func(_i: int) -> void: _refresh())
	# #376: keep the stat grid live while open (HP, buffs, hammer crit/combo).
	_player.stats.changed.connect(_on_live_stat_change)
	_player.health_changed.connect(func(_hp: int, _max: int) -> void: _on_live_stat_change())
	if _caster.hammer_state != null:
		_caster.hammer_state.crit_changed.connect(_on_live_stat_change)
		_caster.hammer_state.combo_changed.connect(_on_live_stat_change)
	_hook_relics()

## Relics hooked to a spell's tags change its crit/amp totals, so a relic
## gained while the menu is open refreshes the grid too. OwnedRelics is
## mounted on Main after this panel, so this is retried in show_panel.
func _hook_relics() -> void:
	var relics := Run.relics()
	if relics != null and not relics.changed.is_connected(_on_live_stat_change):
		relics.changed.connect(_on_live_stat_change)
	if relics != null and not relics.changed.is_connected(_refresh_relics):
		relics.changed.connect(_refresh_relics) # #427 section stays live too

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
	_plate = panel
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	var title := Label.new()
	title.text = "Spells"
	title.add_theme_font_size_override("font_size", 26)
	vbox.add_child(title)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
		b.pressed.connect(func() -> void: _on_slot_pressed(idx))
		b.gui_input.connect(func(ev: InputEvent) -> void: _on_slot_gui_input(ev, idx))
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
	# #416: one fixed-width detail column holds the stats and, under them,
	# the selected spell's upgrades.
	_detail_box = VBoxContainer.new()
	_detail_box.name = "DetailColumn"
	_detail_box.custom_minimum_size = Vector2(DETAIL_WIDTH, 0)
	_detail_box.add_theme_constant_override("separation", 10)
	cols.add_child(_detail_box)
	_stats_box = StatGrid.new()
	_detail_box.add_child(_stats_box)
	_upgrade_box = VBoxContainer.new()
	_upgrade_box.name = "UpgradeBox"
	_upgrade_box.add_theme_constant_override("separation", 4)
	_upgrade_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_box.add_child(_upgrade_box)
	# #417: no "Selected: <spell>" status line; the highlighted slot and the
	# stat grid title already show the selection.
	_build_relics_section(vbox)

## #427 (Daniel, 2026-11-09): "on the spell tab add a section for relics on
## the bottom". Read-only list of the run's owned relics (OwnedRelics.all(),
## acquisition order); an empty run shows a placeholder line.
## #449: icon only (shared placeholder), name + description on hover.
## Fields, interaction, ordering and overflow beyond this are NOT settled
## design - names wrap in a flow container rather than growing the panel.
func _build_relics_section(parent: VBoxContainer) -> void:
	parent.add_child(HSeparator.new())
	_relics_box = VBoxContainer.new()
	_relics_box.name = "RelicsBox"
	_relics_box.add_theme_constant_override("separation", 4)
	parent.add_child(_relics_box)
	var header := Label.new()
	header.name = "RelicsHeader"
	header.text = "Relics"
	header.add_theme_font_size_override("font_size", 22)
	_relics_box.add_child(header)
	_relics_list = HFlowContainer.new()
	_relics_list.name = "RelicsList"
	_relics_list.add_theme_constant_override("h_separation", 16)
	_relics_list.add_theme_constant_override("v_separation", 4)
	_relics_box.add_child(_relics_list)

func _refresh_relics() -> void:
	if not is_instance_valid(_relics_list):
		return
	for c in _relics_list.get_children():
		_relics_list.remove_child(c)
		c.queue_free()
	var owned := Run.relics()
	var relics: Array[Relic] = owned.all() if owned != null else ([] as Array[Relic])
	if relics.is_empty():
		var empty := Label.new()
		empty.name = "RelicsEmpty"
		empty.text = "No relics yet"
		empty.add_theme_font_size_override("font_size", 18)
		empty.modulate = Color(1, 1, 1, 0.6)
		_relics_list.add_child(empty)
		return
	# #449 (Daniel, 2026-11-09): icon only - one shared code-drawn
	# placeholder for every relic; the name and description live in the
	# icon's hover tooltip ("Icon only name and desc on hover").
	for r in relics:
		var icon := RelicIcon.new()
		icon.show_relic(r)
		_relics_list.add_child(icon)

## Names currently shown in the relics section (harness/read-only helper).
## #449: relics render as RelicIcon - the name is the tooltip's first line.
func relic_names() -> PackedStringArray:
	var out := PackedStringArray()
	if is_instance_valid(_relics_list):
		for c in _relics_list.get_children():
			if c is RelicIcon:
				out.append((c as RelicIcon).tooltip_text.get_slice("\n", 0))
	return out

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
	_fit_plate()
	_refresh()
	_set_shown(true)

func hide_panel() -> void:
	_set_shown(false)
	_press_slot = -1
	if _drag_from != -1 or _drag_ghost != null:
		_end_drag()

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
func _on_live_stat_change(_a: Variant = null) -> void:
	if visible:
		_refresh_stats()

func _refresh() -> void:
	_refresh_relics()
	if _caster == null:
		return
	_refresh_stats()
	var slots: Array = _caster.get_slots()
	for i in _slot_buttons.size():
		var occupant: Spell = slots[i] if i < slots.size() else null
		_slot_buttons[i].text = "%s: %s" % [SpellCaster.slot_key_label(i), occupant.spell_name if occupant != null else "(empty)"] # #319: show cast key, not digit
		var move_source := occupant != null and (occupant == _selected or i == _drag_from)
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
		var tokens: int = _upgrader.call(&"upgrade_tokens") if _upgrader.has_method(&"upgrade_tokens") else 0
		if tokens > 0:
			uheader.text = "Upgrades (Upgrade Tokens: %d)" % tokens
		uheader.add_theme_font_size_override("font_size", 22)
		_upgrade_box.add_child(uheader)
		var scroll := ScrollContainer.new()
		scroll.name = "UpgradeScroll"
		_upgrade_scroll = scroll
		# Fills the height left under the stats; tall cards scroll inside it.
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_upgrade_box.add_child(scroll)
		var cards := HBoxContainer.new()
		cards.name = "UpgradeCards"
		cards.add_theme_constant_override("separation", UPGRADE_CARD_GAP)
		scroll.add_child(cards)
		var token_ready := _can_token_upgrade(_selected)
		var paths: Array = _upgrader.call(&"get_upgrade_paths", _selected)
		for path: Variant in paths:
			var needs_token := _path_needs_token(_selected, path)
			# A path offered by neither route (threshold unmet, no token) is
			# not shown; with no token API this is the unchanged listing.
			if needs_token and not token_ready:
				continue
			var b := UpgradeCard.new()
			var result := _path_field(path, &"result_spell") as Spell
			var description := SpellDescription.for_spell(result)
			if result != null and result.projectile_count > 0:
				# #441: short form so the line does not wrap on the slimmer cards (Daniel: "shorten").
				description += "\n%s px | %s px/s" % [int(result.range), int(result.projectile_speed)]
			if description.is_empty():
				description = "Upgrade content is not available yet."
			b.setup(str(_path_field(path, &"display_name")) + _tier_suffix(path), description, needs_token)
			# #451: border in the color of the tier this upgrade leads into.
			b.set_border_color(UiStyle.RANK_COLORS[_path_tier(path)])
			var pid: Variant = _path_field(path, &"id")
			if needs_token:
				b.pressed.connect(func() -> void: _on_token_upgrade_pressed(pid))
			else:
				b.pressed.connect(func() -> void: _on_upgrade_pressed(pid))
			cards.add_child(b)

func _on_upgrade_pressed(path_id: Variant) -> void:
	if _upgrader == null or _selected == null:
		return
	var sel := _selected
	if not _upgrader.call(&"apply_upgrade", sel, path_id):
		push_warning("EquipPanel: apply_upgrade refused; refreshing.")
	elif _caster != null and not _caster.get_unlocked().has(sel):
		# Successful replace consumed the selected spell; drop the stale
		# selection so no later slot click can act on a removed resource.
		_selected = null
	_refresh()

## #315: same flow as _on_upgrade_pressed, spending one boss upgrade token.
func _on_token_upgrade_pressed(path_id: Variant) -> void:
	if _upgrader == null or _selected == null or not _upgrader.has_method(&"apply_upgrade_with_token"):
		return
	var sel := _selected
	if not _upgrader.call(&"apply_upgrade_with_token", sel, path_id):
		push_warning("EquipPanel: token upgrade refused; refreshing.")
	elif _caster != null and not _caster.get_unlocked().has(sel):
		_selected = null
	_refresh()

## #441 Tab interaction: click SELECTS a slot's spell (stats + upgrades),
## clicking the selected slot again deselects, clicking an empty slot
## deselects. Rearrange is hold-and-drag only (see _on_slot_gui_input).
func _on_slot_pressed(index: int) -> void:
	if _suppress_next_click:
		# A drag that ended on its own source slot also fires pressed; the
		# rearrange already ran (or was a no-op), so swallow the click.
		_suppress_next_click = false
		return
	if _caster == null:
		return
	var slots: Array = _caster.get_slots()
	if index < 0 or index >= slots.size():
		return
	var occupant: Spell = slots[index]
	if occupant == null or occupant == _selected:
		_selected = null
	else:
		_selected = occupant
	_refresh()

## #441: press-and-hold on a slot starts a drag once the pointer moves past
## DRAG_THRESHOLD; releasing over another slot swaps the two spells, over
## an empty slot moves the spell there. A ghost icon follows the cursor so
## the dragged spell is visible the whole way (Daniel watches the demos).
func _on_slot_gui_input(event: InputEvent, index: int) -> void:
	if _caster == null:
		return
	var button := event as InputEventMouseButton
	var motion := event as InputEventMouseMotion
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_press_slot = index
			_press_pos = button.global_position
			_drag_from = -1
		else:
			if _drag_from != -1:
				var target := _slot_at(button.global_position)
				if target != -1 and target != _drag_from:
					_rearrange_slots(_drag_from, target)
				# Only a release INSIDE the source button also fires its
				# pressed signal; that trailing click must be swallowed.
				_suppress_next_click = target == _drag_from
				_end_drag()
			_press_slot = -1
	elif motion != null and _press_slot != -1 and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		if _drag_from == -1:
			if _press_pos.distance_to(motion.global_position) <= DRAG_THRESHOLD:
				return
			var slots: Array = _caster.get_slots()
			if _press_slot >= slots.size() or slots[_press_slot] == null:
				return # nothing to drag from an empty slot
			_drag_from = _press_slot
			_begin_drag_ghost(slots[_drag_from])
			_refresh()
		if _drag_ghost != null:
			_drag_ghost.global_position = motion.global_position - _drag_ghost.size * 0.5

func _slot_at(global_pos: Vector2) -> int:
	for i in _slot_buttons.size():
		if _slot_buttons[i].get_global_rect().has_point(global_pos):
			return i
	return -1

func _begin_drag_ghost(spell: Spell) -> void:
	_end_drag_ghost()
	_drag_ghost = SpellIcon.new(UiStyle.ICON_SIZE * 1.5, true)
	_drag_ghost.size = Vector2.ONE * UiStyle.ICON_SIZE * 1.5
	_drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_ghost.modulate.a = 0.85
	_drag_ghost.show_spell(spell)
	add_child(_drag_ghost)

func _end_drag_ghost() -> void:
	if _drag_ghost != null:
		_drag_ghost.queue_free()
		_drag_ghost = null

func _end_drag() -> void:
	_drag_from = -1
	_end_drag_ghost()
	_refresh()

## Rearrange two slots, composed from the strict clear_slot/assign_slot
## primitives: validate BEFORE any clear, roll back toward the prior layout
## on refusal, one-spell-one-slot preserved. Selection is untouched - a
## dragged spell that was selected stays selected.
func _rearrange_slots(source: int, target_index: int) -> void:
	if _caster == null:
		return
	var slots: Array = _caster.get_slots()
	if source < 0 or source >= slots.size() or target_index < 0 or target_index >= slots.size():
		return
	var moved: Spell = slots[source]
	if moved == null or not _caster.get_unlocked().has(moved):
		return
	var target: Spell = slots[target_index]
	_caster.clear_slot(source)
	if target != null:
		_caster.clear_slot(target_index)
	var ok := _caster.assign_slot(target_index, moved)
	if ok and target != null:
		ok = _caster.assign_slot(source, target)
	if not ok:
		# Roll back toward the original layout (best effort, primitives
		# only, re-reading caster truth after each step), then refresh
		# from caster truth either way.
		push_warning("EquipPanel: rearrange refused; restoring prior layout.")
		var now: Array = _caster.get_slots()
		if not now.has(moved) and now[source] == null:
			_caster.assign_slot(source, moved)
			now = _caster.get_slots()
		if target != null and not now.has(target):
			if now[target_index] == null:
				_caster.assign_slot(target_index, target)
			elif now[source] == null:
				_caster.assign_slot(source, target)
	_refresh()
