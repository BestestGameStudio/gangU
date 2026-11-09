extends SceneTree
## #375 Tab-side acceptance harness (Daniel, 2026-11-09): the spell menu
## shows ONLY your six slots; click an occupied slot to select its spell
## (stat grid + upgrades for equipped spells), click a second slot to
## rearrange (swap occupants, or move into an empty slot), click the same
## slot again to deselect. Rearrange is composed from the strict
## clear_slot/assign_slot primitives: validate first, rollback on refusal,
## one-spell-one-slot preserved. Unslotted unlocked spells never appear.
## Fixture: stub Player + stub SpellCaster (typed subclasses so the panel's
## casts pass) + duck-typed upgrade provider.
## Run: godot --headless --path . -s scripts/test375_tab_slots.gd

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
	var refuse_assigns := 0 # refuse the next N assign_slot calls (rollback legs)
	func _ready() -> void:
		pass
	func _process(_delta: float) -> void:
		pass
	func get_unlocked() -> Array[Spell]:
		return fake_unlocked.duplicate()
	func get_slots() -> Array[Spell]:
		return fake_slots.duplicate()
	func assign_slot(index: int, spell: Spell) -> bool:
		if refuse_assigns > 0:
			refuse_assigns -= 1
			return false
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
	var applied: Array = []
	func can_upgrade(spell: Spell) -> bool:
		return upgradeable.has(spell)
	func get_upgrade_paths(_spell: Spell) -> Array:
		return [{"id": "p1", "display_name": "Path One"}]
	func apply_upgrade(spell: Spell, path_id) -> bool:
		applied.append([spell, path_id])
		return true

var failures := 0
func _check(ok: bool, label: String) -> void:
	if ok:
		print("[375T] ", label, " -> PASS")
	else:
		failures += 1
		print("[375T] ", label, " -> FAIL")

func _spell(n: String) -> Spell:
	var s := Spell.new()
	s.spell_name = n
	return s

