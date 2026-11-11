extends SceneTree
## #465 harness: regular mobs drop currency only (Daniel, 2026-11-09:
## "remove spells from the regular mob loot tables (they should only drop
## currency)"; bosses and beasts keep their drops, chests/shops and other
## spell sources unchanged).
##   (A) the production mob table (resources/rewards/demo_table.tres) is
##       currency-only and always rolls currency.
##   (B) every regular-mob context uses a currency-only table: DungeonA,
##       DungeonB, the overworld spawns, the generated dungeon, the
##       DungeonE defense-wave mobs.
##   (C) bosses and beasts are UNCHANGED: their definitions still carry the
##       boss token table with its UPGRADE_TOKEN entry.
##   (D) end to end on Main: a real mob dies, drops CURRENCY (never a
##       spell), and walk-over pickup adds it to the run wallet.
## Idioms follow test264 (production mount) and test414 (_check/_frames).

var failures := 0
var scene: Node
var p: Player

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[465] ", label, " -> ", "PASS" if ok else "FAIL")

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _initialize() -> void:
	var table: RewardTable = load("res://resources/rewards/demo_table.tres")
	_leg_a_table(table)
	_leg_b_mob_contexts()
	_leg_c_bosses_unchanged()
	await _leg_d_end_to_end(table)
	print("[465] DONE failures=", failures)
	if failures == 0:
		print("RESULT: ALL PASS")
	quit(1 if failures > 0 else 0)

func _leg_a_table(table: RewardTable) -> void:
	_check(table != null, "(A) the production mob table loads")
	_check(table.entries.size() == 1, "(A) exactly one entry (got %d)" % table.entries.size())
	var spells := 0
	var currency: RewardEntry = null
	for e in table.entries:
		if e.kind == RewardEntry.Kind.SPELL:
			spells += 1
		elif e.kind == RewardEntry.Kind.CURRENCY:
			currency = e
	_check(spells == 0, "(A) no SPELL entries: regular mobs drop currency only")
	_check(currency != null and currency.currency_amount > 0 and currency.weight > 0.0, "(A) the currency entry has a positive amount and weight")
	var ok := true
	for i in 50:
		if table.roll([]) != currency:
			ok = false
	_check(ok, "(A) the table always rolls currency (the pool keeps CURRENCY eligible after grants, #128)")

func _currency_only(table: RewardTable) -> bool:
	if table == null:
		return false
	for e in table.entries:
		if e.kind != RewardEntry.Kind.CURRENCY:
			return false
	return not table.entries.is_empty()

func _leg_b_mob_contexts() -> void:
	for path in ["res://scenes/dungeon_a.tscn", "res://scenes/dungeon_b.tscn", "res://scenes/overworld.tscn"]:
		var area: Node = load(path).instantiate()
		var all_ok := true
		var found := 0
		for sd in area.find_children("*", "AreaSpawnData", true, false):
			for entry in sd.entries:
				var rt := (entry as SpawnEntry).reward_table
				if rt != null:
					found += 1
					if not _currency_only(rt):
						all_ok = false
		_check(found > 0 and all_ok, "(B) %s mob tables are currency-only (%d checked)" % [path.get_file(), found])
		area.free()
	var gen: Script = load("res://scripts/generated_dungeon.gd")
	var gen_table: RewardTable = gen.get_script_constant_map().get("REWARD_TABLE")
	_check(_currency_only(gen_table), "(B) generated-dungeon mobs use a currency-only table")
	var loader_src: Script = load("res://scripts/area_loader.gd")
	var wave_table: RewardTable = loader_src.get_script_constant_map().get("DEFENSE_WAVE_TABLE")
	_check(_currency_only(wave_table), "(B) DungeonE defense-wave mobs use a currency-only table")

func _leg_c_bosses_unchanged() -> void:
	for path in ["res://resources/enemies/beast_boss.tres", "res://resources/enemies/mustache_warlord.tres", "res://resources/enemies/head_boss.tres", "res://resources/enemies/defense_wave_boss.tres"]:
		var def: EnemyDefinition = load(path)
		var rt: RewardTable = def.reward_table if def != null else null
		var has_token := false
		if rt != null:
			for e in rt.entries:
				if e.kind == RewardEntry.Kind.UPGRADE_TOKEN:
					has_token = true
		_check(has_token, "(C) %s keeps its boss token drops" % path.get_file())

func _leg_d_end_to_end(table: RewardTable) -> void:
	Bestiary.save_path = "user://test465_bestiary.cfg"
	scene = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	p = scene.get_node("Player")
	for i in 60:
		if scene.area_loader != null and scene.area_loader.current_area != null:
			break
		await _frames(1)
	_check(scene.area_loader.current_area != null, "(D) Main mounted")
	var wallet := Run.wallet()
	_check(wallet != null, "(D) Main mounts the run wallet")
	# A real mob carrying the production table dies in the hub area.
	var enemy: Enemy = (load("res://scenes/enemy.tscn") as PackedScene).instantiate()
	enemy.position = Vector2(576, 300)
	enemy.player_path = NodePath("../../Player")
	enemy.reward_table = table
	scene.area_loader.current_area.add_child(enemy)
	await _frames(10)
	# Park AFTER the settle frames: the hub's deferred player placement runs
	# during the first frames and would overwrite an earlier park.
	p.global_position = Vector2(200, 300) # out of aggro and off the kill spot
	await _frames(2)
	var balance_before: int = wallet.balance()
	enemy.apply_damage(9999) # synthetic kill
	await _frames(10)
	var drops := get_nodes_in_group("reward_drops")
	_check(drops.size() == 1, "(D) exactly one drop spawned (got %d)" % drops.size())
	if drops.size() == 1:
		var drop := drops[0] as RewardDrop
		_check(drop.entry != null and drop.entry.kind == RewardEntry.Kind.CURRENCY, "(D) the drop is CURRENCY (never a spell)")
		# Walk-over pickup routes the amount into the run wallet (#128).
		# Capture the amount first: collection frees the drop.
		var amount: int = drop.entry.currency_amount
		p.global_position = drop.global_position
		await _frames(10)
		_check(wallet.balance() == balance_before + amount, "(D) walk-over pickup adds %dc to the wallet" % amount)
	p.hp = p.max_hp
