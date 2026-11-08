extends SceneTree
## #220 harness: enemy spawner foundation (headless).
## Proves: parity with the old mount flow (count/positions/reward tables/
## player_path/terrain/parenting), one request_spawn seam, died bookkeeping,
## policy refusal, unknown entry keys tolerated, per-mount spawning (re-entry
## respawns) and teardown with the area.

var failures := 0

func _check(cond: bool, name: String) -> void:
	if not cond:
		failures += 1
	print("[220] ", name, " -> ", "PASS" if cond else "FAIL")

class RefusingSpawner extends EnemySpawner:
	func should_spawn(_entry: Dictionary) -> bool:
		return false

class CountingSpawner extends EnemySpawner:
	var requests := 0
	func request_spawn(entry: Dictionary) -> Enemy:
		requests += 1
		return super.request_spawn(entry)

func _initialize() -> void:
	var enemy_scene := load("res://scenes/enemy.tscn") as PackedScene
	var table := RewardTable.new()
	var entries: Array = [
		{ "position": Vector2(10, 20), "enemy": enemy_scene, "reward_table": table, "future_key": 42 },
		{ "position": Vector2(300, 40), "enemy": enemy_scene, "reward_table": table },
	]
	var path := NodePath("../../Player")

	# --- parity: default spawner mounts every entry once ---
	var area := Node2D.new()
	root.add_child(area)
	var sp := CountingSpawner.new()
	area.add_child(sp)
	var seen: Array = []
	sp.spawned.connect(func(e, entry): seen.append([e, entry]))
	sp.setup(entries, path, null, area)
	var got := sp.spawn_initial()
	await process_frame
	_check(got.size() == 2 and seen.size() == 2, "default spawns every entry once")
	_check(got[0].position == Vector2(10, 20) and got[1].position == Vector2(300, 40), "positions preserved")
	_check(got[0].reward_table == table and got[1].reward_table == table, "reward tables preserved")
	_check(got[0].player_path == path and got[0].get_parent() == area, "player_path assigned and parented to the area")
	_check(got[0].is_in_group("enemies"), "spawned enemies are in the enemies group")
	_check(sp.requests == 2, "all spawns route through request_spawn")
	_check(sp.alive_count(entries[0]) == 1 and sp.total_alive() == 2, "alive bookkeeping per entry")

	# --- died tracking ---
	var died_log: Array = []
	sp.spawn_died.connect(func(e, entry): died_log.append([e, entry]))
	got[0].died.emit()
	_check(died_log.size() == 1 and died_log[0][0] == got[0], "spawn_died emitted with enemy and entry")
	_check(sp.alive_count(entries[0]) == 0 and sp.alive_count(entries[1]) == 1, "alive count drops on died")

	# --- real Enemy death (apply_damage) + real TerrainMap + identical entries ---
	var areaR := Node2D.new()
	root.add_child(areaR)
	var tm := TerrainMap.new()
	areaR.add_child(tm)
	var dup_a := { "position": Vector2(5, 5), "enemy": enemy_scene, "reward_table": table }
	var dup_b := { "position": Vector2(5, 5), "enemy": enemy_scene, "reward_table": table }
	var spR := EnemySpawner.new()
	areaR.add_child(spR)
	spR.setup([dup_a, dup_b], path, tm, areaR)
	var real_died: Array = []
	spR.spawn_died.connect(func(e, entry): real_died.append([e, entry]))
	var rs2 := spR.spawn_initial()
	await process_frame
	_check(rs2[0].terrain == tm and rs2[1].terrain == tm, "real TerrainMap handed to every spawn")
	_check(spR.alive_count(dup_a) == 1 and spR.alive_count(dup_b) == 1, "identical-content entries keep separate bookkeeping")
	rs2[0].apply_damage(rs2[0].max_hp)
	await process_frame
	_check(real_died.size() == 1 and is_same(real_died[0][1], dup_a), "real lethal damage emits spawn_died for the right entry")
	_check(spR.alive_count(dup_a) == 0 and spR.alive_count(dup_b) == 1 and spR.total_alive() == 1, "only the killed entry's count drops")

	# --- policy refusal ---
	var area2 := Node2D.new()
	root.add_child(area2)
	var rs := RefusingSpawner.new()
	area2.add_child(rs)
	rs.setup(entries, path, null, area2)
	var none := rs.spawn_initial()
	await process_frame
	_check(none.is_empty() and rs.total_alive() == 0 and area2.get_child_count() == 1, "should_spawn false refuses cleanly")

	# --- per-mount: a fresh spawner on re-entry spawns again ---
	var area3 := Node2D.new()
	root.add_child(area3)
	var sp3 := EnemySpawner.new()
	area3.add_child(sp3)
	sp3.setup(entries, path, null, area3)
	var again := sp3.spawn_initial()
	_check(again.size() == 2, "a new mount spawns its entries again")

	# --- teardown ---
	area3.queue_free()
	await process_frame
	await process_frame
	_check(not is_instance_valid(again[0]) and not is_instance_valid(sp3), "spawns and spawner freed with the area")

	print("[220] failures=", failures)
	quit(1 if failures > 0 else 0)
