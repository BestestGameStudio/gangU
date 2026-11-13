extends SceneTree
## Spawn data is typed end to end: authored carriers hold SpawnEntry
## resources with their exact authored values, and the spawner rejects an
## entry that cannot spawn.

const ENEMY := "res://game/enemies/enemy.tscn"
const SLIME := "res://game/enemies/enemy_slime.tscn"
const FISHY := "res://game/enemies/enemy_fishy.tscn"
const TABLE := "res://data/rewards/demo_table.tres"

var failures := 0

func _check(cond: bool, name: String) -> void:
	if not cond:
		failures += 1
	print("[518] ", name, " -> ", "PASS" if cond else "FAIL")

func _initialize() -> void:
	_carrier_leg()
	await _reject_leg()
	print("[518] failures=", failures)
	quit(1 if failures > 0 else 0)

func _path(r: Resource) -> String:
	return r.resource_path if r != null else ""

func _matches(e: SpawnEntry, pos: Vector2, enemy: String, table: String, def: String, route: PackedVector2Array) -> bool:
	return e.position == pos and _path(e.enemy) == enemy and _path(e.reward_table) == table and _path(e.definition) == def and e.route == route

func _all_typed(root: Node) -> bool:
	var carriers := root.find_children("*", "AreaSpawnData", true, false)
	if carriers.is_empty():
		return false
	for c in carriers:
		var entries := (c as AreaSpawnData).entries
		if entries.get_typed_script() != SpawnEntry:
			return false
		for e: Variant in entries:
			if not e is SpawnEntry:
				return false
	return true

func _carrier_leg() -> void:
	var da := (load("res://game/world/dungeon_a.tscn") as PackedScene).instantiate()
	var a := (da.get_node("SpawnData") as AreaSpawnData).entries
	_check(_all_typed(da) and a.size() == 7, "dungeon A carrier holds 7 SpawnEntry resources")
	_check(a.size() == 7 and _matches(a[0], Vector2(250, 280), ENEMY, TABLE, "", PackedVector2Array()), "dungeon A [0] warrior at (250, 280) with the demo table")
	_check(a.size() == 7 and _matches(a[3], Vector2(410, 350), SLIME, TABLE, "", PackedVector2Array()), "dungeon A [3] slime at (410, 350)")
	_check(a.size() == 7 and _matches(a[5], Vector2(576, 420), FISHY, TABLE, "", PackedVector2Array()), "dungeon A [5] Fishy at (576, 420)")
	da.free()

	var db := (load("res://game/world/dungeon_b.tscn") as PackedScene).instantiate()
	var b := (db.get_node("SpawnData") as AreaSpawnData).entries
	_check(_all_typed(db) and b.size() == 5, "dungeon B carrier holds 5 SpawnEntry resources")
	_check(b.size() == 5 and _matches(b[4], Vector2(360, 230), FISHY, TABLE, "", PackedVector2Array()), "dungeon B [4] Fishy at (360, 230)")
	db.free()

	var ow := (load("res://game/world/overworld.tscn") as PackedScene).instantiate()
	_check(_all_typed(ow), "every overworld carrier holds SpawnEntry resources")
	ow.free()

func _reject_leg() -> void:
	var area := Node2D.new()
	root.add_child(area)
	var sp := EnemySpawner.new()
	area.add_child(sp)
	var no_scene := SpawnEntry.new(Vector2(1, 2))
	var good := SpawnEntry.new(Vector2(3, 4), load(ENEMY) as PackedScene, load(TABLE) as RewardTable)
	sp.setup([no_scene, good], NodePath(""), null, area)
	var got := sp.spawn_initial()
	await process_frame
	_check(got.size() == 1 and got[0].position == Vector2(3, 4), "entry without an enemy scene is rejected, the valid one spawns")
	_check(sp.alive_count(no_scene) == 0 and sp.alive_count(good) == 1 and area.get_child_count() == 2, "rejected entry leaves no enemy and no bookkeeping")
	area.queue_free()
	await process_frame
