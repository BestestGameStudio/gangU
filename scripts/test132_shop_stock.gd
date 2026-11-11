extends SceneTree
## #132 harness: shop STOCK + refresh rules. 4 slots drawn distinct from
## the offerable (non-owned) set; free refresh on dungeon victory; paid
## re-roll at the data-driven Fibonacci schedule 1,2,3,5,8,13,21...;
## victory resets the paid price; refusals charge NOTHING; panel renders
## exactly 4 slots with OUT OF STOCK signs and a priced RE-ROLL button.
## Content-free: harness Spell/Consumable definitions, no production data.

var failures := 0
var check_count := 0
var wallet: CurrencyWallet
var caster: SpellCaster
var bag: Consumables
var shop: Shop
var refreshes_seen := 0

func _check(cond: bool, name: String) -> void:
	check_count += 1
	if cond:
		print("[132] ", name, " -> PASS")
	else:
		failures += 1
		print("[132] ", name, " -> FAIL")

## Stub player idiom from test129/test156: real typed Player + real
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
	root.add_child(p)
	return p

func _entry(good: Resource, price: int) -> ShopEntry:
	var e := ShopEntry.new()
	e.good = good
	e.price = price
	return e

func _distinct(entries: Array) -> bool:
	var seen := {}
	for e in entries:
		if seen.has(e):
			return false
		seen[e] = true
	return true

func _subset(stock: Array, offerable: Array) -> bool:
	for e in stock:
		if not offerable.has(e):
			return false
	return true

var _legs_ran := false

## MainLoop._process true = QUIT: return false always; only _done() quits.
func _process(_delta: float) -> bool:
	if _legs_ran:
		return false
	_legs_ran = true
	_run_legs()
	return false

