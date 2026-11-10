extends SceneTree
## #449 harness (SHOP half - the tab-menu half is blocked by #431): relic
## rows in the shop are ICON ONLY, with the relic's name and description in
## the RelicIcon hover tooltip; the placeholder is ONE shared code-drawn
## diamond for every relic (Daniel 2026-11-09: "just use the same
## placeholder for all relics"). Run:
## godot --headless --path . -s scripts/test449_shop_relic_icons.gd

var failures := 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("[449] ", label, " -> PASS")
	else:
		failures += 1
		print("[449] ", label, " -> FAIL")

func _relic(id: StringName, display: String, desc: String = "") -> Relic:
	var r := Relic.new()
	r.id = id
	r.display_name = display
	r.description = desc
	return r

var _frame := 0
var _twin: Relic

func _initialize() -> void:
	# (1) Relic carries a description (the hover "desc" text's home).
	_twin = load("res://resources/relics/twin_dash.tres")
	_check(_twin.description != "", "(1) catalog relic (Twin Dash) has a description")

	# (2) Tooltip contract: name only when no description, name + desc otherwise.
	var plain := RelicIcon.new()
	plain.show_relic(_relic(&"a", "Plain Relic"))
	_check(plain.tooltip_text == "Plain Relic", "(2) tooltip is the name when there is no description")
	plain.free()
	var rich := RelicIcon.new()
	rich.show_relic(_relic(&"b", "Rich Relic", "Does a thing."))
	_check(rich.tooltip_text == "Rich Relic\nDoes a thing.", "(2) tooltip is name + description on hover")
	_check(rich.mouse_filter != Control.MOUSE_FILTER_IGNORE, "(2) icon accepts hover (mouse_filter not IGNORE)")
	rich.free()
	# (2b) ID-only relic (valid: nonempty id, empty display_name): the id is
	# the identity line, with or without a description; fully blank -> "Relic".
	var bare := RelicIcon.new()
	bare.show_relic(_relic(&"probe_relic", ""))
	_check(bare.tooltip_text == "probe_relic", "(2b) ID-only tooltip falls back to the id (got '%s')" % bare.tooltip_text)
	bare.show_relic(_relic(&"probe_relic", "", "Probe text."))
	_check(bare.tooltip_text == "probe_relic\nProbe text.", "(2b) ID-only + desc keeps an id first line (got '%s')" % bare.tooltip_text)
	bare.show_relic(_relic(&"", ""))
	_check(bare.tooltip_text == "Relic", "(2b) no id and no name -> generic 'Relic'")
	bare.free()

	# (3) ONE shared placeholder for every relic: same draw colors, no per-relic art.
	_check(RelicIcon.PLACEHOLDER_FILL.is_equal_approx(Color(0.85, 0.62, 0.20)), "(3) shared placeholder color")
	var src := FileAccess.get_file_as_string("res://scripts/relic_icon.gd")
	_check(not src.contains("preload") and not src.contains("load("), "(3) placeholder is drawn in code, no art files")
	_check(not src.contains("_relic") or not src.contains("PLACEHOLDER_FILL = ") , "(3) placeholder never varies per relic")

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame > 1:
		return false
	# (4) Shop relic rows are icon-only; spell rows keep SpellIcon + name label.
	var panel: ShopPanel = preload("res://scenes/shop_panel.tscn").instantiate()
	root.add_child(panel)
	var wallet := CurrencyWallet.new()
	root.add_child(wallet)
	wallet.add(100)
	var relics := OwnedRelics.new()
	root.add_child(relics)
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

	var shop := Shop.new()
	var catalog := ShopCatalog.new()
	var e_spell := ShopEntry.new()
	e_spell.good = load("res://resources/spells/fire_ball.tres")
	e_spell.price = 10
	var e_relic := ShopEntry.new()
	e_relic.good = _twin
	e_relic.price = 25
	# Valid stockable ID-only probe (nonempty id, empty display_name): its
	# tooltip must keep an identity line, not show only the description.
	var probe := _relic(&"probe_relic", "", "Probe text.")
	var e_probe := ShopEntry.new()
	e_probe.good = probe
	e_probe.price = 5
	catalog.entries = [e_spell, e_relic, e_probe]
	shop.setup(catalog)
	root.add_child(shop)
	panel._shop = shop
	shop.purchased.connect(panel._on_purchased)
	shop.stock_refreshed.connect(panel._on_stock_refreshed)
	panel.open()
	await process_frame

	var relic_rows := panel.get_node("Backdrop/Margin/VBox/RelicRows") as VBoxContainer
	var all_icons := relic_rows.find_children("*", "RelicIcon", true, false)
	_check(all_icons.size() == 2, "(4) one RelicIcon per stocked relic (got %d)" % all_icons.size())
	var icons := all_icons.filter(func(i): return (i as RelicIcon).tooltip_text.begins_with("Twin Dash"))
	var probe_icons := all_icons.filter(func(i): return not (i as RelicIcon).tooltip_text.begins_with("Twin Dash"))
	_check(probe_icons.size() == 1 and (probe_icons[0] as RelicIcon).tooltip_text == "probe_relic\nProbe text.", "(4b) ID-only stocked relic keeps an id identity line (got %s)" % [probe_icons.map(func(i): return (i as RelicIcon).tooltip_text)])
	_check(shop.can_grant(probe), "(4b) ID-only probe is a valid, grantable relic")
	if icons.size() == 1:
		var icon := icons[0] as RelicIcon
		_check(icon.tooltip_text == "Twin Dash\nGrants a second dash charge.", "(4) relic tooltip is name + desc (got '%s')" % icon.tooltip_text)
		_check(icon.custom_minimum_size == Vector2(UiStyle.ICON_SIZE, UiStyle.ICON_SIZE), "(4) relic icon matches the spell-icon size")
		var row: Node = icon
		while row != null and not (row is PanelContainer):
			row = row.get_parent()
		var name_labels := 0
		if row != null:
			for l in row.find_children("*", "Label", true, false):
				if (l as Label).text == "Twin Dash":
					name_labels += 1
		_check(name_labels == 0, "(4) relic row has NO name label (icon only)")
		_check(row != null and row.find_children("BuyButton", "Button", true, false).size() == 1, "(4) relic row keeps its BUY button")

	# (5) Buy flow intact: buying the relic still works from the icon-only row.
	_check(shop.can_grant(e_relic.good), "(5) relic still purchasable")
	_check(shop.buy(e_relic) and relics.has_id(&"twin_dash"), "(5) buy flow grants the relic")

	# (6) Spell rows unchanged: SpellIcon plus a name label.
	var rows := panel.get_node("Backdrop/Margin/VBox/Rows") as VBoxContainer
	var spell_icons := rows.find_children("*", "SpellIcon", true, false)
	_check(spell_icons.size() >= 1, "(6) general rows still use SpellIcon")

	print("[449] failures=%d" % failures)
	print("[449] ALL PASS" if failures == 0 else "[449] FAILURES PRESENT")
	quit(failures)
	return false
