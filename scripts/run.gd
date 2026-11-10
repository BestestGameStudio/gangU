class_name Run
extends Object
## (#520) The one typed owner of shared run state. Replaces the string-group
## lookups ("currency_wallet", "owned_relics", "reward_pool") that callers
## used to find the run services Main mounts.
##
## Static-only, never instantiated and NOT an autoload: each service adds
## itself here when it enters the tree and removes itself when it leaves. A
## death restart (RunManager's full scene reload) frees Main and its
## children, so the old run's services drop out before the new run's mount,
## and nothing here can outlive a reload.
##
## Lookup semantics match the old get_first_node_in_group: no service in the
## tree gives null, and if a harness mounts two at once the one earliest in
## tree order wins.
##
## Usage: Run.wallet(), Run.relics(), Run.reward_pool().

static var _wallets: Array[Node] = []
static var _relics: Array[Node] = []
static var _pools: Array[Node] = []

static func wallet() -> CurrencyWallet:
	return _first(_wallets) as CurrencyWallet

static func relics() -> OwnedRelics:
	return _first(_relics) as OwnedRelics

static func reward_pool() -> RewardPool:
	return _first(_pools) as RewardPool

## Called from a service's _enter_tree.
static func register(service: Node) -> void:
	var list := _list_for(service)
	if not list.has(service):
		list.append(service)

## Called from a service's _exit_tree.
static func unregister(service: Node) -> void:
	_list_for(service).erase(service)

## Unknown types get a throwaway list (and an error), so nothing is stored.
static func _list_for(service: Node) -> Array[Node]:
	if service is CurrencyWallet:
		return _wallets
	if service is OwnedRelics:
		return _relics
	if service is RewardPool:
		return _pools
	push_error("Run: %s is not a run service" % service)
	var none: Array[Node] = []
	return none

static func _first(list: Array[Node]) -> Node:
	var best: Node = null
	for n in list:
		if not is_instance_valid(n) or not n.is_inside_tree():
			continue
		if best == null or best.is_greater_than(n):
			best = n
	return best
