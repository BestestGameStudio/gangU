class_name Shop
extends Node
## (#129, foundation C2) Hub shop: data-driven catalog + atomic pay/grant.
## Daniel (2026-11-07): the walk-up vendor opens a choice PANEL; goods are
## spells/consumables/relics; shops NEVER sell a spell the player already
## owns - OWNERSHIP exclusion, including refreshed stock (C5 rotates among
## non-owned entries only). The offerable set is DERIVED (catalog minus
## owned), so no run-scoped sold-out memory lives here. Mounted once on
## Main (wallet/pool pattern); per-run reset comes free from the reload.
##
## (#132, foundation C5) STOCK + REFRESH. The panel shows a STOCK of
## stock_size slots (Daniel 2026-11-08: "show 4 slots for now") drawn
## without replacement from the offerable set; a slot with no eligible
## item renders an OUT OF STOCK sign (same message). Buying removes the
## entry from the stock. Refresh rules (Daniel 2026-11-07/08, verbatim):
## - FREE refresh on confirmed dungeon VICTORY only (Main calls
##   on_dungeon_victory from DungeonObjective.objective_completed) - never
##   on a plain return to hub.
## - PAID refresh ("players can also buy a refresh"): buy_paid_refresh
##   charges the current schedule price and re-rolls; "each bought
##   refresh costs extra" via the data-driven ShopRefreshSchedule
##   (Fibonacci 1,2,3,5,8,13,21... - "fibonacci yeah").
## - "yes refresh the paid price": victory ALSO resets the paid counter
##   to the schedule's first value.
## - Run-start reset comes free from RunManager's full scene reload, the
##   same pattern as the wallet/satchel (this node rebuilds fresh).
## A paid refresh is REFUSED (no charge) when no re-roll could surface a
## new good - every offerable entry is already in stock, or none exist.
##
## ATOMIC PAY/GRANT (no charge without grant, no grant without charge):
##   1. can_grant precheck - pure read, no side effects.
##   2. wallet.try_spend(price) - false aborts before any grant attempt.
##   3. grant(good) - a FALSE return refunds the price IN FULL.
## grant() is all-or-nothing: false means ZERO side effects. The precheck
## is an optimization, never the atomicity mechanism. buy_paid_refresh is
## simpler: the "grant" is the re-roll itself, so a refused spend is the
## only failure path and leaves EVERYTHING (wallet, counter, stock) as-is.
##
## C3/C4 PROVIDER SEAM: can_grant/grant dispatch on the good's TYPE. Spell
## goods compose the strict-primitive caster from the outside
## (get_unlocked / unlock_spell - the caster gains no shop methods).
## Consumables dispatch to the #130 Consumables manager (#156); relic
## branches return false until their grant seam lands.

signal purchased(entry: ShopEntry)
## Emitted after any stock re-roll - free (victory) or paid. The panel
## re-renders from it so the price/reset is visible without reopening.
signal stock_refreshed()

## Explicit wiring convention (matches SpellProgress/HUD): set before tree
## entry; the Player.find fallback applies otherwise.
@export var caster_path: NodePath
## #131: optional explicit provider; lazy resolution supports later mount.
@export var owned_relics_path: NodePath
## (#132) Slots the panel renders. Daniel 2026-11-08: "show 4 slots for
## now" - SUPERSEDED by #466 (Daniel 2026-11-09): with every spell in
## the pool, a stock shows "3 Random from the pool", so the slot count
## is 3. Data, not a constant, so the count stays human-tunable.
@export var stock_size: int = 3
## (#132) Paid-refresh price schedule. Null falls back to a default
## ShopRefreshSchedule (1, 2 seeds) so harnesses need no .tres; production
## wires resources/shop/demo_refresh_schedule.tres from main.gd.
@export var refresh_schedule: ShopRefreshSchedule

var _catalog: ShopCatalog
var _wallet: CurrencyWallet
var _caster: SpellCaster
var _consumables: Consumables
var _stock: Array[ShopEntry] = []
var _paid_refresh_count: int = 0

func setup(catalog: ShopCatalog) -> void:
	_catalog = catalog

func _ready() -> void:
	add_to_group("shop")
	_wallet = get_tree().get_first_node_in_group("currency_wallet") as CurrencyWallet
	_consumables = get_tree().get_first_node_in_group("consumables") as Consumables
	if caster_path != NodePath(""):
		_caster = get_node_or_null(caster_path) as SpellCaster
	if _caster == null:
		var player := Player.find(get_tree())
		if player != null:
			_caster = player.get_node_or_null("SpellCaster") as SpellCaster
	if refresh_schedule == null:
		refresh_schedule = ShopRefreshSchedule.new()
	if _wallet == null:
		push_warning("Shop: no currency_wallet group node; all buys refuse.")
	if _caster == null:
		push_warning("Shop: no player SpellCaster found; spell grants refuse.")
	if _consumables == null:
		push_warning("Shop: no consumables group node; consumable grants refuse.")
	_reroll_stock()

