extends SceneTree
## #94 equip-panel visual identity harness, re-pinned for the #375 Tab-side
## layout (Daniel, 2026-11-09: the menu shows ONLY your slots). Fixture:
## stub Player + stub SpellCaster (typed subclasses so the panel's
## `as Player` / `as SpellCaster` casts pass; _ready/_process overrides skip
## gameplay wiring) + stub upgrade provider (duck-typed per the panel's
## upgrader contract). Asserts the presentation layer: single-column slots
## structure + header, per-state border channels (selected / occupied /
## empty / move-source), upgrade section styling, and the slot-driven
## select/rearrange flow end-to-end. Decor legs FAIL on the pre-#94 panel.

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

const C_SELECTED := Color(0.85, 0.9, 1.0, 0.9)
const C_UPGRADE := Color(0.95, 0.75, 0.25, 0.9)
const C_DIM := Color(0.45, 0.48, 0.55, 0.6)
const C_ASSIGNED := Color(0.75, 0.8, 0.9, 0.8)

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
	caster.fake_slots = [a, b, null, null, null, null]
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

	# (1) structure + header: title, then ONE slots column + divider + the
	# #376 stat grid; no Unlocked column anywhere.
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
	_check(title.text == "Spells", "(1) title names the spell menu (got '%s')" % title.text)
	var cols := vbox.get_child(1) as HBoxContainer
	_check(cols != null and cols.get_child_count() == 3 and cols.get_child(2) is StatGrid,
		"(1) slots column + divider + #376 stats column (got %d children)" % (cols.get_child_count() if cols != null else -1))
	var slots_box := cols.get_child(0) as VBoxContainer
	_check(slots_box != null, "(1) first column is the slots box")
	var sheader := slots_box.get_child(0) as Label
	_check(sheader != null and sheader.text == "Slots", "(1) Slots header preserved")
	var no_unlocked := true
	for n in panel.find_children("*", "Label", true, false):
		if (n as Label).text == "Unlocked":
			no_unlocked = false
	_check(no_unlocked, "(1) no Unlocked column (#375: the menu shows only your slots)")

	# (2) slots: occupied vs empty borders + preserved texts.
	var slot_buttons: Array = []
	for c in slots_box.get_children():
		if c is Button:
			slot_buttons.append(c)
	_check(slot_buttons.size() == 6, "(2) six slot buttons")
	_check(slot_buttons[0].text == "LMB: AlphaBolt", "(2) slot 1 text preserved (got '%s')" % slot_buttons[0].text)
	_check(slot_buttons[2].text == "Q: (empty)", "(2) slot 3 empty text (got '%s')" % slot_buttons[2].text)
	_check(_border_of(slot_buttons[0]) == C_ASSIGNED, "(2) occupied slot border")
	_check(_border_of(slot_buttons[2]) == C_DIM, "(2) empty slot border")

	# (3) selection: clicking an occupied slot selects its spell - bright
	# move-source border on that slot + status line.
	panel._on_slot_pressed(0)
	await process_frame
	_check(_border_of(slot_buttons[0]) == C_SELECTED, "(3) selected slot highlighted")
	var status := vbox.get_child(vbox.get_child_count() - 1) as Label
	_check(status.text == "Selected: AlphaBolt", "(3) status text (got '%s')" % status.text)
	# Clicking the same slot again deselects.
	panel._on_slot_pressed(0)
	await process_frame
	_check(status.text == "Selected: none" and _border_of(slot_buttons[0]) == C_ASSIGNED,
		"(3) same-slot click deselects (status '%s')" % status.text)

	# (4) upgrade section renders for an upgradeable equipped selection with
	# amber style.
	panel._on_slot_pressed(1) # BetaBolt is slotted + upgradeable
	await process_frame
	var upgrade_box := vbox.get_child(2) as VBoxContainer
	var uh := upgrade_box.get_child(0) as Label
	_check(uh != null and uh.text == "Upgrades", "(4) Upgrades header on selection")
	var ub := upgrade_box.find_children("*", "UpgradeCard", true, false)[0] as UpgradeCard
	_check(ub != null and ub.name_label.text == "Path One", "(4) upgrade path button (got '%s')" % (ub.name_label.text if ub != null else "null"))
	_check(_border_of(ub) == C_UPGRADE, "(4) upgrade button amber")

	# (5) rearrange flow end-to-end: put BetaBolt back, select AlphaBolt,
	# press slot 3 -> move.
	panel._on_slot_pressed(1)
	await process_frame
	panel._on_slot_pressed(0)
	await process_frame
	panel._on_slot_pressed(2)
	await process_frame
	_check(caster.assigned.size() == 1 and caster.assigned[0][0] == 2 and caster.assigned[0][1] == a, "(5) assign_slot(2, AlphaBolt) recorded")
	_check(caster.cleared.has(0), "(5) old slot cleared (move semantics)")
	_check(slot_buttons[2].text == "Q: AlphaBolt", "(5) slot 3 shows spell (got '%s')" % slot_buttons[2].text)
	_check(slot_buttons[0].text == "LMB: (empty)", "(5) slot 1 emptied (got '%s')" % slot_buttons[0].text)
	_check(status.text == "Selected: none", "(5) selection cleared after rearrange")
	_check(_border_of(slot_buttons[2]) == C_ASSIGNED, "(5) newly occupied slot border")

	print("[94] failures=%d" % failures)
	if failures > 0:
		print("[94] FAILURES PRESENT")
	else:
		print("[94] ALL PASS")
	quit(failures)
