extends SceneTree
## #512: every dungeon scene has a DungeonDefinition, and the definition
## agrees with the scene (root node name, scene path, route id/label).
## dungeon_generated has no objective or clear id, so it has none (exempt).
## Run: godot --headless --fixed-fps 60 --path . -s tests/world/test512_dungeon_definitions.gd

const EXEMPT: Array[String] = ["dungeon_generated"]
var _fails := 0
var _checks := 0

func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("[512] ", label, " -> ", "PASS" if ok else "FAIL")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var seen: Array[StringName] = []
	for f in DirAccess.get_files_at("res://game/world"):
		if not (f.begins_with("dungeon_") and f.ends_with(".tscn")):
			continue
		var base := f.get_basename()
		if base in EXEMPT:
			continue
		var scene_path := "res://game/world/" + f
		var def: DungeonDefinition = null
		for d: DungeonDefinition in DungeonCatalog.definitions():
			if d.scene == scene_path:
				def = d
		_check(base + ": has a definition", def != null)
		if def == null:
			continue
		var area := (load(scene_path) as PackedScene).instantiate()
		_check(base + ": area_name matches the scene root (%s)" % area.name, def.area_name == area.name)
		_check(base + ": lookup by area returns it", DungeonCatalog.for_area(area) == def)
		_check(base + ": id is the fast-travel route id", FastTravelRoutes.DUNGEONS.has(def.id) and FastTravelRoutes.DUNGEONS[def.id]["scene"] == scene_path)
		_check(base + ": label matches the route label", FastTravelRoutes.label_for(def.id) == def.label)
		_check(base + ": unique id", not seen.has(def.id))
		seen.append(def.id)
		area.free()
	for id: StringName in FastTravelRoutes.DUNGEONS:
		_check("route %s has a definition" % id, seen.has(id))
	_check("unknown area has none", DungeonCatalog.for_name(&"Hub") == null and DungeonCatalog.for_area(null) == null)
	print("test512 done: %d checks, %d failures" % [_checks, _fails])
	print("[512] RESULT: ", "ALL PASS" if _fails == 0 else "FAIL")
	quit(0 if _fails == 0 else 1)