## Catalog entries the player can currently buy: valid, priced, and not
## already owned (ownership exclusion, Daniel 2026-11-07).
func offerable_entries() -> Array[ShopEntry]:
	var out: Array[ShopEntry] = []
	if _catalog == null:
		return out
	for e in _catalog.entries:
		if e != null and e.good != null and e.price > 0 and can_grant(e.good):
			out.append(e)
	return out

## (#132) The current stock, in slot order, filtered to goods the player
## can still be granted: a spell that became owned AFTER the draw (e.g. a
## #10 ground pickup) never displays, per Daniel's never-sell-owned pin
## "including refreshed stock". A copy - callers cannot mutate the shop's
## state through it.
func stock_entries() -> Array[ShopEntry]:
	var out: Array[ShopEntry] = []
	for e in _stock:
		if e != null and e.good != null and can_grant(e.good):
			out.append(e)
	return out

## (#132) Price of the NEXT paid refresh (schedule index = paid count).
func paid_refresh_price() -> int:
	return refresh_schedule.price_at(_paid_refresh_count)

## (#132) A paid re-roll makes sense only if it could surface a good not
## already on display. When every offerable entry is already in stock (or
## nothing is offerable at all) the refresh is refused - charging for a
## guaranteed no-op would read as a bug in the demo.
func can_paid_refresh() -> bool:
	for e in offerable_entries():
		if not _stock.has(e):
			return true
	return false

## (#132) Paid re-roll. Charges the current schedule price ONLY; on a
## refused spend nothing changes (wallet, counter, stock all untouched).
func buy_paid_refresh() -> bool:
	if not can_paid_refresh():
		return false
	var price := paid_refresh_price()
	if _wallet == null or not _wallet.try_spend(price):
		return false
	_paid_refresh_count += 1
	_reroll_stock()
	return true

## (#132) Dungeon victory: FREE re-roll and the paid price resets to the
## schedule's first value (Daniel: "yes refresh the paid price"). Called
## by Main from DungeonObjective.objective_completed - victory only,
## never a plain hub return. Never charges the wallet.
func on_dungeon_victory() -> void:
	_paid_refresh_count = 0
	_reroll_stock()

## (#132) Re-roll: draw up to stock_size DISTINCT entries from the current
## offerable set (rotation among non-owned only). Fewer eligible goods
## than slots leaves empty slots - the panel signs those OUT OF STOCK.
## (#466) The pool holds every PLAYER spell in the game: the demo catalog
## lists all resources/spells/*.tres at a flat 10c EXCEPT the enemy-only
## boss spells (head_bolt, warlord_orb - Daniel 2026-11-09: "Do not keep
## enemy spells"), so each stock is Daniel's "3 Random from the pool";
## ownership exclusion still applies per-draw.
## (#496, Colin 2026-11-10) NARROWED: only BASE spells are sold. Any spell
## that is a SpellUpgrade result_spell (resources/upgrades/*.tres, e.g.
## Heavy Rain) is an upgraded variant earned through use and is left out
## of the catalog; test496/test466/test129 enforce this from upgrade data.
func _reroll_stock() -> void:
	var pool := offerable_entries()
	pool.shuffle()
	_stock.clear()
	for e in pool.slice(0, stock_size):
		_stock.append(e)
	stock_refreshed.emit()

func _relic_provider() -> OwnedRelics:
	if owned_relics_path != NodePath(""):
		return get_node_or_null(owned_relics_path) as OwnedRelics
	return get_tree().get_first_node_in_group("owned_relics") as OwnedRelics

func can_grant(good: Resource) -> bool:
	if good is Spell:
		return _caster != null and not _caster.has_logical_spell(good)
	if good is Consumable:
		# #156: consumables are count-based and RE-PURCHASABLE; Daniel's
		# never-sell-owned rule names spells, so no ownership exclusion here.
		return _consumables != null
	if good is Relic:
		# #131 (C4): relics are unique per logical id from EVERY source -
		# owned ids are never offered or granted again.
		var owned := _relic_provider()
		return owned != null and (good as Relic).is_valid_definition() and not owned.has_id((good as Relic).id)
	return false

func grant(good: Resource) -> bool:
	if good is Spell:
		if not can_grant(good):
			return false
		_caster.unlock_spell(good)
		return true
	if good is Consumable:
		if _consumables == null:
			return false
		_consumables.add(good)
		return true
	if good is Relic:
		# buy()'s refund path covers a failed add after charge; offerable
		# and stock filtering both route through can_grant above.
		if not can_grant(good):
			return false
		return _relic_provider().add(good)
	return false

## Atomic purchase. Returns true only when the good was granted AND paid
## for; every failure path leaves the wallet exactly as it started.
func buy(entry: ShopEntry) -> bool:
	if entry == null or entry.good == null or entry.price <= 0:
		return false
	if not can_grant(entry.good):
		return false
	if _wallet == null or not _wallet.try_spend(entry.price):
		return false
	if not grant(entry.good):
		_wallet.add(entry.price) # refund: grant failed after charge
		return false
	_stock.erase(entry) # (#132) the bought good leaves the stock
	purchased.emit(entry)
	return true