func _border_of(b: Button) -> Color:
	if b == null:
		return Color(-2, -2, -2)
	var sb := b.get_theme_stylebox("normal") as StyleBoxFlat
	return sb.border_color if sb != null else Color(-1, -1, -1)

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
	var g := _spell("GammaBolt") # unlocked but NEVER slotted
	caster.fake_unlocked = [a, b, g]
	caster.fake_slots = [a, b, null, null, null, null]
	upg.upgradeable = [b]
	var panel: EquipPanel = load("res://scenes/equip_panel.tscn").instantiate()
	panel.upgrader_path = NodePath("../UpgraderStub")
	root.add_child(panel)
	for i in range(5):
		await process_frame
	panel.show_panel()
	for i in range(2):
		await process_frame

	var vbox: VBoxContainer = null
	for c in panel.find_children("*", "VBoxContainer", true, false):
		if c.get_parent() is PanelContainer:
			vbox = c
	var status := vbox.get_child(vbox.get_child_count() - 1) as Label
	var grid := panel.find_child("StatsBox", true, false) as StatGrid

	# (0) The menu shows ONLY the slots: three columns (slots, divider,
	# stat grid), no "Unlocked" header, and the unslotted GammaBolt has no
	# button anywhere in the panel.
	var cols := vbox.get_child(1) as HBoxContainer
	_check(cols != null and cols.get_child_count() == 3, "(0) three columns: slots + divider + stats (got %d)" % (cols.get_child_count() if cols != null else -1))
	_check(cols.get_child(0) == panel._slots_box, "(0) first column is the slots box")
	_check(cols.get_child(1) is VSeparator, "(0) divider second")
	_check(cols.get_child(2) is StatGrid, "(0) stat grid right-most")
	var unlocked_header := false
	var gamma_button := false
	for n in panel.find_children("*", "Label", true, false):
		if (n as Label).text == "Unlocked":
			unlocked_header = true
	for n in panel.find_children("*", "Button", true, false):
		if (n as Button).text == "GammaBolt":
			gamma_button = true
	_check(not unlocked_header, "(0) no Unlocked header")
	_check(not gamma_button, "(0) unslotted GammaBolt never appears")
	_check(panel._slot_buttons[0].text == "LMB: AlphaBolt", "(0) slot 1 text (got '%s')" % panel._slot_buttons[0].text)
	_check(panel._slot_buttons[2].text == "Q: (empty)", "(0) slot 3 empty text (got '%s')" % panel._slot_buttons[2].text)

	# (1) Click an occupied slot: selects its spell (status, move-source
	# highlight, stat grid swaps to the spell).
	panel._on_slot_pressed(0)
	await process_frame
	_check(panel._selected == a, "(1) slot click selects its spell")
	_check(status.text == "Selected: AlphaBolt", "(1) status text (got '%s')" % status.text)
	_check(_border_of(panel._slot_buttons[0]) == UiStyle.B_SELECTED, "(1) selected slot highlighted")
	_check(grid.title() == "AlphaBolt", "(1) stat grid shows the selected spell (got '%s')" % grid.title())

	# (2) Click the SAME slot again: deselect; grid returns to player stats.
	panel._on_slot_pressed(0)
	await process_frame
	_check(panel._selected == null and status.text == "Selected: none", "(2) same-slot click deselects")
	_check(grid.title() == "Stats", "(2) grid back to player stats (got '%s')" % grid.title())

	# (3) Click a second OCCUPIED slot: the two occupants swap;
	# one-spell-one-slot preserved; selection cleared.
	caster.assigned.clear()
	caster.cleared.clear()
	panel._on_slot_pressed(0) # pick up AlphaBolt
	await process_frame
	panel._on_slot_pressed(1) # drop on BetaBolt's slot -> swap
	await process_frame
	_check(caster.fake_slots[0] == b and caster.fake_slots[1] == a, "(3) occupants swapped (got %s / %s)" % [caster.fake_slots[0], caster.fake_slots[1]])
	_check(caster.cleared == [0, 1], "(3) both slots cleared, source first (got %s)" % str(caster.cleared))
	_check(caster.assigned.size() == 2 and caster.assigned[0] == [1, a] and caster.assigned[1] == [0, b],
		"(3) assigned to target then source (got %s)" % str(caster.assigned))
	_check(caster.fake_slots.count(a) == 1 and caster.fake_slots.count(b) == 1, "(3) one spell one slot")
	_check(panel._selected == null, "(3) selection cleared after rearrange")
	_check(panel._slot_buttons[0].text == "LMB: BetaBolt" and panel._slot_buttons[1].text == "RMB: AlphaBolt",
		"(3) slot texts follow the swap (got '%s' / '%s')" % [panel._slot_buttons[0].text, panel._slot_buttons[1].text])

	# (4) Click an EMPTY slot: the selected spell moves there.
	caster.assigned.clear()
	caster.cleared.clear()
	panel._on_slot_pressed(1) # pick up AlphaBolt
	await process_frame
	panel._on_slot_pressed(3) # move into empty slot 4
	await process_frame
	_check(caster.cleared == [1] and caster.assigned == [[3, a]], "(4) move into empty slot (cleared %s, assigned %s)" % [str(caster.cleared), str(caster.assigned)])
	_check(caster.fake_slots[1] == null and caster.fake_slots[3] == a, "(4) old slot emptied, new slot holds the spell")
	_check(panel._slot_buttons[1].text == "RMB: (empty)" and panel._slot_buttons[3].text == "E: AlphaBolt",
		"(4) slot texts follow the move (got '%s' / '%s')" % [panel._slot_buttons[1].text, panel._slot_buttons[3].text])

	# (5) Refusal rollback: the caster refuses the first assign of a swap;
	# the panel restores the prior layout instead of leaving a half-swap.
	# Layout now: [b, null, null, a, null, null].
	caster.assigned.clear()
	caster.cleared.clear()
	caster.refuse_assigns = 1
	panel._on_slot_pressed(3) # pick up AlphaBolt
	await process_frame
	panel._on_slot_pressed(0) # try to swap with BetaBolt: first assign refused
	await process_frame
	_check(caster.refuse_assigns == 0, "(5) the refusal was exercised")
	_check(caster.fake_slots[0] == b and caster.fake_slots[3] == a, "(5) layout restored after refusal (got %s / %s)" % [caster.fake_slots[0], caster.fake_slots[3]])
	_check(caster.fake_slots.count(a) == 1 and caster.fake_slots.count(b) == 1, "(5) one spell one slot survives the rollback")
	_check(panel._selected == null, "(5) selection cleared after refused rearrange")

	# (6) Stale selection: a selected resource the caster no longer holds
	# (e.g. consumed by an upgrade) is refused BEFORE any clear, so an
	# occupied target slot is never erased.
	var removed := _spell("RemovedBolt")
	panel._selected = removed # white-box: simulates a post-upgrade stale selection
	caster.assigned.clear()
	caster.cleared.clear()
	panel._on_slot_pressed(0) # occupied by BetaBolt
	await process_frame
	_check(caster.cleared.is_empty() and caster.assigned.is_empty(), "(6) stale selection: no clear/assign reached the caster")
	_check(caster.fake_slots[0] == b, "(6) occupied target preserved")
	_check(panel._selected == null and status.text == "Selected: none", "(6) stale selection dropped")

	# (7) Equipped spells stay upgradeable from Tab: select BetaBolt (in a
	# slot) and its upgrade buttons render and apply.
	panel._on_slot_pressed(0) # select BetaBolt
	await process_frame
	_check(panel._selected == b, "(7) equipped spell selected")
	var upgrade_box := vbox.get_child(2) as VBoxContainer
	var uh := upgrade_box.get_child(0) as Label
	_check(uh != null and uh.text == "Upgrades", "(7) Upgrades header on selection")
	var ub := upgrade_box.find_child("UpgradeCards", true, false).get_child(0) as UpgradeCard
	_check(ub != null and ub.name_label.text == "Path One" and ub.action_label.text == "Choose upgrade", "(7) upgrade path button (got '%s')" % (ub.name_label.text if ub != null else "null"))
	if ub != null:
		ub.pressed.emit()
		await process_frame
	_check(upg.applied == [[b, "p1"]], "(7) upgrade applied to the equipped spell (got %s)" % str(upg.applied))
	_check(panel._selected == b, "(7) selection kept: the resource survived the upgrade")

	# (8) Empty slot with no selection: a no-op, no crash, no mutation.
	panel._on_slot_pressed(0) # deselect BetaBolt (same slot)
	await process_frame
	caster.assigned.clear()
	caster.cleared.clear()
	panel._on_slot_pressed(5)
	await process_frame
	_check(caster.cleared.is_empty() and caster.assigned.is_empty() and panel._selected == null,
		"(8) empty slot with no selection is a no-op")

	print("[375T] failures=%d" % failures)
	if failures > 0:
		print("[375T] FAILURES PRESENT")
	else:
		print("[375T] ALL PASS")
	quit(failures)
