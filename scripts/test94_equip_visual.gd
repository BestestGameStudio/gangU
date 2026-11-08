extends SceneTree
## #94 equip-panel visual identity harness. Fixture: stub Player + stub
## SpellCaster (typed subclasses so the panel's `as Player` / `as SpellCaster`
## casts pass; _ready/_process overrides skip gameplay wiring) + stub upgrade
## provider (duck-typed per the panel's upgrader contract). Asserts the #94
## presentation layer: two-column structure + headers, state chips, per-state
## border channels (selected / upgrade-available / occupied / empty /
## move-source), upgrade section styling, equip flow end-to-end, and that all
## labels are preserved. Decor legs FAIL on old main (no styling).

class StubPlayer extends Player:
	func _ready() -> void:
		pass # skip gameplay wiring
	func _process(_delta: float) -> void:
		pass
	func _init() -> void:
		# player.gd @onready lookups run even with _ready overridden.
		var aim := Node2D.new()
		aim.name = "AimIndicator"
		add_child(aim)
		var bod := Polygon2D.new()
		bod.name = "Body"
		add_child(bod)

class StubCaster extends SpellCaster:
	var fake_unlocked: Array[Spell] = []
	var fake_slots: Array[Spell] = [null, null, null, null, null, null]
	var assigned: Array = []
	var cleared: Array = []
	func _ready() -> void:
		pass
	func _process(_delta: float) -> void:
		pass
	func get_unlocked() -> Array[Spell]:
		return fake_unlocked.duplicate()
	func get_slots() -> Array[Spell]:
		return fake_slots.duplicate()
	func assign_slot(index: int, spell: Spell) -> bool:
		assigned.append([index, spell])
		fake_slots[index] = spell
		slot_assigned.emit(index, spell)
		return true
	func clear_slot(index: int) -> bool:
		cleared.append(index)
		fake_slots[index] = null
		slot_cleared.emit(index)
		return true

class StubUpgrader extends Node:
	signal upgrades_changed(spell)
	var upgradeable: Array[Spell] = []
	func can_upgrade(spell: Spell) -> bool:
		return upgradeable.has(spell)
	func get_upgrade_paths(_spell: Spell) -> Array:
		return [{"id": "p1", "display_name": "Path One"}]
	func apply_upgrade(_spell: Spell, _path_id) -> bool:
		return true

var failures := 0
func _check(ok: bool, label: String) -> void:
	if ok:
		print("[94] ", label, " -> PASS")
	else:
		failures += 1
		print("[94] ", label, " -> FAIL")

func _spell(n: String) -> Spell:
	var s := Spell.new()
	s.spell_name = n
	return s

func _border_of(b: Button) -> Color:
	if b == null:
		return Color(-2, -2, -2)
	var sb := b.get_theme_stylebox("normal") as StyleBoxFlat
	return sb.border_color if sb != null else Color(-1, -1, -1)

func _row_button(box: VBoxContainer, text: String) -> Button:
	for c in box.get_children():
		if c is Button and c.text == text:
			return c
	return null

func _row_chip(box: VBoxContainer, text: String) -> ColorRect:
	var b := _row_button(box, text)
	if b == null:
		return null
	for c in b.get_children():
		if c is ColorRect:
			return c
	return null

const C_SELECTED := Color(0.85, 0.9, 1.0, 0.9)
const C_UPGRADE := Color(0.95, 0.75, 0.25, 0.9)
const C_DIM := Color(0.45, 0.48, 0.55, 0.6)
const C_ASSIGNED := Color(0.75, 0.8, 0.9, 0.8)
const C_CHIP_ON := Color(0.5, 0.85, 0.55, 0.95)
const C_CHIP_OFF := Color(1.0, 1.0, 1.0, 0.08)

