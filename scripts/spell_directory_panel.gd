class_name SpellDirectoryPanel
extends CanvasLayer
## (#218) Spell directory panel. Hidden by default; the hub
## directory location opens it on walk-up and closes it on walk-away (the
## ShopPanel idiom). Lists EVERY spell in the caster's current-run unlock
## set (SpellCaster.get_unlocked(), #60) as icon + name rows, refreshed
## live through the spell_unlocked signal. No buy and no unlock grants -
## it only displays what the player already unlocked this run.
##
## (#375, Daniel 2026-11-09: "You can swap spells at the spell directory")
## Bounded swap lane: clicking a row selects that unlocked spell and shows
## the six slot targets (cast-key labels + occupants); clicking a slot
## equips the selection there - an occupied target SWAPS (the previous
## occupant stays unlocked, now unequipped), an empty target equips. The
## move is composed from the caster's strict clear_slot/assign_slot
## primitives, so one-spell-one-slot and refusal semantics are preserved;
## nothing here grants, removes or replaces spells. Rearranging already
## EQUIPPED spells stays in the Tab menu (#375): a slotted selection
## clicking a slot is refused with a hint. There is deliberately no
## unequip action (unsettled). Rows stay Button-free (gui_input) and the
## slot bar lives OUTSIDE the Rows box, so #218's row-structure contract
## is untouched. Upgrade-path listing stays display-only.
##
## (#318) Each row also shows the spell's current tier and its full upgrade
## tree from SpellProgress (direct paths with live cast progress, deeper
## tiers indented below). Still read-only: nothing here applies upgrades.
##
## UI is code-built; the look comes from UiStyle. While visible the panel
## joins "modal_ui" so the caster skips casting on panel clicks (the
## EquipPanel/ShopPanel idiom). Found via the "spell_directory_panel"
## group.

const ROW_PAD := 6.0
## (#318) Upgrade-path listing under each spell row.
const PATH_FONT_SIZE := 12
const PATH_INDENT := 14.0
const MAX_PATH_DEPTH := 4
## Display names indexed by SpellUpgrade.tier / SpellProgress.get_tier.
const TIER_NAMES: Array[String] = ["Base", "Specialization", "Mastery", "Signature"]

var _caster: SpellCaster
## (#375) Currently selected row spell; null = browsing (slot bar hidden).
var _selected: Spell = null
## (#318) Upgrade-path provider, discovered via the "spell_progress" group
## at render time (main.gd mounts it after this panel). Optional: a missing
## provider just shows "No further upgrades".
var _progress: SpellProgress
var _count_label: Label
var _rows: VBoxContainer
## (#375) Six slot-target buttons, visible only while a spell is selected.
var _slot_bar: HBoxContainer
var _status: Label

func _ready() -> void:
	add_to_group("spell_directory_panel")
	layer = 3
	_build_skeleton()
	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		_bind_caster(player.get_node_or_null("SpellCaster") as SpellCaster)
	visible = false

func _bind_caster(for_caster: SpellCaster) -> void:
	if for_caster == _caster:
		return
	if is_instance_valid(_caster):
		_caster.spell_unlocked.disconnect(_on_spell_unlocked)
		_caster.spell_replaced.disconnect(_on_spell_replaced)
		_caster.slot_assigned.disconnect(_on_slot_changed)
		_caster.slot_cleared.disconnect(_on_slot_cleared)
	_caster = for_caster
	if is_instance_valid(_caster):
		_caster.spell_unlocked.connect(_on_spell_unlocked)
		_caster.spell_replaced.connect(_on_spell_replaced)
		_caster.slot_assigned.connect(_on_slot_changed)
		_caster.slot_cleared.connect(_on_slot_cleared)

func open(for_caster: SpellCaster = null) -> void:
	if for_caster != null:
		_bind_caster(for_caster)
	_render()
	visible = true
	add_to_group("modal_ui") # caster cast-guard hook (EquipPanel idiom)

func close() -> void:
	visible = false
	_selected = null
	if _status != null:
		_status.text = ""
	remove_from_group("modal_ui")

func _build_skeleton() -> void:
	var backdrop := Panel.new()
	backdrop.name = "Backdrop"
	backdrop.add_theme_stylebox_override("panel", UiStyle.panel())
	backdrop.anchor_left = 0.5
	backdrop.anchor_top = 0.5
	backdrop.anchor_right = 0.5
	backdrop.anchor_bottom = 0.5
	backdrop.offset_left = -260.0
	backdrop.offset_top = -230.0
	backdrop.offset_right = 260.0
	backdrop.offset_bottom = 230.0
	add_child(backdrop)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	backdrop.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	var title := Label.new()
	title.text = "SPELL DIRECTORY"
	title.add_theme_font_size_override("font_size", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	_count_label = Label.new()
	_count_label.name = "CountLabel"
	_count_label.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_count_label)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.add_theme_constant_override("separation", 6)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	_slot_bar = HBoxContainer.new()
	_slot_bar.name = "SlotBar"
	_slot_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_slot_bar.add_theme_constant_override("separation", 6)
	_slot_bar.visible = false
	vbox.add_child(_slot_bar)
	_status = Label.new()
	_status.name = "StatusLabel"
	_status.text = ""
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_status)
	var hint := Label.new()
	hint.text = "Walk away to close"
	hint.add_theme_color_override("font_color", UiStyle.TEXT_DIM * Color(1, 1, 1, 0.6))
	hint.add_theme_font_size_override("font_size", 11)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

