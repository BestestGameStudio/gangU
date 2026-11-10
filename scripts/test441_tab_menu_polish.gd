extends SceneTree
## #441 (Daniel, 2026-11-09): Tab menu polish.
##   1. The plate hugs its content - no block of empty space below the
##      spell slots (PANEL_HEIGHT trimmed; still FIXED per #416).
##   2. Upgrade cards are narrower (CARD_WIDTH), still 3 per row.
##   3. Slot rearrange is HOLD-AND-DRAG only, gesture-level: press, move
##      past the threshold, drop on a slot to swap / on empty to move.
##      Clicks never rearrange (that is pinned by test375).
## Fixture mirrors test375: stub Player + stub SpellCaster + duck-typed
## upgrade provider. Run: godot --headless --path . -s scripts/test441_tab_menu_polish.gd

class StubPlayer extends Player:
	func _ready() -> void:
		pass
	func _process(_delta: float) -> void:
		pass
	func _init() -> void:
		var aim := Node2D.new()
		aim.name = "AimIndicator"
		add_child(aim)
		var bod := Polygon2D.new()
		bod.name = "Body"
		add_child(bod)

class StubCaster extends SpellCaster:
	var fake_unlocked: Array[Spell] = []
	var fake_slots: Array[Spell] = [null, null, null, null, null, null]
	func _ready() -> void:
		pass
	func _process(_delta: float) -> void:
		pass
	func get_unlocked() -> Array[Spell]:
		return fake_unlocked.duplicate()
	func get_slots() -> Array[Spell]:
		return fake_slots.duplicate()
	func assign_slot(index: int, spell: Spell) -> bool:
		fake_slots[index] = spell
		slot_assigned.emit(index, spell)
		return true
	func clear_slot(index: int) -> bool:
		fake_slots[index] = null
		slot_cleared.emit(index)
		return true

var failures := 0
func _check(ok: bool, label: String) -> void:
	if ok:
		print("[441] ", label, " -> PASS")
	else:
		failures += 1
		print("[441] ", label, " -> FAIL")

func _spell(n: String) -> Spell:
	var s := Spell.new()
	s.spell_name = n
	return s

