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
	print("[402i] DONE failures=", failures)
	quit(failures)
