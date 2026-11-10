extends SceneTree
## #427 harness: relics section at the bottom of the Tab (spell) menu
## (Daniel, 2026-11-09: "on the spell tab add a section for relics on the
## bottom").
##  - The section exists, is the LAST block of the menu and sits below the
##    slots / stat grid.
##  - Empty run: a placeholder line, no relic names.
##  - Owned relics are listed by name in acquisition order; a relic gained
##    while the menu is open shows up live.
## Run: godot --headless --path . -s scripts/test427_relics_section.gd

var failures := 0

func _check(cond: bool, name: String) -> void:
	if not cond:
		failures += 1
	print("[427] ", name, " -> ", "PASS" if cond else "FAIL")

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _relic(id: StringName, display: String) -> Relic:
	var r := Relic.new()
	r.id = id
	r.display_name = display
	r.hooked_tags = [SpellTags.EARTH]
	return r

func _initialize() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	root.add_child(vp)
	current_scene = vp
	var stage := Node2D.new()
	stage.name = "Stage"
	vp.add_child(stage)
	await process_frame

	var player: Player = load("res://scenes/player.tscn").instantiate()
	stage.add_child(player)
	await _frames(2)

	var panel: EquipPanel = load("res://scenes/equip_panel.tscn").instantiate()
	panel.player_path = NodePath("../Player")
	stage.add_child(panel)
	# Production order: OwnedRelics mounts AFTER the panel (main.gd).
	var relics := OwnedRelics.new()
	relics.name = "OwnedRelics"
	stage.add_child(relics)
	await _frames(2)
	panel.show_panel()
	await _frames(3)

	var box := panel.find_child("RelicsBox", true, false) as VBoxContainer
	_check(box != null, "RelicsBox exists in the Tab menu")
	if box == null:
		quit(1)
		return
	var header := box.get_node("RelicsHeader") as Label
	_check(header != null and header.text == "Relics", "section header reads 'Relics'")
	var body := box.get_parent()
	_check(box.get_index() == body.get_child_count() - 1, "relics section is the last block of the menu")
	_check(box.get_global_rect().position.y >= panel._slots_box.get_global_rect().end.y, "relics sit below the slots")
	var grid := panel.find_child("StatsBox", true, false) as Control
	_check(grid != null and box.get_global_rect().position.y >= grid.get_global_rect().end.y, "relics sit below the stat grid")

	# Empty state.
	_check(panel.relic_names().is_empty(), "no relic names on an empty run")
	_check(box.find_child("RelicsEmpty", true, false) != null, "empty-state placeholder shown")

	# Gained while open: live, in acquisition order.
	_check(relics.add(_relic(&"t427_a", "Moss Charm")), "first relic added")
	_check(relics.add(_relic(&"t427_b", "Basalt Idol")), "second relic added")
	await _frames(2)
	_check(panel.relic_names() == PackedStringArray(["Moss Charm", "Basalt Idol"]), "owned relics listed live in order: %s" % [panel.relic_names()])
	_check(box.find_child("RelicsEmpty", true, false) == null, "placeholder gone once a relic is owned")
	_check(not relics.add(_relic(&"t427_a", "Moss Charm")), "duplicate refused by OwnedRelics")
	await _frames(1)
	_check(panel.relic_names().size() == 2, "duplicate not listed twice")

	# Survives close/reopen and still sits at the bottom with a selection open.
	panel.hide_panel()
	panel.show_panel()
	await _frames(2)
	_check(panel.relic_names().size() == 2, "relics still listed after reopening")
	var caster: SpellCaster = player.get_node("SpellCaster")
	var slots: Array = caster.get_slots()
	var first := slots.find_custom(func(s): return s != null)
	if first != -1:
		panel._on_slot_pressed(first)
		await _frames(3)
		_check(box.get_index() == body.get_child_count() - 1, "relics stay last with a spell selected")
	print("RESULT: ", "ALL PASS" if failures == 0 else "%d FAIL" % failures)
	quit(0 if failures == 0 else 1)
