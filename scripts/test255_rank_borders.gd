extends SceneTree
## #255 rank borders: every owned spell icon on the HUD grid and the Tab panel
## carries a code-drawn border whose color/shape follows its
## SpellProgress tier (Base silver, Specialization gold, Mastery red,
## Signature purple). Empty slots, the shop and the spell directory show none;
## the border draws above the wipe and chevron and fits the panel icon gap.

const SIDE := 48.0

var failures := 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("[255] ", label, " -> PASS")
	else:
		failures += 1
		print("[255] ", label, " -> FAIL")

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _border(icon: SpellIcon) -> SpellRankBorder:
	return icon.get_node("RankBorder") as SpellRankBorder

func _initialize() -> void:
	root.size = Vector2i(1152, 648)

	# A. Palette and per-tier shape on a free icon.
	_check(UiStyle.RANK_COLORS.size() == 4, "four rank colors")
	var silver: Color = UiStyle.RANK_COLORS[0]
	var gold: Color = UiStyle.RANK_COLORS[1]
	var red: Color = UiStyle.RANK_COLORS[2]
	var purple: Color = UiStyle.RANK_COLORS[3]
	_check(absf(silver.r - silver.b) < 0.1 and silver.v > 0.7 and silver.s < 0.15, "Base is silver (light, desaturated)")
	_check(gold.r > gold.g and gold.g > gold.b and gold.s > 0.6, "Specialization is gold")
	_check(red.r > 0.7 and red.g < 0.3 and red.b < 0.3, "Mastery is red")
	_check(purple.b > purple.g and purple.r > purple.g and purple.s > 0.5, "Signature is purple")

	var free := SpellIcon.new(SIDE, true)
	root.add_child(free)
	await process_frame
	var fb := _border(free)
	_check(fb != null and not fb.visible and free.rank_tier() == SpellRankBorder.NONE, "default icon has no rank border")
	_check(fb.get_index() > free.get_node("UpgradeChevron").get_index() and fb.get_index() > free.get_node("CooldownWipe").get_index(), "border draws above wipe and chevron")
	_check(fb.mouse_filter == Control.MOUSE_FILTER_IGNORE, "border ignores the mouse")
	var last_overhang := 0.0
	for t in 4:
		free.set_rank_tier(t)
		_check(fb.visible and fb.tier == t and fb.color() == UiStyle.RANK_COLORS[t], "tier %d shows its color" % t)
		_check(fb.overhang() > last_overhang, "tier %d is bigger/fancier than the tier below (%.0f px)" % [t, fb.overhang()])
		last_overhang = fb.overhang()
	_check(is_equal_approx(fb.unit(), 2.0), "HUD squares use a 2 px unit")
	free.set_rank_tier(9)
	_check(fb.tier == 3, "tiers above Signature clamp to Signature")
	free.set_rank_tier(SpellRankBorder.NONE)
	_check(not fb.visible, "NONE hides the border")
	free.free()

	var small := SpellIcon.new()
	root.add_child(small)
	await process_frame
	small.set_rank_tier(3)
	_check(is_equal_approx(_border(small).unit(), 1.0), "22 px icons use a 1 px unit")
	_check(_border(small).overhang() <= EquipPanel.ICON_GAP, "Signature fits within the panel icon gap (%.0f <= %.0f)" % [_border(small).overhang(), EquipPanel.ICON_GAP])
	small.free()

	# B. Production wiring.
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(30) # past the HUD's provider discovery
	var hud: HUD = main.get_node("HUD")
	var caster: SpellCaster = main.get_node("Player/SpellCaster")
	var progress: SpellProgress = main.get_node("SpellProgress")
	var equip: EquipPanel = main.get_node("EquipPanel")
	var fire: Spell = load("res://resources/spells/fire_ball.tres")
	var grid := hud.get_node("Root/SpellGrid") as GridContainer
	var squares: Array = grid.get_children()
	var hud_overhang := 3.0 * 2.0 # Signature at the 2 px HUD unit
	_check(grid.get_theme_constant("h_separation") > 2.0 * hud_overhang and grid.get_theme_constant("v_separation") > 2.0 * hud_overhang,
		"HUD grid gaps keep neighbouring Signature borders apart")
	_check(hud.get_node("Root").get_theme_constant("separation") > hud_overhang, "Signature gem clears the HP bar")
	_check(squares[0].rank_tier() == 0 and squares[1].rank_tier() == 0, "HUD starters show the Base (silver) border")
	var empties_bare := true
	for i in range(2, 6):
		empties_bare = empties_bare and squares[i].rank_tier() == SpellRankBorder.NONE and not _border(squares[i]).visible
	_check(empties_bare, "HUD empty slots show no border")

	# A real upgrade: the result spell takes the slot and shows Specialization.
	for i in 10:
		caster.spell_cast.emit(fire)
	_check(progress.apply_upgrade(fire, progress.get_upgrade_paths(fire)[0].id), "setup: apply fire's first upgrade")
	await _frames(2)
	var spec: Spell = caster.get_slots()[0]
	_check(spec != fire and progress.get_tier(spec) == 1, "setup: slot 1 holds the tier-1 result")
	_check(squares[0].rank_tier() == 1, "HUD slot 1 shows the Specialization (gold) border")
	caster._cooldowns[spec] = 1000.0
	await _frames(2)
	_check(squares[0].get_node("CooldownWipe").visible and _border(squares[0]).visible, "border stays visible during a cooldown wipe")
	caster._cooldowns[spec] = 0.0

	# Higher tiers through the same accessor.
	progress._tiers[spec] = 2
	await _frames(2)
	_check(squares[0].rank_tier() == 2, "HUD follows Mastery (red)")
	progress._tiers[spec] = 3
	await _frames(2)
	_check(squares[0].rank_tier() == 3, "HUD follows Signature (purple)")

	# Tab panel: rows and slots match the HUD; empty slots stay bare.
	equip.show_panel()
	await _frames(2)
	_check(equip._slot_icons[0].rank_tier() == 3, "Tab slot 1 shows Signature")
	_check(equip._slot_icons[1].rank_tier() == 0, "Tab slot 2 shows Base")
	_check(equip._slot_icons[2].rank_tier() == SpellRankBorder.NONE, "Tab empty slot shows none")
	var row_tiers := {}
	for c in equip._unlocked_box.get_children():
		if c is Button:
			var icons: Array = c.find_children("SpellIcon", "TextureRect", true, false)
			row_tiers[c.text] = icons[0].rank_tier()
	_check(row_tiers.get(spec.spell_name) == 3, "Tab row for the upgraded spell shows Signature (got %s)" % str(row_tiers))
	_check(row_tiers.get("Mana Shot") == 0, "Tab row for Mana Shot shows Base")
	equip.hide_panel()

	# Unowned-spell surfaces never drive a rank.
	for path in ["res://scripts/shop_panel.gd", "res://scripts/spell_directory_panel.gd"]:
		var src := FileAccess.get_file_as_string(path)
		_check(src.find("set_rank_tier") == -1, "%s shows no rank border" % path.get_file())

	print("[255] RESULT: ", "ALL PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(1 if failures > 0 else 0)
