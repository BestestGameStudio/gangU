extends SceneTree
## #264 harness: currency is part of the enemy loot table used by the current
## dungeons (DungeonA, DungeonB, the generated dungeon). #465 (Daniel,
## 2026-11-09: "remove spells from the regular mob loot tables (they should
## only drop currency)"; bosses/beasts keep theirs, other sources unchanged)
## made the regular-mob table currency-ONLY. Proves:
##  - the production demo_table.tres carries a CURRENCY entry (positive
##    placeholder amount, positive weight) and NO spell entries;
##  - every current dungeon's enemies use that table;
##  - the table still rolls currency after grants (currency stays eligible,
##    #128), so enemies keep dropping it;
##  - end to end on Main: a real enemy carrying the production table dies,
##    drops currency, walk-over pickup adds the amount to the run wallet, and
##    a second kill drops currency again.
## Amounts/weights are placeholder content; only presence is asserted.

const TABLE_PATH := "res://resources/rewards/demo_table.tres"

var failures := 0
var scene: Node
var p: Player
var pool: RewardPool
var wallet: CurrencyWallet
var table: RewardTable
var currency_entry: RewardEntry
var enemy: Enemy
var kills := 0
var balance_before := 0
var phase := 0
var t := 0.0

func _check(cond: bool, name: String) -> void:
	if not cond:
		failures += 1
	print("[264] ", name, " -> ", "PASS" if cond else "FAIL")

func _static_checks() -> void:
	table = load(TABLE_PATH)
	_check(table != null, "demo table loads")
	var spell_names := []
	for e in table.entries:
		if e.kind == RewardEntry.Kind.CURRENCY:
			currency_entry = e
		elif e.kind == RewardEntry.Kind.SPELL:
			spell_names.append(e.spell.spell_name)
	_check(currency_entry != null, "demo table carries a CURRENCY entry")
	_check(currency_entry != null and currency_entry.currency_amount > 0 and currency_entry.weight > 0.0,
		"currency entry has a positive amount and weight")
	_check(spell_names.is_empty(), "no spell entries: regular mobs drop currency only (#465)")
	_check(table.entries.size() == 1 and table.entries[0].kind == RewardEntry.Kind.CURRENCY, "the currency entry is the whole table (#465)")

	for path in ["res://scenes/dungeon_a.tscn", "res://scenes/dungeon_b.tscn"]:
		var area: Node = load(path).instantiate()
		var sd: AreaSpawnData = area.get_node_or_null("SpawnData")
		var all_ok: bool = sd != null and not sd.entries.is_empty()
		if sd != null:
			for entry in sd.entries:
				var rt: RewardTable = entry.get("reward_table")
				if rt == null or rt.resource_path != TABLE_PATH:
					all_ok = false
		_check(all_ok, "%s enemies use the currency-bearing table" % path.get_file())
		area.free()
	var gen: Script = load("res://scripts/generated_dungeon.gd")
	var rt: RewardTable = gen.get_script_constant_map().get("REWARD_TABLE")
	_check(rt != null and rt.resource_path == TABLE_PATH, "generated dungeon enemies use the currency-bearing table")

	# #465: with a currency-only table every roll is currency; the pool
	# keeps CURRENCY eligible after grants (#128), so drops repeat (the
	# second kill below proves it end to end).
	var only_currency := true
	for i in 50:
		if table.roll([]) != currency_entry:
			only_currency = false
	_check(only_currency, "the table always rolls currency")

func _spawn_enemy() -> void:
	enemy = load("res://scenes/enemy.tscn").instantiate()
	enemy.position = Vector2(576, 300)
	enemy.player_path = NodePath("../../Player")
	enemy.reward_table = table
	scene.current_area.add_child(enemy)

func _initialize() -> void:
	_static_checks()
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	p = scene.get_node("Player")

func _finish() -> bool:
	print("RESULT: ", "ALL PASS" if failures == 0 else "%d FAILED" % failures)
	quit(0 if failures == 0 else 1)
	return true

func _process(delta: float) -> bool:
	t += delta
	match phase:
		0:
			if scene.current_area == null:
				return false
			pool = get_first_node_in_group("reward_pool") as RewardPool
			wallet = get_first_node_in_group("currency_wallet") as CurrencyWallet
			_check(pool != null and wallet != null, "Main mounts reward pool and wallet")
			if pool == null or wallet == null or currency_entry == null:
				return _finish()
			# #465: the production table is currency-only, so no grant
			# priming is needed - every roll is currency already.
			_spawn_enemy()
			phase = 1; t = 0
		1:
			if t > 0.3:
				balance_before = wallet.balance()
				enemy.apply_damage(999)
				phase = 2; t = 0
		2:
			if t > 0.4:
				var drops := get_nodes_in_group("reward_drops")
				var cur: RewardDrop = null
				for d in drops:
					if is_instance_valid(d) and d.entry == currency_entry:
						cur = d
				_check(cur != null, "kill %d drops the currency entry" % (kills + 1))
				if cur == null:
					return _finish()
				p.global_position = cur.global_position
				phase = 3; t = 0
		3:
			if t > 0.5:
				kills += 1
				_check(wallet.balance() == balance_before + currency_entry.currency_amount,
					"kill %d pickup adds %dc to the wallet (balance %d)" % [kills, currency_entry.currency_amount, wallet.balance()])
				_check(pool.is_eligible(currency_entry), "currency entry still eligible after grant")
				if kills < 2:
					p.global_position = Vector2(200, 200)
					_spawn_enemy()
					phase = 1; t = 0
				else:
					return _finish()
	if t > 6.0:
		_check(false, "timeout in phase %d" % phase)
		return _finish()
	return false
