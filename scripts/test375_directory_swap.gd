extends SceneTree
## #375 harness: spell SWAPPING at the hub spell directory (Daniel
## 2026-11-09: "You can swap spells at the spell directory"). Bounded lane:
## directory-side only - select an unlocked spell, click a slot target,
## occupied = swap (occupant stays unlocked), empty = equip. Composed from
## the caster's strict clear_slot/assign_slot primitives; one-spell-one-slot
## and refusal semantics preserved. Rearranging equipped spells stays the
## Tab menu's job: a slotted selection clicking a slot is refused.
##
## The #218 listing contract is preserved (same row structure, Button-free
## Rows box, walk-up/walk-away); test218 runs unchanged beside this harness.

var failures := 0
var check_count := 0
var caster: SpellCaster
var panel: SpellDirectoryPanel
var directory: SpellDirectory
var fireball: Spell = preload("res://resources/spells/fire_ball.tres")
var mana: Spell = preload("res://resources/spells/mana_shot.tres")
var bolt: Spell = preload("res://resources/spells/placeholder_bolt.tres")
var frost: Spell = preload("res://resources/spells/frost_shard.tres")

func _check(cond: bool, name: String) -> void:
	check_count += 1
	if cond:
		print("[375] ", name, " -> PASS")
	else:
		failures += 1
		print("[375] ", name, " -> FAIL")

## Stub player: real typed Player + real SpellCaster child (test218 idiom).
func _make_player() -> Player:
	var p := Player.new()
	p.name = "StubPlayer"
	p.set_process(false)
	p.set_physics_process(false)
	var aim := Node2D.new()
	aim.name = "AimIndicator"
	p.add_child(aim)
	var bod := Polygon2D.new()
	bod.name = "Body"
	p.add_child(bod)
	var nose := Polygon2D.new()
	nose.name = "NoseEdge"
	p.add_child(nose)
	caster = SpellCaster.new()
	caster.name = "SpellCaster"
	p.add_child(caster)
	p.add_to_group("player")
	root.add_child(p)
	return p

func _rows() -> VBoxContainer:
	return panel.get_node("Backdrop/Margin/VBox/Scroll/Rows") as VBoxContainer

func _slot_bar() -> HBoxContainer:
	return panel.get_node("Backdrop/Margin/VBox/SlotBar") as HBoxContainer

func _status() -> Label:
	return panel.get_node("Backdrop/Margin/VBox/StatusLabel") as Label

func _row_named(spell_name: String) -> Control:
	for row in _rows().get_children():
		var label := row.find_children("NameLabel", "Label", true, false)
		if not label.is_empty() and label[0].text == spell_name:
			return row
	return null

func _row_slot_label(spell_name: String) -> String:
	var row := _row_named(spell_name)
	if row == null:
		return ""
	var labels := row.find_children("SlotLabel", "Label", true, false)
	return "" if labels.is_empty() else labels[0].text

func _slot_count(spell: Spell) -> int:
	var n := 0
	for s in caster.get_slots():
		if s == spell:
			n += 1
	return n

var _legs_ran := false

func _process(_delta: float) -> bool:
	if _legs_ran:
		return false
	_legs_ran = true
	_run_legs()
	quit(1 if failures > 0 else 0)
	return false

