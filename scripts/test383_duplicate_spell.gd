extends SceneTree
## #383 harness: one logical spell per run across every acquisition source
## (RewardDrop with distinct entries, SpellPickup, shop, direct grants), also
## after the base was upgraded. Refusals must not charge currency, consume the
## pool entry as granted, emit a grant, or mutate state. Different spells and
## fresh-run acquisition stay normal.
var failures := 0
var hammer: Spell = preload("res://resources/spells/placeholder_bolt.tres") ## a different spell
var other: Spell = preload("res://resources/spells/stone_hammer.tres")
var reaper: Spell = preload("res://resources/spells/stone_hammer_reaper.tres")
var up_a: SpellUpgrade = preload("res://resources/upgrades/hammer_reaper.tres")
var unlock_count := 0
var wallet: CurrencyWallet
var caster: SpellCaster
var player: Player
var progress: SpellProgress

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[383] ", name, " -> PASS")
	else:
		failures += 1
		print("[383] ", name, " -> FAIL")

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
	var nose := Polygon2D.new()
	nose.name = "NoseEdge"
	p.add_child(nose)
	caster = SpellCaster.new()
	caster.name = "SpellCaster"
	p.add_child(caster)
	p.add_to_group("player")
	root.add_child(p)
	caster.spell_unlocked.connect(func(_s): unlock_count += 1)
	return p

func _entry(spell: Spell) -> RewardEntry:
	var e := RewardEntry.new()
	e.kind = RewardEntry.Kind.SPELL
	e.spell = spell
	return e

func _drop(entry: RewardEntry) -> RewardDrop:
	var d := (load("res://scenes/reward_drop.tscn") as PackedScene).instantiate() as RewardDrop
	d.setup(entry)
	root.add_child(d)
	return d

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	player = _make_player()
	wallet = CurrencyWallet.new()
	root.add_child(wallet)
	wallet.add(100)
	progress = SpellProgress.new()
	progress.caster_path = caster.get_path()
	progress.upgrades.append(up_a)
	root.add_child(progress)
	await process_frame

	# Direct grants.
	caster.unlock_spell(other)
	_check(caster.get_unlocked().has(other), "first grant succeeds")
	var n := caster.get_unlocked().size()
	caster.unlock_spell(other)
	caster.add_spell(other)
	_check(caster.get_unlocked().count(other) == 1, "direct duplicate unlock/add_spell leave exactly one copy")
	_check(caster.get_unlocked().size() == n and caster.spells.is_empty(), "refusals leave inventory unchanged")
	var emitted := unlock_count
	caster.unlock_spell(other)
	_check(unlock_count == emitted, "refusal emits no spell_unlocked")
	caster.unlock_spell(hammer)
	_check(caster.get_unlocked().has(hammer), "a different spell still grants")

	# Distinct reward entries for the same spell.
	var e1 := _entry(other)
	var e2 := _entry(other)
	var pool := RewardPool.new()
	var table := RewardTable.new()
	var arr: Array[RewardEntry] = [e1, e2]
	table.entries = arr
	pool.setup(table)
	root.add_child(pool)
	await process_frame
	n = caster.get_unlocked().size()
	var emitted_before_drop := unlock_count
	var d2 := _drop(e2)
	d2._on_body_entered(player)
	_check(caster.get_unlocked().size() == n, "distinct reward entry for a held spell grants nothing")
	_check(not pool.granted().has(e2), "refused drop does not record a pool grant")
	_check(unlock_count == emitted_before_drop, "refused drop emits no spell_unlocked")

	# Base re-acquisition after upgrade.
	_check(caster.replace_spell(other, reaper), "upgrade swaps base for result")
	_check(not caster.unlocked.has(other), "base no longer literally held")
	n = caster.get_unlocked().size()
	var pk := (load("res://scenes/spell_pickup.tscn") as PackedScene).instantiate() as SpellPickup
	pk.spell = other
	root.add_child(pk)
	pk._on_body_entered(player)
	_check(caster.get_unlocked().size() == n, "fresh base pickup after upgrade grants nothing")
	var held_after := caster.get_unlocked().size()
	var d3 := _drop(_entry(other))
	d3._on_body_entered(player)
	_check(caster.get_unlocked().size() == n and not caster.get_unlocked().has(other), "reward drop of base after upgrade grants nothing")

	# Fresh run (new caster) acquires normally.
	player.remove_from_group("player")
	var p2 := _make_player()
	caster.unlock_spell(other)
	_check(caster.get_unlocked().has(other), "fresh run caster acquires the spell again")

	# Shop on a caster whose base was upgraded: no charge, no grant.
	caster.replace_spell(other, reaper)
	var shop := Shop.new()
	var catalog := ShopCatalog.new()
	var se := ShopEntry.new()
	se.good = other
	se.price = 10
	var es: Array[ShopEntry] = [se]
	catalog.entries = es
	shop.setup(catalog)
	root.add_child(shop)
	await process_frame
	var bal := wallet.balance()
	var held := caster.get_unlocked().size()
	shop.buy(se)
	_check(wallet.balance() == bal, "shop refuses base after upgrade without charging")
	_check(caster.get_unlocked().size() == held and not caster.get_unlocked().has(other), "shop refusal grants nothing")
	print("test383 done: ", failures, " failures")
	quit(1 if failures > 0 else 0)