func _initialize() -> void:
	var player := StubPlayer.new()
	player.add_to_group("player")
	root.add_child(player)
	var caster := StubCaster.new()
	caster.name = "SpellCaster"
	player.add_child(caster)
	var upg := StubUpgrader.new()
	upg.name = "UpgraderStub"
	root.add_child(upg)
	var a := _spell("AlphaBolt")
	var b := _spell("BetaBolt")
	caster.fake_unlocked = [a, b]
	caster.fake_slots = [a, null, null, null, null, null]
	upg.upgradeable = [b]
	var panel: Node = load("res://scenes/equip_panel.tscn").instantiate()
	panel.upgrader_path = NodePath("../UpgraderStub")
	root.add_child(panel)
	for i in range(5):
		await process_frame

	# (0) hidden by default, modal_ui only when shown.
	_check(panel.visible == false, "(0) panel hidden by default")
	panel.show_panel()
	for i in range(2):
		await process_frame
	_check(panel.visible == true, "(0) show_panel reveals")
	_check(panel.is_in_group("modal_ui"), "(0) modal_ui group on show")

	# (1) two-column structure + headers.
	var panel_style_ok: bool = false
	var center: CenterContainer = null
	for c in panel.get_children():
		if c is CenterContainer:
			center = c
	_check(center != null, "(1) CenterContainer preserved")
	var plate: PanelContainer = center.get_child(0) as PanelContainer
	_check(plate != null, "(1) PanelContainer plate preserved")
	var plate_sb := plate.get_theme_stylebox("panel") as StyleBoxFlat
	_check(plate_sb != null, "(1) plate has flat StyleBoxFlat")
	var vbox := plate.get_child(0) as VBoxContainer
	var title := vbox.get_child(0) as Label
	_check(title.text == "Equip Spells", "(1) title preserved (got '%s')" % title.text)
	var cols := vbox.get_child(1) as HBoxContainer
	_check(cols != null and cols.get_child_count() == 2, "(1) two-column HBox")
	var unlocked_box := cols.get_child(0) as VBoxContainer
	var slots_box := cols.get_child(1) as VBoxContainer
	var uheader := unlocked_box.get_child(0) as Label
	_check(uheader.text == "Unlocked", "(1) Unlocked header preserved")
	var sheader := slots_box.get_child(0) as Label
	_check(sheader != null and sheader.text == "Slots", "(1) Slots header added")

	# (2) unlocked rows: [chip + button], texts preserved.
	var rows: Array = unlocked_box.get_children().filter(func(c): return c is Button)
	_check(rows.size() == 2, "(2) two unlocked rows (got %d)" % rows.size())
	_check(_row_button(unlocked_box, "AlphaBolt") != null, "(2) AlphaBolt row preserved")
	_check(_row_button(unlocked_box, "BetaBolt") != null, "(2) BetaBolt row preserved")
	_check(_row_chip(unlocked_box, "AlphaBolt") != null, "(2) state chip present")

	# (3) chip channel: equipped vs not.
	_check(_row_chip(unlocked_box, "AlphaBolt") != null and _row_chip(unlocked_box, "AlphaBolt").color == C_CHIP_ON, "(3) equipped chip on AlphaBolt")
	_check(_row_chip(unlocked_box, "BetaBolt") != null and _row_chip(unlocked_box, "BetaBolt").color == C_CHIP_OFF, "(3) unequipped chip on BetaBolt")

	# (4) border channel at rest: dim / upgrade-available.
	_check(_border_of(_row_button(unlocked_box, "AlphaBolt")) == C_DIM, "(4) AlphaBolt dim border")
	_check(_border_of(_row_button(unlocked_box, "BetaBolt")) == C_UPGRADE, "(4) BetaBolt upgrade-available amber")

	# (5) slots: occupied vs empty borders + preserved texts.
	var slot_buttons: Array = []
	for c in slots_box.get_children():
		if c is Button:
			slot_buttons.append(c)
	_check(slot_buttons.size() == 6, "(5) six slot buttons")
	_check(slot_buttons[0].text == "1: AlphaBolt", "(5) slot 1 text preserved (got '%s')" % slot_buttons[0].text)
	_check(slot_buttons[1].text == "2: (empty)", "(5) slot 2 empty text (got '%s')" % slot_buttons[1].text)
	_check(_border_of(slot_buttons[0]) == C_ASSIGNED, "(5) occupied slot border")
	_check(_border_of(slot_buttons[1]) == C_DIM, "(5) empty slot border")

	# (6) selection: bright border on row + move-source highlight on its slot.
	panel._on_spell_pressed(a)
	await process_frame
	_check(_border_of(_row_button(unlocked_box, "AlphaBolt")) == C_SELECTED, "(6) selected border bright")
	_check(_border_of(slot_buttons[0]) == C_SELECTED, "(6) move-source slot highlighted")
	var status := vbox.get_child(vbox.get_child_count() - 1) as Label
	_check(status.text == "Selected: AlphaBolt", "(6) status text (got '%s')" % status.text)

	# (7) upgrade section renders for upgradeable selection with amber style.
	panel._on_spell_pressed(b)
	await process_frame
	var upgrade_box := vbox.get_child(2) as VBoxContainer
	var uh := upgrade_box.get_child(0) as Label
	_check(uh != null and uh.text == "Upgrades", "(7) Upgrades header on selection")
	var ub := upgrade_box.get_child(1) as Button
	_check(ub != null and ub.text == "Path One", "(7) upgrade path button (got '%s')" % ub.text)
	_check(_border_of(ub) == C_UPGRADE, "(7) upgrade button amber")

	# (8) equip flow end-to-end: select AlphaBolt, press slot 3 -> move.
	panel._on_spell_pressed(a)
	await process_frame
	panel._on_slot_pressed(2)
	await process_frame
	_check(caster.assigned.size() == 1 and caster.assigned[0][0] == 2 and caster.assigned[0][1] == a, "(8) assign_slot(2, AlphaBolt) recorded")
	_check(caster.cleared.has(0), "(8) old slot cleared (move semantics)")
	_check(slot_buttons[2].text == "3: AlphaBolt", "(8) slot 3 shows spell (got '%s')" % slot_buttons[2].text)
	_check(slot_buttons[0].text == "1: (empty)", "(8) slot 1 emptied (got '%s')" % slot_buttons[0].text)
	_check(status.text == "Selected: none", "(8) selection cleared after assign")
	_check(_border_of(slot_buttons[2]) == C_ASSIGNED, "(8) newly occupied slot border")
	_check(_row_chip(unlocked_box, "AlphaBolt") != null and _row_chip(unlocked_box, "AlphaBolt").color == C_CHIP_ON, "(8) chip follows new slot")

	print("[94] failures=%d" % failures)
	if failures > 0:
		print("[94] FAILURES PRESENT")
	else:
		print("[94] ALL PASS")
	quit(failures)