func _run_legs() -> void:
	print("test375: spell directory swapping (#375)")
	var p := _make_player()
	directory = preload("res://scenes/spell_directory.tscn").instantiate()
	root.add_child(directory)
	panel = preload("res://scenes/spell_directory_panel.tscn").instantiate()
	root.add_child(panel)

	var wallet := CurrencyWallet.new()
	root.add_child(wallet)
	wallet.add(25)

	# #262: grants auto-bind to the first free slot, so fireball -> slot 0,
	# mana -> slot 1. bolt starts UNEQUIPPED (its auto-bind is cleared) as
	# the swap-in candidate.
	caster.unlock_spell(fireball)
	caster.unlock_spell(mana)
	caster.unlock_spell(bolt)
	caster.unlock_spell(frost)
	_check(caster.clear_slot(caster.get_slots().find(bolt)), "fixture: bolt unequipped but unlocked")
	_check(caster.clear_slot(caster.get_slots().find(frost)), "fixture: frost unequipped but unlocked")
	_check(caster.get_slots()[0] == fireball and caster.get_slots()[1] == mana, "fixture: fireball LMB, mana RMB")

	## 1. Browsing state: no selection, no slot bar, equipped markers shown.
	directory._on_body_entered(p)
	_check(panel.visible, "walk-up opens panel")
	_check(not _slot_bar().visible, "no selection: slot bar hidden")
	_check(_status().text == "", "no selection: status empty")
	_check(_row_slot_label("Fire Ball") == "LMB", "equipped marker: Fire Ball shows LMB")
	_check(_row_slot_label("Mana Shot") == "RMB", "equipped marker: Mana Shot shows RMB")
	_check(_row_slot_label("Placeholder Bolt") == "", "unequipped bolt shows no slot marker")

	## 2. Selection shows the six slot targets with key labels + occupants.
	panel.select_spell(bolt)
	_check(_slot_bar().visible, "selection shows the slot bar")
	_check(_slot_bar().get_child_count() == SpellCaster.SLOT_COUNT, "six slot targets")
	var t0 := _slot_bar().get_node("SlotTarget0") as Button
	var t4 := _slot_bar().get_node("SlotTarget4") as Button
	_check(t0.text == "LMB\nFire Ball", "occupied target shows key + occupant")
	_check(t4.text == "R\n(empty)", "empty target shows key + (empty)")

	## 3. gui_input click path selects the row (no Buttons in Rows).
	panel.select_spell(bolt) # deselect first
	_check(not _slot_bar().visible, "re-click deselects")
	var row := _row_named("Placeholder Bolt")
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	row.gui_input.emit(ev)
	_check(_slot_bar().visible, "row left-click selects via gui_input")

	## 4. Empty target: equip.
	panel._on_slot_chosen(4)
	_check(caster.get_slots()[4] == bolt, "empty slot: bolt equipped to R")
	_check(_slot_count(bolt) == 1, "bolt occupies exactly one slot")
	_check(not _slot_bar().visible, "selection consumed after equip")
	_check(_status().text == "Placeholder Bolt -> R", "status reports the equip")
	_check(_row_slot_label("Placeholder Bolt") == "R", "marker follows the new slot")

	## 5. Occupied target: swap. Occupant stays unlocked, unequipped.
	panel.select_spell(frost)
	panel._on_slot_chosen(0)
	_check(caster.get_slots()[0] == frost, "swap: frost takes LMB")
	_check(_slot_count(fireball) == 0, "swap: fireball unequipped")
	_check(caster.get_unlocked().has(fireball), "swap: fireball stays unlocked")
	_check(_slot_count(frost) == 1, "swap: frost exactly one slot (one spell one slot)")
	_check(_status().text == "Frost Shard -> LMB (swapped out Fire Ball)", "status reports the swap")

	## 6. Equipped selection clicking a slot is refused (rearrange = Tab).
	var before := caster.get_slots()
	panel.select_spell(mana)
	panel._on_slot_chosen(0)
	_check(caster.get_slots() == before, "refusal: slots unchanged")
	_check(_status().text == "Mana Shot is equipped to RMB - rearrange slots in the Tab menu", "refusal hints at the Tab menu")
	_check(_slot_bar().visible, "refusal keeps the selection for another pick")

	## 7. Own slot: no-op, selection dropped without a refusal message.
	panel._on_slot_chosen(1)
	_check(caster.get_slots() == before, "own slot: no change")
	_check(not _slot_bar().visible, "own slot: selection dropped")
	_check(_status().text == "", "own slot: no refusal text")

	## 8. Upgrade consuming the selection clears it (no stale resource).
	panel.select_spell(fireball)
	_check(_slot_bar().visible, "fireball selected")
	var split: Spell = preload("res://resources/spells/fire_ball_split.tres")
	_check(caster.replace_spell(fireball, split), "real upgrade replacement accepted")
	_check(not _slot_bar().visible, "consumed selection cleared on spell_replaced")

	## 9. Live external slot change re-renders markers while open.
	caster.clear_slot(1)
	_check(_row_slot_label("Mana Shot") == "", "external clear drops the marker live")

	## 10. Read-only boundaries preserved: no grants, no wallet mutation.
	_check(caster.get_unlocked().size() == 4, "swaps never grant or remove unlocks")
	_check(wallet.balance() == 25, "wallet unchanged")

	## 11. #218 contract preserved: Rows stay Button-free; walk-away closes
	## and resets selection state.
	_check(_rows().find_children("*", "Button", true, false).is_empty(), "Rows contain no Buttons (#218 contract)")
	directory._on_body_exited(p)
	_check(not panel.visible and not panel.is_in_group("modal_ui"), "walk-away closes")
	panel.select_spell(mana) # stale state must not survive a close+reopen
	panel.close()
	directory._on_body_entered(p)
	_check(not _slot_bar().visible, "reopen starts with no selection")
	directory._on_body_exited(p)

	print("test375 done: %d checks, %d failures" % [check_count, failures])

func _done() -> bool:
	return true