## One icon + name row per unlocked spell, in unlock order. Empty runs get
## a dim placeholder line instead of a blank panel.
func _render() -> void:
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	if not is_instance_valid(_progress):
		_progress = get_tree().get_first_node_in_group("spell_progress") as SpellProgress
		# spell_replaced fires inside replace_spell, BEFORE SpellProgress
		# records the new tier; upgrades_changed fires after, so re-render
		# then too or the tier label reads stale.
		if _progress != null and not _progress.upgrades_changed.is_connected(_on_upgrades_changed):
			_progress.upgrades_changed.connect(_on_upgrades_changed)
	var unlocked: Array[Spell] = []
	if _caster != null:
		unlocked = _caster.get_unlocked()
	_count_label.text = "%d spell(s) unlocked this run" % unlocked.size()
	if unlocked.is_empty():
		var empty := Label.new()
		empty.name = "EmptyLabel"
		empty.text = "No spells unlocked yet"
		empty.add_theme_color_override("font_color", UiStyle.TEXT_DIM * Color(1, 1, 1, 0.7))
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_rows.add_child(empty)
		return
	for spell in unlocked:
		_rows.add_child(_make_row(spell))
	_refresh_slot_bar()

func _make_row(spell: Spell) -> Control:
	var row := PanelContainer.new()
	row.name = "Row"
	row.add_theme_stylebox_override("panel", UiStyle.row(UiStyle.B_SELECTED if spell == _selected else UiStyle.B_DIM, ROW_PAD))
	# (#375) Row click selects for swapping. gui_input, NOT a Button: the
	# #218 harness pins a Button-free Rows box, and the slot bar carries the
	# only real buttons. Children are click-through so the row gets the click.
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.gui_input.connect(_on_row_gui_input.bind(spell))
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	row.add_child(vbox)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox)
	var icon := SpellIcon.new()
	icon.show_spell(spell)
	hbox.add_child(icon)
	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.text = spell.spell_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_label)
	# (#375) Equipped marker: the cast-key label of the slot holding this
	# spell, so the listing shows what is currently equipped where.
	if _caster != null:
		var slot_idx := _caster.get_slots().find(spell)
		if slot_idx != -1:
			var slot_label := Label.new()
			slot_label.name = "SlotLabel"
			slot_label.text = SpellCaster.slot_key_label(slot_idx)
			slot_label.add_theme_color_override("font_color", UiStyle.B_ACCENT)
			slot_label.add_theme_font_size_override("font_size", PATH_FONT_SIZE)
			hbox.add_child(slot_label)
	var tier_label := Label.new()
	tier_label.name = "TierLabel"
	var tier: int = _progress.get_tier(spell) if _progress != null else 0
	tier_label.text = TIER_NAMES[clampi(tier, 0, TIER_NAMES.size() - 1)]
	tier_label.add_theme_color_override("font_color", UiStyle.RANK_COLORS[clampi(tier, 0, UiStyle.RANK_COLORS.size() - 1)])
	tier_label.add_theme_font_size_override("font_size", PATH_FONT_SIZE)
	hbox.add_child(tier_label)
	var paths := VBoxContainer.new()
	paths.name = "Paths"
	paths.add_theme_constant_override("separation", 2)
	vbox.add_child(paths)
	if _progress == null or _progress.get_upgrade_paths(spell).is_empty():
		var none := Label.new()
		none.name = "NoPathsLabel"
		none.text = "No further upgrades"
		none.add_theme_color_override("font_color", UiStyle.TEXT_DIM * Color(1, 1, 1, 0.7))
		none.add_theme_font_size_override("font_size", PATH_FONT_SIZE)
		paths.add_child(none)
	else:
		_add_paths(paths, spell, 0, {spell: true}, true)
	for child in row.find_children("*", "Control", true, false):
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return row

## (#375) Left-click on a row toggles its selection for swapping.
func _on_row_gui_input(event: InputEvent, spell: Spell) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		select_spell(spell)

## (#375) Select an unlocked spell (or click it again to deselect). A spell
## the caster no longer holds cannot be selected (stale after an upgrade).
func select_spell(spell: Spell) -> void:
	if _caster == null or not _caster.get_unlocked().has(spell):
		_selected = null
	else:
		_selected = null if _selected == spell else spell
	if _status != null:
		_status.text = ""
	_render()