func _run_legs() -> void:
	seed(1234)

	## 0. Schedule unit checks: default seeds give Daniel's confirmed
	## Fibonacci continuation; other seeds prove the curve is data-driven.
	var sched := ShopRefreshSchedule.new()
	var seq: Array[int] = []
	for i in range(7):
		seq.append(sched.price_at(i))
	_check(seq == [1, 2, 3, 5, 8, 13, 21], "default schedule is 1,2,3,5,8,13,21")
	var custom := ShopRefreshSchedule.new()
	custom.first_price = 5
	custom.second_price = 7
	_check(custom.price_at(0) == 5 and custom.price_at(1) == 7 and custom.price_at(2) == 12 and custom.price_at(3) == 19, "custom seeds continue by summing (5,7,12,19)")

	## Shared fixture: player+caster, Consumables manager, wallet. Manager
	## and wallet enter the tree BEFORE the shop (production mount order).
	_make_player()
	bag = Consumables.new()
	bag.player_path = NodePath("../StubPlayer")
	root.add_child(bag)
	wallet = CurrencyWallet.new()
	root.add_child(wallet)

	## Catalog: 6 harness spells + 1 harness consumable, all price 10.
	var spells: Array[Spell] = []
	var entries: Array[ShopEntry] = []
	for i in range(6):
		var s := Spell.new()
		s.mode = Spell.CastMode.PROJECTILE
		s.spell_name = "Harness Spell %d" % (i + 1)
		spells.append(s)
		entries.append(_entry(s, 10))
	var potion := Consumable.new()
	potion.consumable_name = "Harness Potion"
	potion.effect_hook = &"test_heal"
	var potion_entry := _entry(potion, 10)
	entries.append(potion_entry)
	var catalog := ShopCatalog.new()
	catalog.entries = entries

	shop = Shop.new()
	shop.stock_size = 4 # #132 slot mechanics pinned at 4; #466's production default is 3
	shop.setup(catalog)
	shop.stock_refreshed.connect(func(): refreshes_seen += 1)
	root.add_child(shop) # _ready draws the initial stock
	refreshes_seen = 0 # discount the initial draw's emission; count re-rolls only

	## 1. Initial stock: exactly 4 slots (Daniel), distinct, all offerable.
	var stock := shop.stock_entries()
	_check(stock.size() == 4, "initial stock fills 4 slots")
	_check(_distinct(stock), "initial stock entries are distinct")
	_check(_subset(stock, shop.offerable_entries()), "initial stock drawn from offerable (non-owned) set")
	_check(shop.paid_refresh_price() == 1, "first paid refresh priced at schedule seed 1")
	_check(shop.can_paid_refresh(), "re-roll available while undisplayed goods exist")

	## 2. Paid sequence: exact Fibonacci charges 1, 2, 3, 5.
	wallet.add(1000)
	var balance := wallet.balance()
	var expected := [1, 2, 3, 5]
	for price in expected:
		var before := wallet.balance()
		_check(shop.buy_paid_refresh(), "paid refresh at %d succeeds" % price)
		_check(wallet.balance() == before - price, "charged exactly %d" % price)
	_check(shop.paid_refresh_price() == 8, "after 4 buys the next price is 8")
	_check(shop.stock_entries().size() == 4, "stock refills to 4 after re-rolls")
	_check(_distinct(shop.stock_entries()), "re-rolled stock stays distinct")
	_check(refreshes_seen == 4, "stock_refreshed emitted once per paid re-roll")
	balance = wallet.balance()

	## 3. Insufficient funds: NOTHING changes - wallet, counter, stock,
	## emissions all frozen.
	var spend_ok := wallet.try_spend(wallet.balance() - 3) # leave 3 < price 8
	_check(spend_ok, "fixture: drain wallet to 3")
	var frozen_stock := shop.stock_entries()
	var frozen_emissions := refreshes_seen
	_check(not shop.buy_paid_refresh(), "paid refresh at 8 with 3c refused")
	_check(wallet.balance() == 3, "refusal leaves wallet unchanged")
	_check(shop.paid_refresh_price() == 8, "refusal does not advance the counter")
	_check(shop.stock_entries() == frozen_stock, "refusal leaves stock untouched")
	_check(refreshes_seen == frozen_emissions, "no stock_refreshed on refused re-roll")

	## 4. Victory: FREE re-roll (no charge) and the paid price resets.
	shop.on_dungeon_victory()
	_check(wallet.balance() == 3, "victory refresh charges nothing")
	_check(shop.paid_refresh_price() == 1, "victory resets the paid price to 1")
	_check(refreshes_seen == frozen_emissions + 1, "victory emits stock_refreshed")
	_check(shop.stock_entries().size() == 4, "victory refills the stock")
	_check(shop.buy_paid_refresh(), "post-victory paid refresh succeeds")
	_check(wallet.balance() == 2, "post-victory charge is the reset price 1")
	_check(shop.paid_refresh_price() == 2, "counter climbs again from the reset")

	## 5. Buying removes the good from the stock; an OWNED spell can never
	## rotate back in (ownership exclusion, including refreshed stock).
	wallet.add(100)
	var bought: ShopEntry = shop.stock_entries()[0]
	while not (bought.good is Spell): # pick a spell slot deterministically
		bought = shop.stock_entries()[shop.stock_entries().find(bought) + 1]
	_check(shop.buy(bought), "buying a stocked spell succeeds")
	_check(not shop.stock_entries().has(bought), "bought entry leaves the stock")
	_check(caster.get_unlocked().has(bought.good), "bought spell granted to caster")
	shop.on_dungeon_victory() # re-roll with the spell now owned
	_check(not shop.stock_entries().has(bought), "owned spell never rotates back into stock")
	_check(not shop.offerable_entries().has(bought), "owned spell leaves the offerable set")

	## 6. Consumables stay re-purchasable through the stock (#156 seam).
	_check(shop.can_grant(potion), "consumable grantable")
	_check(shop.buy(potion_entry), "consumable buy succeeds")
	_check(shop.buy(potion_entry), "repeat consumable buy succeeds (re-purchasable)")
	_check(bag.count(potion) == 2, "bag counted both consumable buys")
	_check(shop.offerable_entries().has(potion_entry), "consumable remains offerable after purchase")

	## 7. Panel: exactly 4 slot rows, OUT OF STOCK signs for unfillable
	## slots, priced RE-ROLL button, live re-render on stock_refreshed.
	## (Leg 5's victory reset the counter; one paid re-roll re-arms it so
	## the live reset below is observable on the button.)
	_check(shop.buy_paid_refresh(), "pre-panel paid re-roll succeeds at reset price 1")
	_check(shop.paid_refresh_price() == 2, "counter re-armed to price 2")
	var panel: ShopPanel = preload("res://scenes/shop_panel.tscn").instantiate()
	root.add_child(panel)
	panel.open()
	_check(panel._rows.get_child_count() == 4, "panel renders exactly 4 slot rows")
	var oos := panel.find_children("OutOfStockLabel", "Label", true, false)
	_check(oos.size() == 4 - shop.stock_entries().size(), "one OUT OF STOCK sign per unfillable slot")
	_check(panel._refresh_button.text == "RE-ROLL STOCK (2c)", "re-roll button shows the current price")
	_check(not panel._refresh_button.disabled, "re-roll button enabled while re-roll useful")
	var old_first_row := panel._rows.get_child(0)
	shop.on_dungeon_victory() # visible panel re-renders live from the signal
	_check(panel._refresh_button.text == "RE-ROLL STOCK (1c)", "victory reset shows on the button live")
	_check(panel._rows.get_child(0) != old_first_row, "visible panel re-rendered on stock_refreshed")
	_check(panel._rows.get_child_count() == 4, "panel still renders 4 slots after victory")
	panel.free()
	shop.free()

	## 8. Out-of-stock shop: 1-spell catalog. One stocked slot + 3 signs;
	## re-roll refused (every offerable good already displayed); after the
	## only good sells, all 4 slots sign OUT OF STOCK and re-roll stays
	## refused with ZERO charge.
	var solo := Shop.new()
	var solo_catalog := ShopCatalog.new()
	var lone_spell := Spell.new()
	lone_spell.mode = Spell.CastMode.PROJECTILE
	lone_spell.spell_name = "Lone Harness Spell"
	var lone_entry := _entry(lone_spell, 10)
	solo_catalog.entries = [lone_entry]
	solo.stock_size = 4 # pinned at the #132 slot count, not the #466 default
	solo.setup(solo_catalog)
	root.add_child(solo)
	_check(solo.stock_entries() == [lone_entry], "single-good catalog stocks its one good")
	_check(not solo.can_paid_refresh(), "re-roll refused when all offerable goods are displayed")
	var panel2: ShopPanel = preload("res://scenes/shop_panel.tscn").instantiate()
	root.add_child(panel2)
	panel2.open()
	_check(panel2._rows.get_child_count() == 4, "small catalog still renders 4 slots")
	_check(panel2.find_children("OutOfStockLabel", "Label", true, false).size() == 3, "3 OUT OF STOCK signs beside the one good")
	_check(panel2._refresh_button.disabled, "re-roll button disabled when re-roll is useless")
	var funds_before := wallet.balance()
	_check(not solo.buy_paid_refresh(), "useless re-roll refused")
	_check(wallet.balance() == funds_before, "useless re-roll charges nothing")
	wallet.add(10)
	_check(solo.buy(lone_entry), "buying the only good succeeds")
	_check(solo.stock_entries().is_empty(), "stock empties after the only good sells")
	_check(panel2.find_children("OutOfStockLabel", "Label", true, false).size() == 4, "all 4 slots sign OUT OF STOCK when no eligible item")
	_check(not solo.buy_paid_refresh(), "re-roll refused with nothing offerable")
	_check(wallet.balance() == funds_before, "empty-shop re-roll charges nothing")
	panel2.free()
	solo.free()

	_done()

func _done() -> bool:
	print("[132] checks=", check_count)
	if failures == 0:
		print("[132] PASS")
	else:
		print("[132] DONE failures=", failures)
	quit(0 if failures == 0 else 1)
	return true
