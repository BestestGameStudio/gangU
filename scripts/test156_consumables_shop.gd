extends SceneTree
## #156 harness: shop Consumable dispatch seam. Buy -> Consumables manager
## increment + exact charge; repeat purchases allowed (count-based;
## Daniel's never-sell-owned rule names SPELLS); refusals leave wallet AND
## bag untouched; panel row shows consumable_name; spell path regression.
## Content-free: a harness Consumable definition, no catalog/prices/effects.

var failures := 0
var check_count := 0
var wallet: CurrencyWallet
var caster: SpellCaster
var bag: Consumables
var shop: Shop
var potion: Consumable
var bolt: Spell = preload("res://resources/spells/placeholder_bolt.tres")
var purchases_seen: Array = []
var bag_emissions: Array = []

func _check(cond: bool, name: String) -> void:
	check_count += 1
	if cond:
		print("[156] ", name, " -> PASS")
	else:
		failures += 1
		print("[156] ", name, " -> FAIL")

## Stub player idiom from test129 (test93): real typed Player + real
## SpellCaster child, with the children their @onready lookups need BEFORE
## tree entry.
func _make_player() -> Player:
	var p := Player.new()
	p.name = "StubPlayer"
	p.set_process(false)
	p.set_physics_process(false)
	var aim := Node2D.new()
	aim.name = "AimIndicator"
	p.add_child(aim)
	var bod := Polygon2D.new()
	bod.name = "Body"
	p.add_child(bod)
	var nose := Polygon2D.new() # post-#137 player.gd @onready
	nose.name = "NoseEdge"
	p.add_child(nose)
	caster = SpellCaster.new()
	caster.name = "SpellCaster"
	p.add_child(caster)
	p.add_to_group("player")
	root.add_child(p)
	return p

func _entry(good: Resource, price: int) -> ShopEntry:
	var e := ShopEntry.new()
	e.good = good
	e.price = price
	return e

var _legs_ran := false

## MainLoop._process true = QUIT: return false always; only _done() quits.
func _process(_delta: float) -> bool:
	if _legs_ran:
		return false
	_legs_ran = true
	_run_legs()
	return false

func _run_legs() -> void:
	## Shared fixture: player+caster, Consumables manager, wallet(10),
	## shop [potion(10), bolt(10)]. Manager and wallet enter the tree BEFORE
	## the shop so its group lookups resolve (production mount order).
	_make_player()
	bag = Consumables.new()
	bag.player_path = NodePath("../StubPlayer")
	root.add_child(bag)
	bag.carried_changed.connect(func(c, n): bag_emissions.append([c, n]))
	wallet = CurrencyWallet.new()
	root.add_child(wallet)
	wallet.add(10)
	potion = Consumable.new()
	potion.consumable_name = "Test Potion"
	potion.effect_hook = &"test_heal"
	var pe := _entry(potion, 10)
	var be := _entry(bolt, 10)
	shop = Shop.new()
	var catalog := ShopCatalog.new()
	catalog.entries = [pe, be]
	shop.setup(catalog)
	root.add_child(shop)
	shop.purchased.connect(func(e): purchases_seen.append(e))

	## 1. Offer layer: both goods offerable (consumable can_grant true with
	## a manager present; repeat-purchase rule means ownership never hides it).
	_check(shop.offerable_entries() == [pe, be], "consumable + spell both offerable")

	## 2. Buy consumable: exact charge, bag increment, both signals.
	_check(shop.buy(pe), "buy(consumable) succeeds at exact funds")
	_check(wallet.balance() == 0, "charged exactly the price (10 -> 0)")
	_check(bag.count(potion) == 1, "bag incremented to 1")
	_check(purchases_seen.size() == 1 and purchases_seen[0] == pe, "purchased emitted once with the entry")
	_check(bag_emissions == [[potion, 1]], "carried_changed emitted via the grant")

	## 3. Repeat purchase ALLOWED (count-based; ownership exclusion is spell-only).
	wallet.add(10)
	_check(shop.buy(pe), "repeat consumable buy succeeds")
	_check(bag.count(potion) == 2, "bag incremented to 2")
	_check(shop.offerable_entries() == [pe, be], "consumable STILL offerable after purchase")

	## 4. Insufficient funds: wallet AND bag unchanged, no grant, no signal.
	## (Balance is already 0 after legs 2-3; bag holds 2 potions.)
	var count_before: int = bag.count(potion)
	_check(not shop.buy(pe), "buy with 0 < 10 refused")
	_check(wallet.balance() == 0, "insufficient refusal leaves wallet unchanged")
	_check(bag.count(potion) == count_before, "insufficient refusal leaves bag unchanged")
	_check(purchases_seen.size() == 2, "no purchased emission on refused buy")
	_check(bag_emissions.size() == 2, "no carried_changed on refused buy")

	## 5. Missing manager: consumable can_grant false -> refusal, wallet and
	## bag untouched (manager stays unharmed elsewhere in the tree).
	var shop2 := Shop.new()
	var cat2 := ShopCatalog.new()
	cat2.entries = [pe]
	shop2.setup(cat2)
	root.add_child(shop2)
	shop2._consumables = null # simulate a tree with no Consumables mount
	wallet.add(10)
	_check(not shop2.can_grant(pe.good), "no-manager can_grant refuses consumable")
	_check(not shop2.buy(pe), "no-manager buy refuses")
	_check(wallet.balance() == 10, "no-manager refusal charges nothing")
	_check(bag.count(potion) == count_before, "no-manager refusal adds nothing to the real bag")
	_check(shop2.offerable_entries().is_empty(), "consumable hidden from offers without a manager")
	shop2.queue_free()

	## 6. Panel row label: consumable display name renders, not "Item".
	var panel: ShopPanel = preload("res://scenes/shop_panel.tscn").instantiate()
	root.add_child(panel)
	var row: Control = panel._make_row(pe)
	var name_label: Label = row.find_children("*", "Label", true, false)[0]
	_check(name_label.text == "Test Potion", "panel row shows consumable_name")
	row.free()
	var srow: Control = panel._make_row(be)
	var sname: Label = srow.find_children("*", "Label", true, false)[0]
	_check(sname.text == "Placeholder Bolt", "spell row label unchanged")
	srow.free()
	panel.queue_free()

	## 7. Spell path regression: buy bolt, granted; repeat refused (ownership).
	_check(shop.buy(be), "spell buy still succeeds")
	_check(wallet.balance() == 0, "spell charged exactly 10")
	_check(caster.get_unlocked().has(bolt), "spell granted to caster")
	_check(not shop.buy(be), "repeat spell buy refused (ownership exclusion)")
	_check(shop.offerable_entries() == [pe], "owned spell hidden; consumable remains offerable")

	_done()

func _done() -> bool:
	print("[156] checks=", check_count)
	if failures == 0:
		print("[156] PASS")
	else:
		print("[156] DONE failures=", failures)
	quit(0 if failures == 0 else 1)
	return true
