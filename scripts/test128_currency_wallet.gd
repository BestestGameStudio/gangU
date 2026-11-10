extends SceneTree
## #128 (foundation C1) harness: run-scoped CurrencyWallet unit contract
## (add/try_spend/clamp/signal), the ONE-persistent Main mount, CURRENCY
## drop routing to the wallet through a REAL RewardDrop walk-over pickup,
## pool REPEAT eligibility for currency (Daniel, 2026-11-07: "Currency
## should be eligible again" - two pickups of the same entry must both pay),
## and the unchanged SPELL route.

var failures := 0
var scene: Node
var p: Player
var wallet: CurrencyWallet
var pool: RewardPool
var signals_seen: Array = []
var phase := 0
var t := 0.0
var centry: RewardEntry
var sentry: RewardEntry
var cdrop: RewardDrop
var sdrop: RewardDrop
var unlocked_before := 0

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[128] ", name, " -> PASS")
	else:
		failures += 1
		print("[128] ", name, " -> FAIL")

func _initialize() -> void:
	# Unit legs: plain wallet, no scene required.
	var w := CurrencyWallet.new()
	root.add_child(w)
	var sig: Array = []
	w.balance_changed.connect(func(b): sig.append(b))
	_check(w.balance() == 0, "fresh wallet balance 0")
	w.add(5)
	_check(w.balance() == 5, "add(5) -> 5")
	_check(sig == [5], "balance_changed emitted once with 5")
	_check(w.try_spend(3) and w.balance() == 2, "try_spend(3) true, balance 2")
	_check(sig == [5, 2], "spend emitted balance_changed 2")
	_check(not w.try_spend(99) and w.balance() == 2, "try_spend(99) false, balance unchanged")
	_check(not w.try_spend(0) and w.balance() == 2, "try_spend(0) false")
	w.add(0)
	w.add(-4)
	_check(w.balance() == 2, "add(0)/add(-4) no-op")
	_check(sig == [5, 2], "no signals from rejected ops")
	w.queue_free()

	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	p = scene.get_node("Player")

func _process(delta: float) -> bool:
	t += delta
	match phase:
		0:
			if scene.current_area == null:
				return false
			# Mount legs: the production wallet exists exactly once, in its
			# group, beside the existing mounts.
			wallet = scene.get_node_or_null("CurrencyWallet") as CurrencyWallet
			_check(wallet != null, "Main mounts CurrencyWallet")
			_check(wallet != null and Run.wallet() == wallet, "Run.wallet() is Main's wallet")
			_check(scene.get_node_or_null("RewardPool") != null, "RewardPool mount intact")
			_check(scene.get_node_or_null("ReviveSatchel") != null, "ReviveSatchel mount intact")
			pool = Run.reward_pool()
			_check(pool != null, "Run.reward_pool() resolves")
			wallet.balance_changed.connect(func(b): signals_seen.append(b))
			var caster: Node = p.get_node("SpellCaster")
			unlocked_before = caster.get_unlocked().size()
			# CURRENCY drop at the player's feet: real walk-over pickup.
			centry = RewardEntry.new()
			centry.kind = RewardEntry.Kind.CURRENCY
			centry.currency_amount = 7
			cdrop = _spawn_drop(centry)
			phase = 1; t = 0
		1:
			if t > 0.6:
				_check(wallet.balance() == 7, "currency pickup routes to wallet (+7)")
				_check(signals_seen == [7], "balance_changed fired with 7")
				_check(not is_instance_valid(cdrop), "currency drop freed after pickup")
				_check(not pool.granted().has(centry), "currency grant does NOT leave run pool")
				_check(pool.is_eligible(centry), "currency entry stays eligible after grant")
				var caster: Node = p.get_node("SpellCaster")
				_check(caster.get_unlocked().size() == unlocked_before, "currency pickup unlocks no spell")
				# Repeat leg: a second drop of the SAME entry must pay again.
				cdrop = _spawn_drop(centry)
				phase = 2; t = 0
		2:
			if t > 0.6:
				_check(wallet.balance() == 14, "repeat pickup of same currency entry pays again (+14)")
				_check(signals_seen == [7, 14], "balance_changed fired for repeat grant")
				_check(not is_instance_valid(cdrop), "repeat currency drop freed after pickup")
				# SPELL route unchanged: same walk-over through a spell entry.
				sentry = RewardEntry.new()
				sentry.kind = RewardEntry.Kind.SPELL
				sentry.spell = load("res://resources/spells/placeholder_bolt.tres")
				sdrop = _spawn_drop(sentry)
				phase = 3; t = 0
		3:
			if t > 0.6:
				var caster: Node = p.get_node("SpellCaster")
				_check(caster.get_unlocked().has(sentry.spell), "SPELL pickup still unlocks via caster")
				_check(wallet.balance() == 14, "SPELL pickup touches no wallet")
				_check(signals_seen == [7, 14], "no wallet signal from SPELL pickup")
				_check(not is_instance_valid(sdrop), "spell drop freed after pickup")
				_check(pool.granted().has(sentry), "SPELL entry still leaves pool on grant")
				return _done()
		_:
			return true
	if t > 8.0:
		_check(false, "timeout in phase %d" % phase)
		return _done()
	return false

func _spawn_drop(entry: RewardEntry) -> RewardDrop:
	var drop: RewardDrop = preload("res://scenes/reward_drop.tscn").instantiate()
	drop.setup(entry)
	scene.current_area.add_child(drop)
	drop.global_position = p.global_position
	return drop

func _done() -> bool:
	if failures == 0:
		print("[128] PASS")
	else:
		print("[128] DONE failures=", failures)
	quit(0 if failures == 0 else 1)
	return true
