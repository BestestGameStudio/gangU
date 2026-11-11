extends SceneTree
## #520 harness: Run is the typed owner of shared run state.
##  - Run.wallet()/relics()/reward_pool() resolve Main's mounts.
##  - The services no longer join the old string groups.
##  - A service leaving the tree leaves Run (nothing survives a free).
##  - Two mounts at once: the earliest in tree order wins (old group rule).
##  - A full scene reload (death restart) hands Run the NEW run's services.

var _checks := 0
var _failures := 0

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("[520] ", label, " -> ", "PASS" if ok else "FAIL")

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	# --- Unit: register/unregister and tree order --------------------------
	_check(Run.wallet() == null and Run.relics() == null and Run.reward_pool() == null, "empty tree: all accessors null")
	var a := CurrencyWallet.new()
	var b := CurrencyWallet.new()
	root.add_child(a)
	root.add_child(b)
	_check(Run.wallet() == a, "two wallets: first in tree order wins")
	root.move_child(b, 0)
	_check(Run.wallet() == b, "tree order, not mount order, decides")
	b.free()
	_check(Run.wallet() == a, "freed wallet drops out of Run")
	root.remove_child(a)
	_check(Run.wallet() == null, "wallet removed from tree is not reachable")
	root.add_child(a)
	_check(Run.wallet() == a, "re-entering the tree registers again")
	a.free()
	var not_in_tree := OwnedRelics.new()
	_check(Run.relics() == null, "service never mounted is not reachable")
	not_in_tree.free()

	# --- Production mount ---------------------------------------------------
	change_scene_to_file("res://game/core/main.tscn")
	for i in 10:
		await process_frame
	var main := current_scene
	_check(main != null and main.get_node_or_null("CurrencyWallet") != null, "main.tscn booted")
	var wallet := main.get_node("CurrencyWallet") as CurrencyWallet
	var relics := main.get_node("OwnedRelics") as OwnedRelics
	var pool := main.get_node("RewardPool") as RewardPool
	_check(Run.wallet() == wallet, "Run.wallet() is Main's CurrencyWallet")
	_check(Run.relics() == relics, "Run.relics() is Main's OwnedRelics")
	_check(Run.reward_pool() == pool, "Run.reward_pool() is Main's RewardPool")
	_check(get_nodes_in_group("currency_wallet").is_empty(), "no currency_wallet group joins")
	_check(get_nodes_in_group("owned_relics").is_empty(), "no owned_relics group joins")
	_check(get_nodes_in_group("reward_pool").is_empty(), "no reward_pool group joins")
	wallet.add(7)
	_check(Run.wallet().balance() == 7, "accessor reaches live run state")

	# --- Full reload (the death-restart path) -------------------------------
	reload_current_scene()
	for i in 10:
		await process_frame
	var next := current_scene
	_check(next != null and next != main, "scene reloaded")
	_check(Run.wallet() != null and Run.wallet() == next.get_node("CurrencyWallet"), "Run.wallet() follows the new run")
	_check(Run.wallet().balance() == 0, "new run's wallet starts at 0")
	_check(Run.relics() == next.get_node("OwnedRelics"), "Run.relics() follows the new run")
	_check(Run.reward_pool() == next.get_node("RewardPool"), "Run.reward_pool() follows the new run")
	_check(Run._wallets.size() == 1 and Run._relics.size() == 1 and Run._pools.size() == 1, "old run's services left Run")

	print("[520] %d checks, %d failures" % [_checks, _failures])
	print("RESULT: ALL PASS" if _failures == 0 else "RESULT: FAIL")
	quit(0 if _failures == 0 else 1)
