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
## ATOMIC PAY/GRANT (no charge without grant, no grant without charge):
##   1. can_grant precheck - pure read, no side effects.
##   2. wallet.try_spend(price) - false aborts before any grant attempt.
##   3. grant(good) - a FALSE return refunds the price IN FULL.
## grant() is all-or-nothing: false means ZERO side effects. The precheck
## is an optimization, never the atomicity mechanism.
##
## C3/C4 PROVIDER SEAM: can_grant/grant dispatch on the good's TYPE. Spell
## goods compose the strict-primitive caster from the outside
## (get_unlocked / unlock_spell - the caster gains no shop methods).
## Consumable/relic branches return false until their grant seams land.

signal purchased(entry: ShopEntry)

var _catalog: ShopCatalog
var _wallet: CurrencyWallet
var _caster: SpellCaster

func setup(catalog: ShopCatalog) -> void:
	_catalog = catalog

func _ready() -> void:
	add_to_group("shop")
	_wallet = get_tree().get_first_node_in_group("currency_wallet") as CurrencyWallet
	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		_caster = player.get_node_or_null("SpellCaster") as SpellCaster
	if _wallet == null:
		push_warning("Shop: no currency_wallet group node; all buys refuse.")
	if _caster == null:
		push_warning("Shop: no player SpellCaster found; spell grants refuse.")

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

func can_grant(good: Resource) -> bool:
	if good is Spell:
		return _caster != null and not _caster.get_unlocked().has(good)
	return false # C3/C4 consumable/relic grant seams land here

func grant(good: Resource) -> bool:
	if good is Spell:
		if not can_grant(good):
			return false
		_caster.unlock_spell(good)
		return true
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
	purchased.emit(entry)
	return true
