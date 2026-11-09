extends SceneTree
## #428 harness: the shop panel has a RELICS section (Daniel 2026-11-09:
## "add a section for relics in the shop UI"). Display only - relic goods
## already in the stock render under RELICS instead of the general rows,
## the section shows an honest empty state when no relic is stocked, and
## stock/prices/buy flow are unchanged (both sections total stock_size).
##
## Rendered runs (xvfb + --write-movie) hold the final state for a few
## frames so it can be screenshotted; headless runs quit the same way.

var failures := 0
var check_count := 0
var caster: SpellCaster
var wallet: CurrencyWallet
var shop: Shop
var panel: ShopPanel
var relics: OwnedRelics
var bolt: Spell = preload("res://resources/spells/placeholder_bolt.tres")
var fireball: Spell = preload("res://resources/spells/fire_ball.tres")
var _frame := 0
var _hold := 0

func _check(cond: bool, name: String) -> void:
	check_count += 1
	if cond:
		print("[428] ", name, " -> PASS")
	else:
		failures += 1
		print("[428] ", name, " -> FAIL")

func _make_player() -> void:
	var p := Player.new()
	p.set_process(false)
	p.set_physics_process(false)
	var aim := Node2D.new()
	aim.name = "AimIndicator"
	p.add_child(aim)
	var bod := Polygon2D.new()
	bod.name = "Body"
	p.add_child(bod)
	var nose := Polygon2D.new()
	nose.name = "NoseEdge"
	p.add_child(nose)
	caster = SpellCaster.new()
	caster.name = "SpellCaster"
	p.add_child(caster)
	p.add_to_group("player")
	p.visible = false
	root.add_child(p)

func _entry(good: Resource, price: int) -> ShopEntry:
	var e := ShopEntry.new()
	e.good = good
	e.price = price
	return e

func _relic(id: StringName, display: String) -> Relic:
	var r := Relic.new()
	r.id = id
	r.display_name = display
	return r

func _rows() -> VBoxContainer:
	return panel.get_node("Backdrop/Margin/VBox/Rows") as VBoxContainer

func _relic_rows() -> VBoxContainer:
	return panel.get_node("Backdrop/Margin/VBox/RelicRows") as VBoxContainer

func _names(box: Control) -> Array:
	var out := []
	for r in box.get_children():
		var labels := r.find_children("*", "Label", true, false)
		if not labels.is_empty():
			out.append(labels[0].text)
	return out

func _build_shop(entries: Array[ShopEntry]) -> void:
	if shop != null:
		shop.free()
	shop = Shop.new()
	var catalog := ShopCatalog.new()
	catalog.entries = entries
	shop.setup(catalog)
	root.add_child(shop)
	panel._shop = shop
	shop.purchased.connect(panel._on_purchased)
	shop.stock_refreshed.connect(panel._on_stock_refreshed)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_run_legs()
	elif _frame > 1:
		_hold += 1
		if _hold == 10:
			_populated_leg() # frames 1-10 show the empty state, 11-20 this one
		if _hold >= 20:
			print("[428] %d checks, %d failures" % [check_count, failures])
			print("RESULT: ALL PASS" if failures == 0 else "RESULT: FAIL")
			quit(0 if failures == 0 else 1)
	return false

func _run_legs() -> void:
	_make_player()
	wallet = CurrencyWallet.new()
	root.add_child(wallet)
	wallet.add(100)
	relics = OwnedRelics.new()
	root.add_child(relics)
	panel = preload("res://scenes/shop_panel.tscn").instantiate()
	root.add_child(panel)

	## 1. Skeleton: RELICS header + container between stock rows and re-roll.
	var vbox := panel.get_node("Backdrop/Margin/VBox")
	var header := vbox.get_node_or_null("RelicHeader") as Label
	_check(header != null and header.text == "RELICS", "RELICS section header exists")
	_check(_relic_rows() != null, "RelicRows container exists")
	_check(_rows().get_index() < header.get_index() and header.get_index() < _relic_rows().get_index()
		and _relic_rows().get_index() < vbox.get_node("RefreshButton").get_index(),
		"order: stock rows, RELICS header, relic rows, re-roll button")

	## 2. No relic in stock: honest empty state, general rows keep 4 slots.
	_build_shop([_entry(fireball, 10), _entry(bolt, 10)])
	panel.open()
	_check(_rows().get_child_count() == 4, "no relics: general rows keep all 4 slots")
	_check(_relic_rows().get_child_count() == 1 and _relic_rows().get_node_or_null("NoRelicsRow") != null,
		"no relics: RELICS shows the empty-state row")
	_check(_relic_rows().find_children("BuyButton", "Button", true, false).is_empty(), "empty state has no buy button")

	## 3. Relic in stock: rendered under RELICS by display name, not in Rows.
	var amulet := _relic(&"test_amulet", "Test Amulet")
	var re := _entry(amulet, 25)
	_build_shop([_entry(fireball, 10), _entry(bolt, 10), re])
	panel._render()
	_check(shop.stock_entries().size() == 3, "stock unchanged: 3 goods drawn (shop logic untouched)")
	_check(_names(_relic_rows()) == ["Test Amulet"], "relic row shows the relic's display name under RELICS")
	_check(not _names(_rows()).has("Test Amulet"), "relic is NOT duplicated among the general rows")
	_check(_rows().get_child_count() + _relic_rows().get_child_count() == shop.stock_size,
		"both sections together render exactly stock_size slots")
	_check(_rows().find_children("OutOfStockLabel", "Label", true, false).size() == 1, "1 OUT OF STOCK sign for the free slot")
	var price := _relic_rows().get_child(0).find_children("*", "Label", true, false)[1] as Label
	_check(price.text == "25c", "relic row shows the catalog price")

	## 4. BUY in the relic section uses the normal atomic buy flow.
	var buy := _relic_rows().find_children("BuyButton", "Button", true, false)
	_check(buy.size() == 1, "relic row has a BUY button")
	buy[0].pressed.emit()
	_check(relics.has_id(&"test_amulet"), "buying grants the relic")
	_check(wallet.balance() == 75, "charged exactly the relic price (100 -> 75)")
	_check(_relic_rows().get_node_or_null("NoRelicsRow") != null, "bought relic leaves; empty state returns")
	_check(_rows().get_child_count() == 4, "general rows back to 4 slots")

func _populated_leg() -> void:
	## 5. Screenshot state: two relics + both spells stocked.
	_build_shop([_entry(fireball, 10), _entry(bolt, 10), _entry(_relic(&"ember_charm", "Ember Charm"), 30), _entry(_relic(&"frost_ring", "Frost Ring"), 40)])
	panel._render()
	_check(_relic_rows().get_child_count() == 2 and _rows().get_child_count() == 2, "4 goods: 2 general rows + 2 relic rows")
