extends SceneTree
## #129 (foundation C2) harness: hub shop data-driven catalog, ownership
## exclusion (Daniel, 2026-11-07: "Shops should never sell a spell that a
## player already owns" - offer AND purchase layer, refreshes included by
## derivation), ATOMIC pay/grant (no charge without grant: provider refusal
## after precheck refunds IN FULL; no grant attempt when try_spend fails),
## the walk-up panel (Daniel: "yes open a panel") and vendor proximity.

var failures := 0
var check_count := 0
var wallet: CurrencyWallet
var caster: SpellCaster
var shop: Shop
var panel: ShopPanel
var vendor: ShopVendor
var bolt: Spell = preload("res://resources/spells/placeholder_bolt.tres")
var fireball: Spell = preload("res://resources/spells/fire_ball.tres")
var purchases_seen: Array = []

func _check(cond: bool, name: String) -> void:
	check_count += 1
	if cond:
		print("[129] ", name, " -> PASS")
	else:
		failures += 1
		print("[129] ", name, " -> FAIL")

## Stub player: real typed Player + real SpellCaster child, no gameplay
## wiring, so Shop's group lookup and `body is Player` checks work.
func _make_player() -> Player:
	var p := Player.new()
	p.name = "StubPlayer"
	p.set_process(false)
	p.set_physics_process(false)
	# @onready lookups in player.gd/spell_caster.gd need these children
	# present BEFORE tree entry (test93 stub idiom).
	var aim := Node2D.new()
	aim.name = "AimIndicator"
	p.add_child(aim)
	var bod := Polygon2D.new()
	bod.name = "Body"
	p.add_child(bod)
	caster = SpellCaster.new()
	caster.name = "SpellCaster"
	var bg := Polygon2D.new()
	bg.name = "CooldownBarBG"
	caster.add_child(bg)
	var fill := Polygon2D.new()
	fill.name = "CooldownBarFill"
	caster.add_child(fill)
	p.add_child(caster)
	p.add_to_group("player")
	root.add_child(p)
	return p

func _make_wallet(start: int) -> CurrencyWallet:
	wallet = CurrencyWallet.new()
	root.add_child(wallet)
	if start > 0:
		wallet.add(start)
	return wallet

func _make_shop(entries: Array[ShopEntry]) -> Shop:
	shop = Shop.new()
	var catalog := ShopCatalog.new()
	catalog.entries = entries
	shop.setup(catalog)
	root.add_child(shop)
	shop.purchased.connect(func(e): purchases_seen.append(e))
	return shop

func _entry(spell: Spell, price: int) -> ShopEntry:
	var e := ShopEntry.new()
	e.good = spell
	e.price = price
	return e

func _rows() -> VBoxContainer:
	return panel.get_node("Backdrop/Margin/VBox/Rows") as VBoxContainer

func _balance_label() -> Label:
	return panel.get_node("Backdrop/Margin/VBox/BalanceLabel") as Label

var _legs_ran := false

## MainLoop._process true = QUIT: return false always; only _done() quits.
func _process(_delta: float) -> bool:
	if _legs_ran:
		return false
	_legs_ran = true
	_run_legs()
	return false

