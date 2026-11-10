extends SceneTree
## #466: every PLAYER spell in the game joins the shop pool at a flat
## price, and each stock shows 3 random picks from that pool (Daniel
## 2026-11-09: "issue: add all spells to the shop pool" / "1. flat
## price" / "2. 3 Random from the pool"). Enemy-only boss spells stay
## OUT (Daniel 2026-11-09: "Do not keep enemy spells"): head_bolt and
## warlord_orb exist only as boss attack projectiles
## (scripts/enemy_behavior_head.gd / enemy_behavior_warlord.gd). Exercises
## the PRODUCTION data (resources/shop/demo_catalog.tres) and the new
## stock_size default. #496 (Colin 2026-11-10): only BASE spells are sold;
## every SpellUpgrade result_spell (e.g. Heavy Rain) stays out.
var failures := 0

var shop: Shop
var panel: ShopPanel
var wallet: CurrencyWallet
var caster: SpellCaster

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("[466] FAIL ", label)
	else:
		print("[466] pass ", label)

func _make_player() -> Player:
	var p := Player.new()
	p.set_process(false)
	p.set_physics_process(false)
	for n in ["AimIndicator", "Body", "NoseEdge"]:
		var c := Polygon2D.new()
		c.name = n
		p.add_child(c)
	var c := SpellCaster.new()
	c.name = "SpellCaster"
	p.add_child(c)
	p.visible = false
	root.add_child(p)
	caster = c
	return p

## Enemy-only attack spells (Daniel 2026-11-09: "Do not keep enemy
## spells"). Each is preloaded ONLY by an enemy behavior as a projectile
## (head_bolt/warlord_orb: boss attacks; mustache_rock: #443 cover-throw
## rock in enemy_behavior_cover); no player path (starting kit, reward
## table, upgrade) grants them.
const ENEMY_ONLY := ["head_bolt.tres", "warlord_orb.tres", "mustache_rock.tres"]

func _spell_files() -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.open("res://resources/spells").get_files():
		if f.ends_with(".tres"):
			out.append(f)
	return out

## #496: spell files that are the RESULT of a SpellUpgrade (upgraded
## variants), derived from the upgrade data - never from names.
func _upgraded_spell_files() -> Dictionary:
	var out := {}
	for f in DirAccess.open("res://resources/upgrades").get_files():
		if f.ends_with(".tres"):
			var up := load("res://resources/upgrades/" + f) as SpellUpgrade
			if up != null and up.result_spell != null:
				out[up.result_spell.resource_path.get_file()] = true
	return out

## Spell resources that BELONG in the shop pool: every spell file minus
## the enemy-only set and (#496) minus every upgraded variant.
func _player_spell_files() -> Array[String]:
	var upgraded := _upgraded_spell_files()
	var out: Array[String] = []
	for f in _spell_files():
		if not ENEMY_ONLY.has(f) and not upgraded.has(f):
			out.append(f)
	return out

func _rows() -> VBoxContainer:
	return panel.get_node("Backdrop/Margin/VBox/Rows") as VBoxContainer

func _oos_count() -> int:
	return _rows().find_children("OutOfStockLabel", "Label", true, false).size()

