extends SceneTree
## #694: the Sand General's reward drops after the death animation. If the
## player leaves the arena (area swap frees it) before that, the reward must
## not be lost: coins and the upgrade token are credited straight to the run.

var failures := 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[statue reward exit] ", label, " -> ", "PASS" if ok else "FAIL")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var wallet := CurrencyWallet.new()
	root.add_child(wallet)
	Run.register(wallet)
	var progress := SpellProgress.new()
	progress.add_to_group("spell_progress")
	root.add_child(progress)
	var area := Node2D.new()
	root.add_child(area)
	var player: Player = load("res://game/player/player.tscn").instantiate()
	player.name = "Player"
	area.add_child(player)
	player.set_physics_process(false)
	var region := Node2D.new()
	area.add_child(region)
	var arena := DesertStatueArena.new()
	region.add_child(arena)
	arena.set_physics_process(false)
	arena.start_encounter()
	var coins_before := wallet.balance()
	var tokens_before := progress.upgrade_tokens()
	var victory: int = arena.victory_coins

	arena.apply_damage(arena.hp)
	await process_frame
	_check(wallet.balance() == coins_before, "nothing is credited while the animation plays")
	# Leave the area mid-death: the arena (and its drop parent) is freed.
	area.queue_free()
	await process_frame
	await process_frame
	_check(wallet.balance() == coins_before + victory, "coins are credited when the arena is left mid-death")
	_check(progress.upgrade_tokens() == tokens_before + 1, "the upgrade token is credited too")
	# The orphaned timer must not pay a second time.
	await create_timer(DesertStatue.death_animation_seconds() + 0.2, false).timeout
	_check(wallet.balance() == coins_before + victory, "no double payout when the timer fires later")
	print("[statue reward exit] DONE failures=", failures)
	quit(1 if failures > 0 else 0)