func _run_legs() -> void:
	## 1. Placeholder catalog DATA leg.
	var demo: ShopCatalog = preload("res://resources/shop/demo_catalog.tres")
	_check(demo.entries.size() == 1, "demo catalog has one entry")
	_check(demo.entries[0].good is Spell and demo.entries[0].good.spell_name == "Placeholder Bolt", "entry good is Placeholder Bolt spell")
	_check(demo.entries[0].price == 10, "entry placeholder price 10")

	## Shared fixture: player+caster, wallet(10), shop [fire_ball, bolt].
	var p := _make_player()
	_make_wallet(10)
	var fe := _entry(fireball, 10)
	var be := _entry(bolt, 10)
	_make_shop([fe, be])

	## 2. Offer layer: both offerable while unowned.
	_check(shop.offerable_entries() == [fe, be], "both spells offerable while unowned")

	## 3. Ownership exclusion (offer layer): owned spell vanishes.
	caster.unlock_spell(fireball)
	_check(shop.offerable_entries() == [be], "owned fire_ball excluded from offers")

	## 4. Ownership exclusion (purchase layer): direct buy of owned refused.
	var bal_before: int = wallet.balance()
	_check(not shop.buy(fe), "buy of OWNED spell refused")
	_check(wallet.balance() == bal_before, "owned-buy refusal leaves balance unchanged")

	## 5. Exact charge + grant on success.
	_check(shop.buy(be), "buy(placeholder_bolt) succeeds at exact funds")
	_check(wallet.balance() == 0, "charged exactly the price (10 -> 0)")
	_check(caster.get_unlocked().has(bolt), "bolt granted to caster")
	_check(purchases_seen.size() == 1 and purchases_seen[0] == be, "purchased emitted once with the entry")

	## 6. Repeat purchase refused (ownership exclusion, not sold-out memory).
	_check(not shop.buy(be), "repeat buy refused after ownership")
	_check(wallet.balance() == 0, "repeat refusal leaves balance unchanged")
	_check(shop.offerable_entries().is_empty(), "nothing offerable once everything owned")

	## 7. Insufficient funds: no charge, NO GRANT ATTEMPT.
	var stub_shop := StubShopCounting.new()
	stub_shop.setup(_catalog_of([be]))
	root.add_child(stub_shop)
	wallet.add(5)
	_check(not stub_shop.buy(be), "buy with 5 < 10 refused")
	_check(wallet.balance() == 5, "insufficient funds leaves balance unchanged")
	_check(stub_shop.grant_calls == 0, "grant NEVER attempted when try_spend fails")
	stub_shop.queue_free()

	## 8. Provider refusal AFTER precheck: full refund, no side effects.
	wallet.add(5) # 10c: enough to charge, so the refund path actually runs
	var fail_shop := StubShopFailing.new()
	fail_shop.setup(_catalog_of([be]))
	root.add_child(fail_shop)
	var sig: Array = []
	wallet.balance_changed.connect(func(b): sig.append(b))
	_check(not fail_shop.buy(be), "failing provider buy returns false")
	_check(wallet.balance() == 10, "REFUND restores balance exactly (10 -> 0 -> 10)")
	_check(sig == [0, 10], "balance_changed nets back to the starting value")
	_check(fail_shop.grant_calls == 1, "grant was attempted once before refusing")
	_check(purchases_seen.size() == 1, "no purchased emission on refunded buy")
	fail_shop.queue_free()

	## 9. Invalid entries refuse cleanly.
	var bad := ShopEntry.new()
	_check(not shop.buy(bad), "null good refuses")
	var freebie := _entry(bolt, 0)
	_check(not shop.buy(freebie), "zero price refuses")

	## 10. Panel: hidden by default, outside modal_ui. Fresh player so the
	## shop's caster and the offers start unowned again.
	panel = preload("res://scenes/shop_panel.tscn").instantiate()
	root.add_child(panel)
	_check(not panel.visible, "panel hidden by default")
	_check(not panel.is_in_group("modal_ui"), "panel not modal while hidden")

	p.queue_free()
	p = _make_player()
	shop._caster = caster # re-point the shop at the fresh caster
	_check(shop.offerable_entries() == [fe, be], "fresh caster: both spells offerable again")

	## 11. Panel render on open: offerable rows only + balance text.
	panel.open()
	_check(panel.visible and panel.is_in_group("modal_ui"), "open: visible + modal_ui")
	_check(_rows().get_child_count() == 2, "two offerable rows rendered")
	_check(_balance_label().text == "Wallet: 10c", "balance label shows wallet (10c)")

	## 12. Buy via the panel button: row drops, grant lands, balance updates.
	wallet.add(10) # 20c
	var btn: Button = _rows().get_child(0).find_children("*", "Button", true, false)[0]
	btn.pressed.emit() # buy fire_ball (row 0) for 10c
	_check(caster.get_unlocked().has(fireball), "panel buy granted fire_ball")
	_check(wallet.balance() == 10, "panel buy charged exactly 10 (20 -> 10)")
	_check(_rows().get_child_count() == 1, "bought row removed (ownership exclusion)")
	_check(_balance_label().text == "Wallet: 10c", "balance label updated after panel buy")

	## 12b. Panel buy with insufficient funds: no change anywhere.
	wallet.try_spend(10) # drain to 0 (direct harness setup, not a buy)
	btn = _rows().get_child(0).find_children("*", "Button", true, false)[0]
	btn.pressed.emit() # bolt costs 10, wallet has 0
	_check(not caster.get_unlocked().has(bolt), "insufficient panel buy grants nothing")
	_check(wallet.balance() == 0, "insufficient panel buy charges nothing")
	_check(_rows().get_child_count() == 1, "unaffordable row remains")

	## 12c. Everything owned: empty-state hint renders.
	caster.unlock_spell(bolt)
	panel._render()
	_check(_rows().get_node_or_null("EmptyHint") != null, "empty-state hint when nothing offerable")

	## 13. Vendor proximity: walk-up opens, walk-away closes.
	vendor = preload("res://scenes/shop_vendor.tscn").instantiate()
	root.add_child(vendor)
	panel.close()
	vendor._on_body_entered(p)
	_check(panel.visible and panel.is_in_group("modal_ui"), "vendor walk-up opens panel")
	vendor._on_body_exited(p)
	_check(not panel.visible and not panel.is_in_group("modal_ui"), "vendor walk-away closes panel")
	var stranger := Node2D.new()
	vendor._on_body_entered(stranger)
	_check(not panel.visible, "non-player body does not open panel")
	stranger.free()

	## 14. Production mount: main.tscn wires the Shop with a RESOLVED caster
	## (explicit caster_path; the group fallback alone finds no player).
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var prod_shop: Shop = scene.get_node_or_null("Shop") as Shop
	_check(prod_shop != null, "main.tscn mounts Shop")
	_check(prod_shop != null and prod_shop._caster != null, "production Shop caster RESOLVED via caster_path")
	_check(prod_shop != null and not prod_shop.offerable_entries().is_empty(), "production shop offers the placeholder bolt")
	scene.queue_free()

	_done()

func _catalog_of(entries: Array[ShopEntry]) -> ShopCatalog:
	var c := ShopCatalog.new()
	c.entries = entries
	return c

func _done() -> bool:
	print("[129] checks=", check_count)
	if failures == 0:
		print("[129] PASS")
	else:
		print("[129] DONE failures=", failures)
	quit(0 if failures == 0 else 1)
	return true

## Stub provider: can_grant always true, grant always FALSE - the provider
## refusal-after-precheck leg (atomic refund).
class StubShopFailing extends Shop:
	var grant_calls := 0
	func can_grant(_good: Resource) -> bool:
		return true
	func grant(_good: Resource) -> bool:
		grant_calls += 1
		return false

## Stub provider: can_grant true, grant counts calls and succeeds silently.
class StubShopCounting extends Shop:
	var grant_calls := 0
	func can_grant(_good: Resource) -> bool:
		return true
	func grant(_good: Resource) -> bool:
		grant_calls += 1
		return true
