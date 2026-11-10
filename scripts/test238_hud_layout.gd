extends SceneTree
## #238 HUD layout: production main.tscn boots with the starters in slots 1-2,
## the 3x2 grid mirrors the six slots with empty placeholders, the cooldown
## wipe covers the bottom fraction of the icon and clears downward, the
## chevron follows can_upgrade and draws above the wipe, and the Tab panel
## shows the chevron with no cooldown display.

const SIDE := 48.0

var failures := 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("[238] ", label, " -> PASS")
	else:
		failures += 1
		print("[238] ", label, " -> FAIL")

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _loadout(first: Spell, second: Spell) -> Array[Spell]:
	var out: Array[Spell] = [first, second, null, null, null, null]
	return out

func _icons_in(n: Node) -> Array:
	return n.find_children("SpellIcon", "TextureRect", true, false)

func _initialize() -> void:
	root.size = Vector2i(1152, 648)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(30) # past the HUD's 0.25s provider discovery
	var hud: HUD = main.get_node("HUD")
	var caster: SpellCaster = main.get_node("Player/SpellCaster")
	var progress: SpellProgress = main.get_node("SpellProgress")
	var equip: EquipPanel = main.get_node("EquipPanel")
	var fire: Spell = load("res://resources/spells/fire_ball.tres")
	var mana: Spell = load("res://resources/spells/mana_shot.tres")
	var frames: SpriteFrames = load("res://resources/sprites/spell_icons_frames.tres")
	var grid := hud.get_node("Root/SpellGrid") as GridContainer

	# Seed: starter in slot 1 exactly once; grid and Tab panel agree.
	_check(caster.get_slots() == _loadout(fire, mana), "starting spells seeded into slots 1-2 in order")
	_check(caster.get_unlocked().count(fire) == 1 and caster.get_unlocked().count(mana) == 1, "starters seeded once, not double-added")
	equip.show_panel()
	await process_frame
	_check(equip._slot_buttons[0].text == "LMB: Fire Ball", "Tab panel shows the seeded slot (got '%s')" % equip._slot_buttons[0].text)
	_check(equip._slot_buttons[1].text == "RMB: Mana Shot", "Tab panel shows seeded slot 2 (got '%s')" % equip._slot_buttons[1].text)
	_check(equip._slot_buttons[2].text == "Q: (empty)", "Tab panel slot 3 empty")
	equip.hide_panel()

	# Grid: six squares in 3x2, empties are placeholders.
	_check(grid.columns == 3 and grid.get_child_count() == 6, "grid is 3x2")
	var squares: Array = grid.get_children()
	var top: float = squares[0].global_position.y
	_check(squares[2].global_position.y == top and squares[3].global_position.y > top, "squares wrap after three")
	_check(squares[0].texture == frames.get_frame_texture(&"fireball_base", 0), "slot 1 shows the starter's art")
	_check(squares[1].texture == frames.get_frame_texture(&"mana_base", 0), "slot 2 shows the second starter's art")
	for i in range(2, 6):
		_check(squares[i].texture == null and squares[i].get_node("Placeholder").visible, "slot %d empty placeholder" % (i + 1))
	var hp_bar: Control = hud.get_node("Root/HPBar")
	var player: Player = main.get_node("Player")
	var hp_label := hud.get_node("Root/HPBar/HPLabel") as Label
	var hp_before := hp_label.text
	player.apply_damage(7)
	_check(hp_label.text == "%d/%d" % [player.hp, player.max_hp] and hp_label.text != hp_before, "HP text follows damage (got '%s')" % hp_label.text)
	player.heal(7)
	_check(hp_label.text == hp_before, "HP text follows healing (got '%s')" % hp_label.text)
	_check(hud.reserved_rect().encloses(squares[5].get_global_rect()) and hud.reserved_rect().encloses(hp_bar.get_global_rect()), "reserved_rect spans the real content")

	# Wipe: bottom fraction covered; a free icon isolates the geometry from
	# the HUD's per-frame cooldown refresh.
	var free_icon := SpellIcon.new(SIDE, true)
	root.add_child(free_icon)
	var free_wipe := free_icon.get_node("CooldownWipe") as ColorRect
	_check(free_wipe.color.a > 0.0 and free_wipe.color.a < 1.0, "wipe is translucent (#278)")
	await process_frame
	for frac in [1.0, 0.75, 0.5, 0.1]:
		free_icon.set_cooldown_fraction(frac)
		await process_frame
		var r := free_wipe.get_global_rect()
		var i_r := free_icon.get_global_rect()
		var expected_top: float = i_r.end.y - SIDE * frac
		_check(free_wipe.visible and is_equal_approx(r.position.y, expected_top) and is_equal_approx(r.end.y, i_r.end.y) and is_equal_approx(r.size.x, SIDE),
			"wipe at %.2f covers the bottom fraction, top edge at %.1f (got %s)" % [frac, expected_top, str(r)])
	free_icon.set_cooldown_fraction(0.0)
	_check(not free_wipe.visible, "wipe gone at 0")
	free_icon.free()
	var icon: SpellIcon = squares[0]
	var wipe := icon.get_node("CooldownWipe") as ColorRect
	var bare := SpellIcon.new(SIDE, true)
	root.add_child(bare)
	bare.show_spell(null)
	bare.set_cooldown_fraction(0.5)
	_check(bare.get_node("CooldownWipe").visible, "wipe works with no art")
	bare.free()
	caster._cooldowns[fire] = fire.cooldown * 0.5
	await _frames(2)
	var live_frac := caster.cooldown_remaining(fire) / fire.cooldown
	var live_cov := wipe.get_global_rect().size.y / SIDE
	_check(absf(live_cov - live_frac) < 0.1, "HUD drives wipe from cooldown (frac %.2f coverage %.2f)" % [live_frac, live_cov])
	caster._cooldowns[fire] = 0.0
	await _frames(2)

	# Chevron: follows can_upgrade, stays in bounds, loops, sits above the wipe.
	var chevron := icon.get_node("UpgradeChevron") as TextureRect
	_check(not chevron.visible, "chevron hidden while can_upgrade is false")
	for i in 10:
		caster.spell_cast.emit(fire)
	_check(progress.can_upgrade(fire), "setup: fire can upgrade at 10 casts")
	await _frames(2)
	_check(chevron.visible, "chevron shows when can_upgrade is true")
	_check(chevron.get_index() > wipe.get_index(), "chevron draws above the wipe")
	caster._cooldowns[fire] = 1000.0 # clamps to a full wipe for the whole window
	await _frames(2)
	var textures := {}
	var ys := {}
	var in_bounds := true
	var rises := 0
	var falls := 0
	var last_y := chevron.position.y
	for i in 240:
		await process_frame
		textures[chevron.texture] = true
		ys[snappedf(chevron.position.y, 1.0)] = true
		if chevron.position.y < last_y:
			rises += 1
		elif chevron.position.y > last_y:
			falls += 1 # the once-per-cycle reset back to the bottom
		last_y = chevron.position.y
		var r := chevron.get_global_rect()
		in_bounds = in_bounds and icon.get_global_rect().grow(0.01).encloses(r)
	_check(textures.size() == 4, "chevron loops all 4 frames (saw %d)" % textures.size())
	_check(ys.size() > 4, "chevron travels vertically (saw %d rows)" % ys.size())
	_check(rises > falls * 2, "chevron drifts upward (%d frames up, %d down)" % [rises, falls])
	_check(in_bounds, "chevron stays within the icon")
	_check(chevron.visible and wipe.visible, "chevron remains visible over an active wipe")

	# Tab panel: chevron overlay, no cooldown, with the spell cooling. (#375
	# removed the unlocked rows, so the slot icons are the Tab surface.)
	caster._cooldowns[fire] = fire.cooldown
	equip.show_panel()
	await _frames(2)
	for pi in [equip._slot_icons[0]]:
		_check(pi.get_node("UpgradeChevron").visible, "Tab icon shows the chevron")
		_check(not pi.get_node("CooldownWipe").visible, "Tab icon shows no cooldown wipe")
		_check(pi.texture == frames.get_frame_texture(&"fireball_base", 0), "Tab icon keeps base art while cooling")
	_check(not equip._slot_icons[1].get_node("UpgradeChevron").visible, "Tab slot without an upgrade shows no chevron")
	_check(not equip._slot_icons[2].get_node("UpgradeChevron").visible, "Tab empty slot shows no chevron")

	# upgrades_changed refreshes the Tab chevron with the panel open...
	var tab_fire_chevron: Node = equip._slot_icons[0].get_node("UpgradeChevron")
	_check(progress.apply_upgrade(fire, progress.get_upgrade_paths(fire)[0].id), "setup: apply an upgrade with the panel open")
	_check(equip.visible and not tab_fire_chevron.visible, "open Tab panel: slot chevron clears on upgrades_changed")
	await _frames(2)
	_check(not chevron.visible, "HUD chevron disappears once the upgrade is spent")

	# ...and with it closed.
	for i in 10:
		caster.spell_cast.emit(mana)
	equip.show_panel()
	await process_frame
	var tab_mana_chevron: Node = equip._slot_icons[1].get_node("UpgradeChevron")
	_check(tab_mana_chevron.visible, "setup: Tab slot 2 chevron shows at 10 casts")
	equip.hide_panel()
	_check(progress.apply_upgrade(mana, progress.get_upgrade_paths(mana)[0].id), "setup: apply an upgrade with the panel closed")
	_check(not equip.visible and not tab_mana_chevron.visible, "closed Tab panel: slot chevron clears on upgrades_changed")

	# Other SpellIcon users stay overlay-free even when asked.
	var plain := SpellIcon.new()
	root.add_child(plain)
	plain.set_upgrade_available(true)
	_check(not plain.get_node("UpgradeChevron").visible, "icons without the overlay never show the chevron")
	plain.free()

	# Objective row: inside reserved_rect, below the grid, via a real gate.
	var seeded_now: Array = caster.get_slots()
	caster.clear_slot(1)
	caster.assign_slot(4, seeded_now[1])
	var player_loadout: Array = caster.get_slots()
	var objective := hud.get_node("Root/ObjectiveLabel") as Label
	main.area_loader.enter_overworld() # #346: dungeon entrances live in the overworld
	main.area_loader.current_area.get_node("GateNormal")._on_body_entered(player)
	var waited := 0
	while not objective.visible and waited < 1200:
		await process_frame
		waited += 1
	await _frames(4)
	_check(objective.visible and objective.text.begins_with("Objective: CLEAR ALL"), "objective row shows in the dungeon (got '%s')" % objective.text)
	_check(hud.reserved_rect().encloses(objective.get_global_rect()), "reserved_rect includes the objective row")
	_check(not objective.get_global_rect().intersects(squares[5].get_global_rect()), "objective row is clear of the grid")

	# A hub return never reseeds over the player's reassignment.
	main.area_loader._load_hub()
	await _frames(4)
	_check(caster.get_slots() == player_loadout, "hub return keeps the player's slot reassignment")

	# A death restart is the same full reload RunManager performs.
	reload_current_scene()
	await _frames(10)
	var caster2: SpellCaster = current_scene.get_node("Player/SpellCaster")
	_check(caster2 != caster and caster2.get_slots() == _loadout(fire, mana), "restart reseeds slots 1-2 exactly once")
	_check(caster2.get_unlocked().size() == 2, "restart adds no duplicate unlocks (got %d)" % caster2.get_unlocked().size())

	print("[238] RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(1 if failures > 0 else 0)
