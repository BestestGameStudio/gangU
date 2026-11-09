extends SceneTree
## #402 production panel/provider checks. Synthetic casts/token grants are fixtures.
var failures := 0
func ck(ok: bool, label: String) -> void:
	print("[402i] ", label, " -> ", "PASS" if ok else "FAIL")
	if not ok: failures += 1
func cards(panel: EquipPanel) -> Array:
	return panel._upgrade_box.find_children("*", "UpgradeCard", true, false).filter(func(c): return not c.is_queued_for_deletion() and not c.get_parent().is_queued_for_deletion())
func click(card: UpgradeCard) -> void:
	var at := card.get_global_rect().get_center()
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event)
		await process_frame
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1152, 648)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	for i in 5: await process_frame
	var caster: SpellCaster = main.get_node("Player/SpellCaster")
	var progress: SpellProgress = main.get_node("SpellProgress")
	var panel: EquipPanel = main.get_node("EquipPanel")
	var fire: Spell = load("res://resources/spells/fire_ball.tres")
	panel.show_panel()
	panel._on_slot_pressed(caster.get_slots().find(fire))
	for i in 3: await process_frame
	ck(cards(panel).is_empty(), "unqualified spell offers no cards")
	for i in 10: caster.spell_cast.emit(fire)
	panel._refresh()
	for i in 8: await process_frame
	var offered := cards(panel)
	ck(offered.size() == 2, "two qualified fireball cards")
	if offered.size() != 2:
		quit(1)
		return
	ck(offered[1].global_position.x >= offered[0].get_global_rect().end.x, "production cards side by side")
	ck(offered[0].name_label.text == "Split shot [S]" and offered[1].name_label.text == "Beam [S]", "real names and tier labels")
	ck(offered[0].description_label.text.begins_with(SpellDescription.for_spell(load("res://resources/spells/fire_ball_split.tres"))), "copy from real result behavior")
	ck(offered[1].description_label.text.contains("900 px range | 2000 px/s") and not offered[1].description_label.text.contains("pierc"), "Beam copy matches nonpiercing real range and speed")
	ck(panel._stats_box.description() == SpellDescription.for_spell(fire), "399 selected source description preserved")
	var scroller: ScrollContainer = panel._upgrade_box.get_node("UpgradeScroll")
	ck(scroller.get_global_rect().end.x <= 1152 and scroller.get_global_rect().end.y <= 648, "card scroll viewport fits screen")
	scroller.scroll_vertical = 0
	for i in 3: await process_frame
	if DisplayServer.get_name() != "headless": root.get_texture().get_image().save_png("/downloads/402_integrated_cast.png")
	await click(offered[0])
	ck(not caster.get_unlocked().has(fire), "actual mouse click applies cast-qualified upgrade")
	var split: Spell = load("res://resources/spells/fire_ball_split.tres")
	ck(caster.get_unlocked().has(split), "replacement is unlocked")
	panel.hide_panel()
	panel.show_panel()
	panel._on_slot_pressed(caster.get_slots().find(split))
	progress.add_upgrade_token()
	panel._refresh()
	for i in 8: await process_frame
	offered = cards(panel)
	ck(offered.size() == 2, "token offers next tier cards only")
	if offered.size() == 2:
		ck(offered[0].action_label.text.contains("token"), "token cost labelled")
		if DisplayServer.get_name() != "headless": root.get_texture().get_image().save_png("/downloads/402_integrated_token.png")
		await click(offered[0])
		ck(progress.upgrade_tokens() == 0, "actual mouse click spends one token")
		ck(not caster.get_unlocked().has(split), "token route replaces selected spell")
	# Long production content: keep source stats and every upgrade word, while
	# bounding the panel and making the final action reachable by scrolling.
	panel.hide_panel()
	var leap: Spell = load("res://resources/spells/stone_hammer_leap.tres")
	caster.unlock_spell(leap)
	caster.clear_slot(caster.get_slots().find(leap))
	caster.clear_slot(0)
	caster.assign_slot(0, leap)
	progress.add_upgrade_token()
	panel.show_panel()
	panel._on_slot_pressed(0)
	for i in 30: await process_frame
	offered = cards(panel)
	ck(offered.size() == 1 and offered[0].name_label.text == "Dice Roll [G]", "real long-description Dice Roll offered")
	if offered.size() == 1:
		var card: UpgradeCard = offered[0]
		scroller = panel._upgrade_box.get_node("UpgradeScroll")
		var plate := panel._plate
		ck(plate.get_global_rect().position.y >= 0 and plate.get_global_rect().end.y <= 648, "Leaping Hammer full panel bounded by viewport")
		ck(panel._status.get_global_rect().end.y <= 648, "long-content selected status stays on screen")
		ck(panel._stats_box.description() == SpellDescription.for_spell(leap), "long source description preserved")
		ck(card.description_label.text == SpellDescription.for_spell(load("res://resources/spells/stone_hammer_gambler.tres")), "full long upgrade copy preserved")
		if DisplayServer.get_name() != "headless": root.get_texture().get_image().save_png("/downloads/402_long_top.png")
		scroller.scroll_vertical = 99999
		for i in 8: await process_frame
		ck(scroller.scroll_vertical > 0, "long upgrade content actually scrolls")
		var action_rect := card.action_label.get_global_rect()
		ck(scroller.get_global_rect().encloses(action_rect), "long upgrade action reachable inside scroll viewport")
		if DisplayServer.get_name() != "headless": root.get_texture().get_image().save_png("/downloads/402_long_bottom.png")
		# Click the visible bottom action, not an off-screen card centre.
		var at := action_rect.get_center()
		for down in [true, false]:
			var event := InputEventMouseButton.new()
			event.position = at
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = down
			root.push_input(event)
			await process_frame
		ck(progress.upgrade_tokens() == 0 and not caster.get_unlocked().has(leap), "scrolled action mouse click applies long token upgrade")
	print("[402i] DONE failures=", failures)
	quit(failures)
