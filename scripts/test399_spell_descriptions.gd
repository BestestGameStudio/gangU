extends SceneTree
## #399: copy is behavior-derived, pure, and lives outside stat cells.
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[399] ", label, " -> ", "PASS" if ok else "FAIL")

func description(file: String) -> String:
	return SpellDescription.for_spell(load("res://resources/spells/%s.tres" % file))

func _initialize() -> void:
	check(SpellDescription.for_spell(null).is_empty(), "null selection has no description")
	var dir := DirAccess.open("res://resources/spells")
	var count := 0
	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var s := load("res://resources/spells/" + file) as Spell
		if s == null:
			continue
		var before := var_to_str(s)
		var text := SpellDescription.for_spell(s)
		check(not text.is_empty(), "%s has behavior copy" % file)
		check(text == SpellDescription.for_spell(s) and before == var_to_str(s), "%s deterministic and read-only" % file)
		count += 1
	check(count >= 40, "all existing spell resources covered: %d" % count)
	check(description("spirit_punch_bubble").contains("freeze bubble") and not description("spirit_punch_bubble").contains("punch toward"), "freeze-only Spirit Punch never promises a punch")
	check(description("spirit_punch_launch").contains("Launches") and description("spirit_punch_launch").contains("3 times"), "same-name Spirit Punch tiers use behavior fields")
	check(description("water_ball_guided").contains("1 time(s)"), "Guided once-per-shot redirect")
	check(description("water_ball_seeking").contains("briefly turn"), "Seeking cursor chase")
	check(description("water_ball_tidal").contains("until 5 hits") and description("water_ball_tidal").contains("same enemy again"), "Tidal total hit budget and rehit")
	check(description("big_ball").contains("shrink") and description("big_ball").contains("Pushes"), "Big Ball recast and end push")
	check(description("heavy_rain").contains("rain zone") and not description("heavy_rain").contains("Lobs"), "rain takes priority over splash fields")
	check(description("stone_hammer_gambler").contains("8 consecutive") and description("stone_hammer_gambler").contains("shockwave"), "Gambler combo and jump")
	check(description("stone_hammer_vortex").contains("Hold") and description("stone_hammer_vortex").contains("bonus crit"), "Vortex includes inherited behavior")
	check(description("mana_shot_lance").contains("pass through"), "piercing behavior")
	check(description("fire_ball_beam_homing").contains("nearby enemies"), "homing behavior")
	check(not description("fire_ball").contains("burn") and not description("frost_shard").contains("slow"), "metadata never invents burn or slow mechanics")
	check(description("summon_ally").contains("shared summon cap"), "summon cap caveat")
	check(description("stone_block").contains("cell allows"), "block placement caveat")

	var stage := Node2D.new()
	root.add_child(stage)
	current_scene = stage
	var player: Player = load("res://scenes/player.tscn").instantiate()
	stage.add_child(player)
	await process_frame
	var caster: SpellCaster = player.get_node("SpellCaster")
	var spell: Spell = load("res://resources/spells/stone_hammer_gambler.tres")
	caster.unlock_spell(spell)
	var panel := EquipPanel.new()
	panel.player_path = NodePath("../Player")
	stage.add_child(panel)
	await process_frame
	panel.show_panel()
	var grid := panel._stats_box
	check(grid.description().is_empty() and not grid.get_node("Description").visible, "player stats hide description")
	var slot := caster.get_slots().find(spell)
	panel._slot_buttons[slot].pressed.emit()
	await process_frame
	check(grid.description() == SpellDescription.for_spell(spell), "slot selection shows selected resource description")
	check(grid.get_node("Description").visible, "description label visible")
	var damage_cell := grid.cell(&"damage")
	player.stats.add(StatModifier.flat(PlayerStats.COOLDOWN_REDUCTION, 0.2))
	await process_frame
	check(grid.cell(&"damage") == damage_cell and grid.description() == SpellDescription.for_spell(spell), "live refresh preserves cells and description")
	panel._slot_buttons[slot].pressed.emit()
	check(grid.description().is_empty() and not grid.get_node("Description").visible, "deselect clears stale description")
	panel._slot_buttons[slot].pressed.emit()
	panel.hide_panel()
	panel.show_panel()
	check(grid.description().is_empty(), "reopen resets selection and description")
	check(grid.get_node("Grid").get_child_count() == grid.cell_ids().size(), "description is outside stat cells")
	print("RESULT: ", "ALL PASS" if failures == 0 else "%d FAILURES" % failures)
	quit(0 if failures == 0 else 1)