func _press(pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.global_position = pos
	return ev

func _release(pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.global_position = pos
	return ev

func _move(pos: Vector2) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.global_position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	return ev

func _center(b: Button) -> Vector2:
	return b.get_global_rect().get_center()

func _initialize() -> void:
	root.size = Vector2i(1152, 648)
	var player := StubPlayer.new()
	player.add_to_group("player")
	root.add_child(player)
	var caster := StubCaster.new()
	caster.name = "SpellCaster"
	player.add_child(caster)
	var a := _spell("AlphaBolt")
	var b := _spell("BetaBolt")
	caster.fake_unlocked = [a, b]
	caster.fake_slots = [a, b, null, null, null, null]
	var panel: EquipPanel = load("res://scenes/equip_panel.tscn").instantiate()
	root.add_child(panel)
	for i in range(5):
		await process_frame
	panel.show_panel()
	for i in range(8):
		await process_frame

	# (1) The plate hugs its content.
	_check(EquipPanel.PANEL_HEIGHT < 620.0, "(1) fixed height trimmed from 620 (now %.0f)" % EquipPanel.PANEL_HEIGHT)
	var plate_r := panel._plate.get_global_rect()
	_check(is_equal_approx(plate_r.size.y, EquipPanel.PANEL_HEIGHT), "(1) plate is exactly the trimmed height")
	var last_slot_bottom := panel._slot_buttons[5].get_global_rect().end.y
	_check(plate_r.end.y - last_slot_bottom < 120.0, "(1) slack below the spell slots < 120px (was ~330; now %.0f)" % (plate_r.end.y - last_slot_bottom))
	# Viewport fit is pinned on the real scene by test416 (this stub
	# harness's CenterContainer lags the root.size override, which is a
	# harness quirk, not panel behavior).
	var plate_w := plate_r.size.x

	# (2) Narrower cards, still 3 per row.
	_check(is_equal_approx(UpgradeCard.CARD_WIDTH, 176.0), "(2) card width slimmed to 176 (got %.0f)" % UpgradeCard.CARD_WIDTH)
	_check(EquipPanel.DETAIL_WIDTH >= UpgradeCard.CARD_WIDTH * 3 + EquipPanel.UPGRADE_CARD_GAP * 2, "(2) detail column still fits 3 cards")
	panel._on_slot_pressed(0)
	for i in range(2):
		await process_frame
	_check(is_equal_approx(panel._plate.get_global_rect().size.x, plate_w), "(2) plate width stable on spell stats (#416)")
	panel._on_slot_pressed(0) # deselect
	for i in range(2):
		await process_frame

	# (3) A short wiggle below the threshold is not a drag.
	var r0 := _center(panel._slot_buttons[0])
	panel._slot_buttons[0].gui_input.emit(_press(r0))
	panel._slot_buttons[0].gui_input.emit(_move(r0 + Vector2(0, EquipPanel.DRAG_THRESHOLD - 4.0)))
	_check(panel._drag_from == -1, "(3) sub-threshold move does not start a drag")
	_check(panel._drag_ghost == null, "(3) no ghost before the threshold")
	panel._slot_buttons[0].gui_input.emit(_release(r0 + Vector2(0, EquipPanel.DRAG_THRESHOLD - 4.0)))
	for i in range(2):
		await process_frame
	_check(caster.fake_slots[0] == a and caster.fake_slots[1] == b, "(3) no mutation from a wiggle")

	# (4) Drag slot 2 (BetaBolt) onto slot 1 (AlphaBolt): swap; ghost while
	# dragging, source highlighted, state cleaned up after the drop.
	var r1 := _center(panel._slot_buttons[1])
	panel._slot_buttons[1].gui_input.emit(_press(r1))
	panel._slot_buttons[1].gui_input.emit(_move(r1 + Vector2(0, 40)))
	_check(panel._drag_from == 1, "(4) drag starts past the threshold (from slot 2)")
	_check(panel._drag_ghost != null and is_instance_valid(panel._drag_ghost), "(4) ghost icon follows the drag")
	_check(panel._slot_buttons[1].get_theme_stylebox("normal").border_color == UiStyle.B_SELECTED, "(4) drag source highlighted")
	var r0b := _center(panel._slot_buttons[0])
	panel._slot_buttons[1].gui_input.emit(_release(r0b))
	for i in range(2):
		await process_frame
	_check(caster.fake_slots[0] == b and caster.fake_slots[1] == a, "(4) drop on occupied slot swaps (got %s / %s)" % [caster.fake_slots[0], caster.fake_slots[1]])
	_check(panel._drag_from == -1 and panel._drag_ghost == null, "(4) drag state cleaned up after the drop")
	_check(panel._slot_buttons[0].text == "LMB: BetaBolt", "(4) slot text follows the swap")

	# (5) Drag slot 2 (now AlphaBolt... layout [b, a]) onto empty slot 4:
	# move, old slot emptied.
	var r1c := _center(panel._slot_buttons[1])
	panel._slot_buttons[1].gui_input.emit(_press(r1c))
	panel._slot_buttons[1].gui_input.emit(_move(r1c + Vector2(30, 30)))
	var r3 := _center(panel._slot_buttons[3])
	panel._slot_buttons[1].gui_input.emit(_release(r3))
	for i in range(2):
		await process_frame
	_check(caster.fake_slots[1] == null and caster.fake_slots[3] == a, "(5) drop on empty slot moves the spell")
	_check(panel._slot_buttons[1].text == "RMB: (empty)", "(5) old slot shows empty")

	# (6) Release OUTSIDE every slot: nothing changes.
	var r0d := _center(panel._slot_buttons[0])
	panel._slot_buttons[0].gui_input.emit(_press(r0d))
	panel._slot_buttons[0].gui_input.emit(_move(r0d + Vector2(0, 60)))
	_check(panel._drag_from == 0, "(6) drag started")
	panel._slot_buttons[0].gui_input.emit(_release(Vector2(2, 2))) # the dim layer, off all slots
	for i in range(2):
		await process_frame
	_check(caster.fake_slots[0] == b, "(6) release outside all slots is a no-op")
	_check(panel._drag_from == -1 and panel._drag_ghost == null, "(6) drag state cleaned up")

	# (7) No drag from an EMPTY slot.
	var r2 := _center(panel._slot_buttons[2])
	panel._slot_buttons[2].gui_input.emit(_press(r2))
	panel._slot_buttons[2].gui_input.emit(_move(r2 + Vector2(0, 80)))
	_check(panel._drag_from == -1, "(7) empty slot never starts a drag")
	panel._slot_buttons[2].gui_input.emit(_release(r2))

	# (8) A drag that ends back on its SOURCE slot performs no rearrange and
	# swallows the trailing click (no accidental deselect).
	panel._on_slot_pressed(0) # select BetaBolt
	for i in range(2):
		await process_frame
	_check(panel._selected == b, "(8) BetaBolt selected")
	var r0e := _center(panel._slot_buttons[0])
	panel._slot_buttons[0].gui_input.emit(_press(r0e))
	panel._slot_buttons[0].gui_input.emit(_move(r0e + Vector2(0, 60)))
	panel._slot_buttons[0].gui_input.emit(_release(r0e)) # back on source
	for i in range(2):
		await process_frame
	_check(caster.fake_slots[0] == b, "(8) drop on source slot is a no-op")
	_check(panel._suppress_next_click, "(8) trailing click armed for suppression")
	panel._on_slot_pressed(0) # the click the Button would fire
	for i in range(2):
		await process_frame
	_check(panel._selected == b, "(8) selection survives the swallowed click")
	_check(not panel._suppress_next_click, "(8) suppression consumed")
	panel._on_slot_pressed(0) # deselect for a clean exit
	for i in range(2):
		await process_frame
	_check(panel._selected == null, "(8) plain click still deselects afterwards")

	print("[441] failures=%d" % failures)
	if failures > 0:
		print("[441] FAILURES PRESENT")
	else:
		print("[441] ALL PASS")
	quit(failures)
