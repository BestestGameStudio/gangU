extends SceneTree
## #451: upgrade cards in the Tab menu use the border color of the tier they
## upgrade INTO (UiStyle.RANK_COLORS, the #255 palette). Production main scene,
## real fireball/split/leap paths. Saves screenshots when rendered
## (pass a dir after `--`, e.g. `-- /tmp/ci/shots451`).
var failures := 0
var out_dir := ""
func ck(ok: bool, label: String) -> void:
	print("[451] ", label, " -> ", "PASS" if ok else "FAIL")
	if not ok: failures += 1
func cards(panel: EquipPanel) -> Array:
	return panel._upgrade_box.find_children("*", "UpgradeCard", true, false).filter(func(c): return not c.is_queued_for_deletion() and not c.get_parent().is_queued_for_deletion())
func border(card: UpgradeCard, state: String = "normal") -> Color:
	return (card.get_theme_stylebox(state) as StyleBoxFlat).border_color
func shot(file: String) -> void:
	if out_dir != "" and DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png(out_dir.path_join(file))
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: out_dir = args[0]
	# Unit: default card keeps B_ACCENT; set_border_color restyles every state.
	var lone := UpgradeCard.new()
	ck(border(lone) == UiStyle.B_ACCENT, "default card border is still B_ACCENT")
	lone.set_border_color(UiStyle.RANK_COLORS[3])
	ck(border(lone) == UiStyle.RANK_COLORS[3] and border(lone, "hover") == UiStyle.RANK_COLORS[3] and border(lone, "pressed") == UiStyle.RANK_COLORS[3], "set_border_color restyles normal/hover/pressed")
	lone.free()

	root.size = Vector2i(1152, 648)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	for i in 5: await process_frame
	var caster: SpellCaster = main.get_node("Player/SpellCaster")
	var progress: SpellProgress = main.get_node("SpellProgress")
	var panel: EquipPanel = main.get_node("EquipPanel")
	# Tier fallback: a provider path without a tier field reads as Base (silver).
	ck(panel._path_tier(Resource.new()) == 0, "path without tier -> Base")
	var t0 := SpellUpgrade.new(); t0.tier = 0
	ck(panel._path_tier(t0) == 0, "tier 0 path -> Base silver")

	# Base -> Specialization: gold.
	var fire: Spell = load("res://resources/spells/fire_ball.tres")
	panel.show_panel()
	panel._on_slot_pressed(caster.get_slots().find(fire))
	for i in 10: caster.spell_cast.emit(fire)
	panel._refresh()
	for i in 8: await process_frame
	var offered := cards(panel)
	ck(offered.size() == 2, "two fireball cards (got %d)" % offered.size())
	for c: UpgradeCard in offered:
		ck(border(c) == UiStyle.RANK_COLORS[1], "'%s' (Base -> Spec) has the gold border" % c.name_label.text)
	shot("451_spec_gold.png")

	# Specialization -> Mastery: red.
	var split: Spell = load("res://resources/spells/fire_ball_split.tres")
	panel._on_upgrade_pressed(panel._upgrader.get_upgrade_paths(fire)[0].id)
	ck(caster.get_unlocked().has(split), "fireball upgraded into Split")
	panel.hide_panel()
	panel.show_panel()
	panel._on_slot_pressed(caster.get_slots().find(split))
	progress.add_upgrade_token()
	panel._refresh()
	for i in 8: await process_frame
	offered = cards(panel)
	ck(offered.size() >= 1, "split offers mastery cards (got %d)" % offered.size())
	for c: UpgradeCard in offered:
		ck(c.name_label.text.ends_with("[M]") and border(c) == UiStyle.RANK_COLORS[2], "'%s' (Spec -> Mastery) has the red border" % c.name_label.text)
	shot("451_mastery_red.png")

	# Mastery -> Signature: purple (Leaping Hammer -> Dice Roll).
	panel.hide_panel()
	var leap: Spell = load("res://resources/spells/stone_hammer_leap.tres")
	caster.unlock_spell(leap)
	caster.clear_slot(caster.get_slots().find(leap))
	caster.clear_slot(0)
	caster.assign_slot(0, leap)
	panel.show_panel()
	panel._on_slot_pressed(0)
	for i in 30: await process_frame
	offered = cards(panel)
	ck(offered.size() == 1 and offered[0].name_label.text == "Dice Roll [G]", "Dice Roll offered")
	if offered.size() == 1:
		ck(border(offered[0]) == UiStyle.RANK_COLORS[3], "Dice Roll (Mastery -> Signature) has the purple border")
	shot("451_signature_purple.png")
	print("[451] DONE failures=", failures)
	print("RESULT: ALL PASS" if failures == 0 else "RESULT: FAIL")
	quit(failures)