## (#375) Slot target clicked while a spell is selected. The move is the
## panel's composition of strict caster primitives (EquipPanel idiom):
## validate everything BEFORE any clear so a refused assign never erases an
## occupied target. Occupied target = swap (occupant stays unlocked);
## empty target = equip. An already-slotted selection is refused:
## rearranging equipped spells is the Tab menu's job (#375).
func _on_slot_chosen(index: int) -> void:
	if _caster == null or _selected == null:
		return
	if not _caster.get_unlocked().has(_selected):
		_selected = null
		_render()
		return
	var slots := _caster.get_slots()
	var current := slots.find(_selected)
	if current == index:
		# Tapping the slot the spell already holds: no-op, drop selection.
		_selected = null
		_status.text = ""
		_render()
		return
	if current != -1:
		_status.text = "%s is equipped to %s - rearrange slots in the Tab menu" % [_selected.spell_name, SpellCaster.slot_key_label(current)]
		_render()
		return
	var occupant: Spell = slots[index] if index < slots.size() else null
	if occupant != null:
		_caster.clear_slot(index)
	if not _caster.assign_slot(index, _selected):
		if occupant != null:
			_caster.assign_slot(index, occupant) # rollback: never lose the occupant
		push_warning("SpellDirectoryPanel: assign_slot refused; refreshed from caster state.")
		_status.text = "Swap refused"
	else:
		_status.text = "%s -> %s%s" % [_selected.spell_name, SpellCaster.slot_key_label(index), " (swapped out %s)" % occupant.spell_name if occupant != null else ""]
		_selected = null
	_render()

## (#375) Rebuild the six slot targets from live caster state; visible only
## while a selection is active so the default directory stays a plain list.
func _refresh_slot_bar() -> void:
	for c in _slot_bar.get_children():
		_slot_bar.remove_child(c)
		c.queue_free()
	_slot_bar.visible = _selected != null
	if _selected == null or _caster == null:
		return
	var slots := _caster.get_slots()
	for i in SpellCaster.SLOT_COUNT:
		var occupant: Spell = slots[i] if i < slots.size() else null
		var b := Button.new()
		b.name = "SlotTarget%d" % i
		b.text = "%s\n%s" % [SpellCaster.slot_key_label(i), occupant.spell_name if occupant != null else "(empty)"]
		b.add_theme_font_size_override("font_size", 11)
		b.custom_minimum_size = Vector2(76, 40)
		UiStyle.style_button(b, UiStyle.B_ASSIGNED if occupant != null else UiStyle.B_DIM)
		var idx := i
		b.pressed.connect(func(): _on_slot_chosen(idx))
		_slot_bar.add_child(b)

## (#318) Recursively lists the upgrade tree reachable from `source`: one
## line per SpellUpgrade, indented by depth and tinted with the target tier's
## rank colour. Only the owned spell's direct paths show live cast progress
## (cast counts exist only for held spells); deeper lines show the threshold.
## `seen` guards against cyclic upgrade data.
func _add_paths(box: VBoxContainer, source: Spell, depth: int, seen: Dictionary, owned: bool) -> void:
	if depth >= MAX_PATH_DEPTH:
		return
	for u in _progress.get_upgrade_paths(source):
		var line := HBoxContainer.new()
		line.name = "PathLine"
		line.set_meta("upgrade_id", u.id)
		line.set_meta("depth", depth)
		line.add_theme_constant_override("separation", 6)
		var indent := Control.new()
		indent.custom_minimum_size = Vector2(PATH_INDENT * (depth + 1), 0)
		line.add_child(indent)
		var tier := clampi(u.tier, 0, UiStyle.RANK_COLORS.size() - 1)
		var label := Label.new()
		label.name = "PathLabel"
		label.text = "%s %s  [%s]" % [">" if depth == 0 else ">>", u.display_name, TIER_NAMES[clampi(u.tier, 0, TIER_NAMES.size() - 1)]]
		label.add_theme_color_override("font_color", UiStyle.RANK_COLORS[tier])
		label.add_theme_font_size_override("font_size", PATH_FONT_SIZE)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(label)
		var req := Label.new()
		req.name = "RequirementLabel"
		if owned:
			var casts := mini(_progress.cast_count(source), u.xp_threshold)
			req.text = "READY" if casts >= u.xp_threshold else "%d/%d casts" % [casts, u.xp_threshold]
			if casts >= u.xp_threshold:
				req.add_theme_color_override("font_color", UiStyle.B_ACCENT)
			else:
				req.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
		else:
			req.text = "%d casts" % u.xp_threshold
			req.add_theme_color_override("font_color", UiStyle.TEXT_DIM * Color(1, 1, 1, 0.75))
		req.add_theme_font_size_override("font_size", PATH_FONT_SIZE)
		line.add_child(req)
		box.add_child(line)
		if u.result_spell != null and not seen.has(u.result_spell):
			var next_seen := seen.duplicate()
			next_seen[u.result_spell] = true
			_add_paths(box, u.result_spell, depth + 1, next_seen, false)

func _on_spell_unlocked(_spell: Spell) -> void:
	if visible:
		_render()

func _on_spell_replaced(old_spell: Spell, _new_spell: Spell) -> void:
	# An upgrade consumed the selected spell: never act on a removed resource.
	if _selected == old_spell:
		_selected = null
	if visible:
		_render()

func _on_slot_changed(_index: int, _spell: Spell) -> void:
	if visible:
		_render()

func _on_slot_cleared(_index: int) -> void:
	if visible:
		_render()

func _on_upgrades_changed(_spell: Spell) -> void:
	if visible:
		_render()
