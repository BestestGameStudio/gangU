extends SceneTree
## #376 harness: TFT-style stat grid in the Tab menu (Daniel, 2026-11-09).
##  - Player stats render as a grid of cells showing ONLY an icon + value.
##  - Each cell's hover card (tooltip) holds the stat name and details,
##    including modifier sources.
##  - The grid sits on the right side of the Tab menu (third column).
##  - Clicking a spell replaces the player stats with that spell's stats;
##    Stone Hammer tracks its Reaper bonus crit (player crit + hammer kills).
##  - Values update live while the menu is open.
## Run: godot --headless --path . -s scripts/test376_stat_grid.gd

var failures := 0

func _check(cond: bool, name: String) -> void:
	if not cond:
		failures += 1
	print("[376] ", name, " -> ", "PASS" if cond else "FAIL")

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _unlocked_button(panel: EquipPanel, spell_name: String) -> Button:
	for c in panel._unlocked_box.get_children():
		if c is Button and not c.is_queued_for_deletion() and c.text == spell_name:
			return c
	return null

func _initialize() -> void:
	# Headless root is 64x64, so the menu lives in a 1920x1080 SubViewport;
	# that lets real mouse motion reach the cells and open Godot's own tooltip.
	var vp := SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	vp.gui_embed_subwindows = true
	root.add_child(vp)
	current_scene = vp
	var stage := Node2D.new()
	stage.name = "Stage"
	vp.add_child(stage)
	await process_frame

	var player: Player = load("res://scenes/player.tscn").instantiate()
	player.add_to_group("player")
	stage.add_child(player)
	await _frames(2)
	var caster: SpellCaster = player.get_node("SpellCaster")
	var reaper: Spell = load("res://resources/spells/stone_hammer_reaper.tres")
	caster.unlock_spell(reaper)
	player.stats.add(StatModifier.flat(PlayerStats.ARMOR, 0.15, 0.0, &"stone_skin"))
	var crit := DamageModifier.crit(0.25, 2.0)
	player.damage_modifiers.add(crit)

	var relics := OwnedRelics.new()
	relics.name = "OwnedRelics"
	stage.add_child(relics)

	var panel: EquipPanel = load("res://scenes/equip_panel.tscn").instantiate()
	panel.player_path = NodePath("../Player")
	stage.add_child(panel)
	await _frames(2)
	panel.show_panel()
	await _frames(2)

	var grid := panel.find_child("StatsBox", true, false) as StatGrid
	_check(grid != null, "StatsBox is a StatGrid")
	if grid == null:
		quit(1)
		return

	# Right side: third column after Unlocked and Slots (index 0, 1, divider 2).
	var cols := grid.get_parent()
	_check(cols is HBoxContainer and cols.get_child(0) == panel._unlocked_box and grid.get_index() == cols.get_child_count() - 1,
		"grid is the right-most column of the Tab menu")
	_check(grid.get_global_rect().position.x > panel._unlocked_box.get_global_rect().end.x, "grid sits right of the spell list")

	# Grid of icon + value cells only.
	var g := grid.get_node("Grid") as GridContainer
	_check(g.columns >= 2, "cells laid out in a multi-column grid (%d cols)" % g.columns)
	var ids := grid.cell_ids()
	_check(ids == [&"hp", &"damage_amp", &"armor", &"move_speed", &"cooldown_reduction", &"crit"], "player stat cells: %s" % [ids])
	var only_icon_value := true
	for id in ids:
		var cell := grid.cell(id)
		var row := cell.get_child(0)
		var labels := row.get_children().filter(func(n): return n is Label)
		if row.get_child_count() != 2 or not row.get_child(0) is StatIcon or labels.size() != 1:
			only_icon_value = false
	_check(only_icon_value, "each cell shows exactly one icon and one value label")
	_check(grid.value_of(&"armor") == "+15%", "armor value +15%% (%s)" % grid.value_of(&"armor"))
	_check(grid.value_of(&"crit") == "25%", "player crit 25%% (%s)" % grid.value_of(&"crit"))
	_check(grid.value_of(&"hp") == "%d/%d" % [player.hp, player.max_hp], "hp value")

	# Hover details: tooltip set, and the custom card names the stat + sources.
	var armor_cell := grid.cell(&"armor")
	_check(armor_cell.tooltip_text.begins_with("Armor"), "armor cell has a hover tooltip")
	_check(armor_cell.mouse_filter == Control.MOUSE_FILTER_STOP, "cell receives hover")
	_check(grid.details_of(&"armor").contains("Stone Skin"), "armor details list the modifier source")
	var card := armor_cell._make_custom_tooltip("") as Control
	_check(card != null and (card.find_child("Title", true, false) as Label).text.begins_with("Armor"), "custom hover card shows the stat name")
	if card != null:
		card.free()

	# Live update while open: a buff changes the value in place, same cell.
	player.stats.add(StatModifier.flat(PlayerStats.COOLDOWN_REDUCTION, 0.2))
	await _frames(1)
	_check(grid.value_of(&"cooldown_reduction") == "+20%", "CDR updates live while open")
	_check(grid.cell(&"armor") == armor_cell, "live update reuses the hovered cell")

	# Clicking a spell swaps the grid to that spell's stats.
	var btn := _unlocked_button(panel, reaper.spell_name)
	_check(btn != null, "Reaper Hammer row present")
	btn.pressed.emit()
	await _frames(1)
	_check(grid.title() == reaper.spell_name, "header shows the selected spell")
	_check(grid.cell_ids().has(&"damage") and grid.cell_ids().has(&"cooldown") and grid.cell_ids().has(&"crit") and grid.cell_ids().has(&"area"),
		"spell cells: %s" % [grid.cell_ids()])
	_check(grid.cell(&"hp") == null, "player cells replaced")
	_check(grid.value_of(&"damage") == "60", "damage 60 (%s)" % grid.value_of(&"damage"))
	_check(grid.value_of(&"cooldown") == "6.8s", "cooldown 8.5s with 20%% CDR = 6.8s (%s)" % grid.value_of(&"cooldown"))
	_check(grid.value_of(&"crit") == "25%", "hammer crit before kills = player 25%% (%s)" % grid.value_of(&"crit"))

	# Stone Hammer bonus crit is tracked (Daniel's example).
	caster.hammer_state.register_strike(reaper, 2, 2)
	await _frames(1)
	_check(grid.value_of(&"crit") == "45%", "two Reaper kills: 25%% + 20%% = 45%% (%s)" % grid.value_of(&"crit"))
	var cd := grid.details_of(&"crit")
	_check(cd.contains("Hammer kills: +20%") and cd.contains("Player: 25%") and cd.contains("+10% per kill"), "crit details break down player vs hammer bonus")

	# Review fix: the hover card Godot is ALREADY showing must follow live
	# values. Real mouse motion over the crit cell opens the real tooltip.
	var crit_cell := grid.cell(&"crit")
	var motion := InputEventMouseMotion.new()
	motion.position = crit_cell.get_global_rect().get_center()
	motion.global_position = motion.position
	vp.notification(Node.NOTIFICATION_VP_MOUSE_ENTER) # the mouse is over this viewport
	vp.push_input(motion)
	await create_timer(1.5).timeout
	var tip := crit_cell.open_tooltip()
	_check(tip != null and tip.is_inside_tree() and tip.is_visible_in_tree(), "hovering the crit cell opens Godot's real tooltip")
	if tip != null:
		var head := tip.find_child("Title", true, false) as Label
		_check(head.text.contains("45%"), "open card shows 45%% (%s)" % head.text)
		caster.hammer_state.register_strike(reaper, 1, 1)
		await _frames(2)
		_check(grid.value_of(&"crit") == "55%", "third kill: cell 55%% (%s)" % grid.value_of(&"crit"))
		_check(crit_cell.open_tooltip() == tip and tip.is_visible_in_tree(), "the same card stays open")
		_check(head.text.contains("55%"), "open card updated live to 55%% (%s)" % head.text)
		var body := tip.find_child("Details", true, false) as Label
		_check(body.text.contains("Hammer kills: +30%"), "open card details updated live (Hammer kills: +30%)")

		# A tag-matched crit relic gained while open refreshes the grid AND the card.
		var relic := Relic.new()
		relic.id = &"test376_earth_crit"
		relic.hooked_tags = [SpellTags.EARTH]
		relic.stage = DamageModifier.Stage.CRIT
		relic.chance = 0.25
		relic.multiplier = 2.0
		_check(relics.add(relic), "crit relic added through OwnedRelics.add")
		await _frames(2)
		var truth := roundi(caster.hammer_state.crit_chance(reaper, player) * 100.0)
		_check(grid.value_of(&"crit") == "%d%%" % truth and truth == 80, "relic refreshes the open grid: %s vs hammer_state %d%%" % [grid.value_of(&"crit"), truth])
		_check(head.text.contains("80%") and body.text.contains("Relics: +25%"), "open card shows the relic too (%s)" % head.text)
	var away := InputEventMouseMotion.new()
	vp.push_input(away)
	await _frames(2)

	# Assigning the spell to a slot clears the selection -> player stats back.
	panel._on_slot_pressed(0)
	await _frames(1)
	_check(grid.title() == "Stats" and grid.cell(&"hp") != null, "after assigning, grid returns to player stats")
	_check(grid.value_of(&"crit") == "25%", "player crit excludes the hammer-only bonus")

	# Review fix: Tidal Seeker's cells describe what Projectile actually does.
	# pierce_hits shots count TOTAL hits (re-hits included) and have no range expiry.
	var tidal: Spell = load("res://resources/spells/water_ball_tidal.tres")
	_check(tidal.pierce_hits == 5, "Tidal Seeker resource has pierce_hits 5")
	var te := {}
	for e in StatSheet.spell_entries(tidal, player, caster):
		te[e["id"]] = e
	_check(te.has(&"range") and te[&"range"]["value"] == "No limit" and not String(te[&"range"]["details"]).contains("1500"),
		"Tidal range: No limit, not 1500 (%s)" % te.get(&"range", {}).get("value", "?"))
	var hits: Dictionary = te.get(&"pierce", {})
	_check(hits.get("title", "") == "Hits" and hits.get("value", "") == str(tidal.pierce_hits), "Tidal shows total Hits = pierce_hits")
	_check(String(hits.get("details", "")).contains("same enemy") and String(hits.get("details", "")).contains(String.num(tidal.rehit_delay, 2) + "s")
		and not String(hits.get("details", "")).contains("Extra enemies"), "Tidal hits details: re-hits count, rehit delay shown")
	# Source fidelity: a real Tidal projectile with nothing to hit outlives spell.range.
	var tp: Projectile = load("res://scenes/projectile.tscn").instantiate()
	tp.setup(tidal, Vector2.RIGHT, player) # cast by the player: never hits its own caster
	stage.add_child(tp)
	var guard := 0
	while is_instance_valid(tp) and tp._traveled < tidal.range + 200.0 and guard < 2000:
		await physics_frame
		guard += 1
	_check(is_instance_valid(tp) and not tp.is_queued_for_deletion() and tp._traveled > tidal.range,
		"real Tidal projectile is still alive past its 1500 range (no range expiry)")
	if is_instance_valid(tp):
		tp.queue_free()
	# Control: an ordinary shot still expires at range and shows its number.
	var plain: Spell = load("res://resources/spells/mana_shot.tres")
	var pe := StatSheet.spell_entries(plain, player, caster)
	_check(pe.filter(func(e): return e["id"] == &"range")[0]["value"] == "%d" % roundi(plain.range), "normal shot keeps its numeric range")
	var pp: Projectile = load("res://scenes/projectile.tscn").instantiate()
	pp.setup(plain, Vector2.RIGHT, player)
	stage.add_child(pp)
	guard = 0
	while is_instance_valid(pp) and guard < 2000:
		await physics_frame
		guard += 1
	_check(not is_instance_valid(pp), "normal shot expires at its range")

	# Non-hammer spells have no hammer cells.
	var bolt: Spell = load("res://resources/spells/mana_shot.tres")
	var entries := StatSheet.spell_entries(bolt, player, caster)
	var eids := entries.map(func(e): return e["id"])
	_check(not eids.has(&"area") and not eids.has(&"combo"), "non-hammer spell shows no hammer cells")

	print("[376] SUMMARY failures=", failures)
	print("RESULT: ALL PASS" if failures == 0 else "RESULT: FAIL")
	quit(0 if failures == 0 else 1)