func _run() -> void:
	## 1. Production pool data: one entry per PLAYER spell resource, flat
	## 10c; the enemy-only boss spells are excluded.
	var demo: ShopCatalog = preload("res://resources/shop/demo_catalog.tres")
	var files := _player_spell_files()
	_check(demo.entries.size() == files.size(),
		"pool holds every BASE player spell resource (%d entries)" % files.size())
	var flat := true
	var seen: Array[Resource] = []
	var present := {}
	for e in demo.entries:
		if not (e.good is Spell) or e.price != 10 or seen.has(e.good):
			flat = false
		seen.append(e.good)
		present[(e.good as Spell).resource_path.get_file()] = true
	_check(flat, "every pool entry is a distinct Spell at the flat price 10")
	for enemy_file in ENEMY_ONLY:
		_check(not present.has(enemy_file),
			"enemy-only spell stays out of the pool: %s" % enemy_file)
	for player_file in files:
		_check(present.has(player_file),
			"player spell is in the pool: %s" % player_file)
	for upgraded_file in _upgraded_spell_files():
		_check(not present.has(upgraded_file),
			"upgraded variant stays out of the pool (#496): %s" % upgraded_file)

	## 2. Production slot count is 3 (Daniel: "3 Random from the pool").
	_check(Shop.new().stock_size == 3, "stock_size default is 3 (#466)")

	## 3. Fresh caster, production catalog: stock is 3 DISTINCT pool spells.
	_make_player()
	wallet = CurrencyWallet.new()
	root.add_child(wallet)
	wallet.add(100)
	shop = Shop.new()
	shop.setup(demo)
	root.add_child(shop)
	var stock := shop.stock_entries()
	_check(stock.size() == 3, "stock draws 3 from the full pool")
	var names: Array[String] = []
	var distinct := true
	for e in stock:
		if names.has(e.good.spell_name):
			distinct = false
		names.append(e.good.spell_name)
	_check(distinct, "the 3 drawn spells are distinct")
	_check(shop.offerable_entries().size() == files.size(),
		"fresh caster: whole pool offerable")

	## 4. Ownership exclusion holds across the full pool: own one spell,
	## re-roll, and it can never surface while the rest remain.
	var owned: Spell = stock[0].good
	caster.unlock_spell(owned)
	shop._reroll_stock()
	_check(shop.offerable_entries().size() == files.size() - 1,
		"owned spell leaves the offerable pool")
	var leaked := false
	for i in range(10):
		shop._reroll_stock()
		for e in shop.stock_entries():
			if e.good == owned:
				leaked = true
	_check(not leaked, "owned spell never rotates back in over 10 re-rolls")
	_check(shop.stock_entries().size() == 3, "stock stays 3 with one owned")

	## 5. Re-rolls actually sample the pool: over 12 draws more than the
	## first 3 names appear (a fixed or broken shuffle cannot do this).
	var all_names := {}
	for e in shop.stock_entries():
		all_names[e.good.spell_name] = true
	for i in range(12):
		shop._reroll_stock()
		for e in shop.stock_entries():
			all_names[e.good.spell_name] = true
	_check(all_names.size() > 3, "re-rolls sample beyond the first draw (%d names seen)" % all_names.size())

	## 6. Buy at the flat price from the full pool: charge 10, grant, the
	## entry leaves the stock, and the pool's ownership exclusion kicks in.
	var buy_entry: ShopEntry = shop.stock_entries()[0]
	_check(shop.buy(buy_entry), "buy a pool spell succeeds")
	_check(wallet.balance() == 90, "charged the flat 10 (100 -> 90)")
	_check(caster.get_unlocked().has(buy_entry.good), "pool spell granted")
	_check(not shop.stock_entries().has(buy_entry), "bought spell leaves the stock")
	_check(not shop.buy(buy_entry), "re-buy of owned pool spell refused")
	_check(wallet.balance() == 90, "refused re-buy charges nothing")

	## 7. Panel renders exactly 3 slots; with the full pool offerable there
	## are no OUT OF STOCK signs.
	panel = preload("res://scenes/shop_panel.tscn").instantiate()
	root.add_child(panel)
	shop._reroll_stock()
	panel.open()
	_check(_rows().get_child_count() == 3, "panel renders exactly 3 slots (#466)")
	_check(_oos_count() == 0, "no OUT OF STOCK signs while the pool is deep")
	panel.close()

	## 8. Shallow end: own all but 2 spells -> 2 rows + 1 OUT OF STOCK sign;
	## own everything -> all 3 slots sign OUT OF STOCK.
	var unowned: Array[Spell] = []
	for e in demo.entries:
		if not caster.has_logical_spell(e.good):
			unowned.append(e.good)
	for i in range(unowned.size() - 2):
		caster.unlock_spell(unowned[i])
	_check(shop.offerable_entries().size() == 2, "setup: exactly 2 spells left offerable")
	shop._reroll_stock()
	_check(shop.stock_entries().size() == 2, "stock holds the 2 remaining spells")
	panel._render()
	_check(_oos_count() == 1, "1 OUT OF STOCK sign for the unfillable slot")
	for e in demo.entries:
		if not caster.has_logical_spell(e.good):
			caster.unlock_spell(e.good)
	shop._reroll_stock()
	_check(shop.stock_entries().is_empty(), "everything owned: stock empty")
	panel._render()
	_check(_oos_count() == 3, "all 3 slots sign OUT OF STOCK when nothing is offerable")

var _legs_ran := false

## Nodes added during _initialize get _ready only after the first frame;
## run the legs on the first _process tick so Shop._ready has fired.
func _process(_delta: float) -> bool:
	if _legs_ran:
		return false
	_legs_ran = true
	_run()
	quit(failures)
	return false
