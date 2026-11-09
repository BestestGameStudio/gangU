extends SceneTree
## #416: the Tab menu keeps the same size when switching between player stats
## and spell stats, and the upgrades sit under the spell stats in a column
## wide enough for three upgrade cards. Run headless for checks; run with a
## display to also save screenshots to /tmp/ci/shots416/.
var failures := 0
var shots := false

func ck(ok: bool, label: String) -> void:
	print("[416] ", label, " -> ", "PASS" if ok else "FAIL")
	if not ok: failures += 1

func cards(panel: EquipPanel) -> Array:
	return panel._upgrade_box.find_children("*", "UpgradeCard", true, false).filter(func(c): return not c.is_queued_for_deletion() and not c.get_parent().is_queued_for_deletion())

func settle(n := 8) -> void:
	for i in n: await process_frame

func shot(file: String) -> void:
	if shots:
		root.get_texture().get_image().save_png("/tmp/ci/shots416/%s.png" % file)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	shots = DisplayServer.get_name() != "headless"
	if shots:
		DirAccess.make_dir_recursive_absolute("/tmp/ci/shots416")
	root.size = Vector2i(1152, 648)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await settle(5)
	var caster: SpellCaster = main.get_node("Player/SpellCaster")
	var panel: EquipPanel = main.get_node("EquipPanel")
	var fire: Spell = load("res://resources/spells/fire_ball.tres")

	panel.show_panel()
	await settle()
	var player_rect: Rect2 = panel._plate.get_global_rect()
	ck(panel._stats_box.title() == "Stats", "opens on player stats")
	ck(player_rect.position.y >= 0 and player_rect.end.y <= 648 and player_rect.position.x >= 0 and player_rect.end.x <= 1152, "panel fits the 1152x648 viewport (%s)" % player_rect)
	await shot("player_stats")

	# Spell stats, not yet qualified for upgrades.
	panel._on_slot_pressed(caster.get_slots().find(fire))
	await settle()
	ck(panel._stats_box.title() == fire.spell_name, "slot click shows spell stats")
	ck(panel._plate.get_global_rect().is_equal_approx(player_rect), "same size on spell stats without upgrades (%s vs %s)" % [panel._plate.get_global_rect(), player_rect])

	# Spell stats with upgrade cards.
	for i in 10: caster.spell_cast.emit(fire)
	panel._refresh()
	await settle()
	var offered := cards(panel)
	ck(offered.size() == 2, "fireball upgrade cards shown")
	ck(panel._plate.get_global_rect().is_equal_approx(player_rect), "same size on spell stats with upgrades (%s vs %s)" % [panel._plate.get_global_rect(), player_rect])
	var scroll: ScrollContainer = panel._upgrade_box.get_node_or_null("UpgradeScroll")
	ck(scroll != null, "upgrade scroll present")
	if scroll != null:
		var stats_r := panel._stats_box.get_global_rect()
		var scroll_r := scroll.get_global_rect()
		ck(scroll_r.position.y >= stats_r.end.y, "upgrades sit under the spell stats")
		ck(scroll_r.position.x >= stats_r.position.x - 1.0 and scroll_r.position.x <= stats_r.position.x + 1.0, "upgrades share the stats column")
		var three := UpgradeCard.CARD_WIDTH * 3 + EquipPanel.UPGRADE_CARD_GAP * 2
		ck(scroll_r.size.x >= three, "column fits 3 upgrade cards (%.0f >= %.0f)" % [scroll_r.size.x, three])
		ck(scroll_r.size.y >= 200.0, "card area tall enough for a full card (%.0f)" % scroll_r.size.y)
		for c in offered:
			ck(scroll_r.encloses(c.get_global_rect()), "card '%s' fully visible inside the column" % c.name_label.text)
	ck(panel._status.get_global_rect().end.y <= panel._plate.get_global_rect().end.y, "status stays inside the plate")
	await shot("spell_stats_upgrades")

	# A third card (fixture) still fits without horizontal scrolling.
	if scroll != null and offered.size() > 0:
		var extra := UpgradeCard.new()
		extra.setup("Fixture third card", "Width check only.", false)
		offered[0].get_parent().add_child(extra)
		await settle()
		ck(scroll.get_global_rect().encloses(extra.get_global_rect()), "third card fits in the column")
		ck(panel._plate.get_global_rect().is_equal_approx(player_rect), "same size with three cards")
		await shot("three_cards")

	# Back to player stats (deselect).
	panel._on_slot_pressed(caster.get_slots().find(fire))
	await settle()
	ck(panel._stats_box.title() == "Stats", "deselect returns to player stats")
	ck(panel._plate.get_global_rect().is_equal_approx(player_rect), "same size after switching back")
	print("[416] DONE failures=", failures)
	if failures == 0: print("RESULT: ALL PASS")
	quit(failures)
