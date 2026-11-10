extends SceneTree
## #490 harness: the Fishy spawns about half as often as Mustache Warriors
## in the overworld (every entrance camp + roamers), DungeonA/B and the
## generated dungeon. "About half" = fish / warriors within 0.35 .. 0.7.

const FISHY_PATH := "res://scenes/enemy_fishy.tscn"
const WARRIOR_PATH := "res://scenes/enemy.tscn"
const LOW := 0.35
const HIGH := 0.7

var failures := 0

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[490] ", name, " -> PASS")
	else:
		failures += 1
		print("[490] ", name, " -> FAIL")

func _count(entries: Array) -> Vector2i:
	var c := Vector2i.ZERO
	for e in entries:
		var path := (e["enemy"] as PackedScene).resource_path
		if path == FISHY_PATH:
			c.x += 1
		elif path == WARRIOR_PATH:
			c.y += 1
	return c

func _about_half(c: Vector2i) -> bool:
	if c.y == 0:
		return false
	var r := float(c.x) / float(c.y)
	return r >= LOW and r <= HIGH

func _initialize() -> void:
	await _overworld()
	for path in ["res://scenes/dungeon_a.tscn", "res://scenes/dungeon_b.tscn"]:
		await _dungeon(path)
	await _generated()
	print("[490] failures: ", failures)
	if failures == 0:
		print("RESULT: ALL PASS")
	quit(1 if failures > 0 else 0)

func _overworld() -> void:
	var ow: Node2D = load("res://scenes/overworld.tscn").instantiate()
	root.add_child(ow)
	await process_frame
	var total := Vector2i.ZERO
	for camp in ow.get_node("EntranceGuards").get_children():
		var c := _count((camp as AreaSpawnData).entries)
		total += c
		_check(c.x >= 1, "overworld %s has a Fishy (%d fish / %d warriors)" % [camp.name, c.x, c.y])
	total += _count((ow.get_node("Roamers") as AreaSpawnData).entries)
	_check(_about_half(total), "overworld: Fishy about half as common as warriors (%d vs %d)" % [total.x, total.y])
	ow.queue_free()
	await process_frame

func _dungeon(path: String) -> void:
	var area: Node2D = load(path).instantiate()
	root.add_child(area)
	await process_frame
	var c := _count((area.get_node("SpawnData") as AreaSpawnData).entries)
	_check(c.x >= 2 and c.x < c.y, "%s: more Fishy than before, still fewer than warriors (%d vs %d)" % [path.get_file(), c.x, c.y])
	area.queue_free()
	await process_frame

func _generated() -> void:
	var scene: PackedScene = load("res://scenes/dungeon_generated.tscn")
	var total := Vector2i.ZERO
	var every_seed := true
	for s in [1, 2, 3, 7, 42]:
		var area: Node2D = scene.instantiate()
		area.set("map_seed", s)
		root.add_child(area)
		await process_frame
		var c := _count((area.get_node("SpawnData") as AreaSpawnData).entries)
		total += c
		print("  seed %d: %d fish / %d warriors" % [s, c.x, c.y])
		if c.x + c.y >= 3 and c.x == 0:
			every_seed = false
		var map := area.get_node("Terrain") as TerrainMap
		for e in (area.get_node("SpawnData") as AreaSpawnData).entries:
			if not map.is_walkable_at(area.to_global(e["position"])):
				every_seed = false
				print("  seed %d: spawn on blocked terrain at %s" % [s, e["position"]])
		area.queue_free()
		await process_frame
	_check(every_seed, "generated dungeon: every seed with 3+ enemies spawns a Fishy, all on walkable ground")
	_check(_about_half(total), "generated dungeon: Fishy about half as common as warriors (%d vs %d)" % [total.x, total.y])
