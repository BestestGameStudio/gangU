extends SceneTree
## #449 harness (TAB-MENU half): the Tab menu's relics section (#427/#431)
## lists owned relics as RelicIcon - icon only, name + description in the
## hover tooltip, ONE shared placeholder (Daniel 2026-11-09). Run:
## godot --headless --path . -s scripts/test449_tab_relic_icons.gd

var failures := 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("[449t] ", label, " -> PASS")
	else:
		failures += 1
		print("[449t] ", label, " -> FAIL")

func _initialize() -> void:
	var p := Player.new()
	p.set_process(false)
	p.set_physics_process(false)
	for n in ["AimIndicator", "Body", "NoseEdge"]:
		var c := Polygon2D.new()
		c.name = n
		p.add_child(c)
	var caster := SpellCaster.new()
	caster.name = "SpellCaster"
	p.add_child(caster)
	p.add_to_group("player")
	p.visible = false
	root.add_child(p)
	var owned := OwnedRelics.new()
	root.add_child(owned)

	var panel: EquipPanel = preload("res://scenes/equip_panel.tscn").instantiate()
	root.add_child(panel)
	await process_frame
	panel.show_panel()
	await process_frame

	var list := panel.get_node_or_null("RelicsBox/RelicsList")
	if list == null:
		list = panel.find_child("RelicsList", true, false)
	_check(list != null, "(1) relics list exists")

	# (2) Empty run: honest placeholder, no icons.
	_check(list.find_child("RelicsEmpty", true, false) != null, "(2) empty run shows the placeholder line")
	_check(panel.relic_names().is_empty(), "(2) no relic names on an empty run")

	# (3) Two owned relics: icons only, tooltips carry name (+desc), order kept.
	var a := Relic.new()
	a.id = &"moss_charm"
	a.display_name = "Moss Charm"
	a.description = "A mossy charm."
	var b := Relic.new()
	b.id = &"basalt_idol"
	b.display_name = "Basalt Idol"
	owned.add(a)
	owned.add(b)
	await process_frame
	var icons := list.find_children("*", "RelicIcon", true, false)
	_check(icons.size() == 2, "(3) one icon per owned relic (got %d)" % icons.size())
	_check(panel.relic_names() == PackedStringArray(["Moss Charm", "Basalt Idol"]), "(3) acquisition order kept: %s" % [panel.relic_names()])
	if icons.size() == 2:
		_check((icons[0] as RelicIcon).tooltip_text == "Moss Charm\nA mossy charm.", "(3) tooltip carries name + desc on hover")
		_check((icons[1] as RelicIcon).tooltip_text == "Basalt Idol", "(3) tooltip falls back to name when desc is empty")
	var name_labels := 0
	for l in list.find_children("*", "Label", true, false):
		if (l as Label).text in ["Moss Charm", "Basalt Idol"]:
			name_labels += 1
	_check(name_labels == 0, "(3) NO name labels in the relics list (icon only)")

	# (4) Shared placeholder: same colors as the shop's RelicIcon (one class, one draw).
	_check(RelicIcon.PLACEHOLDER_FILL.is_equal_approx(Color(0.85, 0.62, 0.20)), "(4) tab menu uses the same shared placeholder")

	# (5) Live update: a relic gained while the menu is open appears.
	var c := Relic.new()
	c.id = &"third"
	c.display_name = "Third Relic"
	owned.add(c)
	await process_frame
	_check(panel.relic_names() == PackedStringArray(["Moss Charm", "Basalt Idol", "Third Relic"]), "(5) section stays live")

	print("[449t] failures=%d" % failures)
	print("[449t] ALL PASS" if failures == 0 else "[449t] FAILURES PRESENT")
	quit(failures)
