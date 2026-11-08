extends SceneTree
## Headless driver for the hub stone plaza floor: hub-only, layered between
## the global grid and the hub decor, covers every hub point of interest,
## freed on entering a dungeon and restored on return, deterministic tiles.

var scene: Node
var p: Node2D
var phase := 0
var t := 0.0
var fails := 0

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene

func _check(label: String, ok: bool) -> void:
	if not ok:
		fails += 1
	print("[190] ", label, " -> ", "PASS" if ok else "FAIL")

func _floors() -> Array[Node]:
	return scene.find_children("*", "HubFloor", true, false)

func _check_hub_floor(when: String) -> void:
	var hub: Node = scene.current_area
	_check("%s: current area is Hub" % when, hub.name == "Hub")
	var floor := hub.get_node_or_null("Floor") as HubFloor
	_check("%s: hub has exactly one HubFloor at Hub/Floor" % when, floor != null and _floors().size() == 1)
	if floor == null:
		return
	var grid := scene.get_node("BackgroundGrid") as Node2D
	var bg := hub.get_node("Background") as Node2D
	_check("%s: floor z_index -80" % when, floor.z_index == -80)
	_check("%s: grid z %d < floor z %d < hub Background z %d" % [when, grid.z_index, floor.z_index, bg.z_index],
		grid.z_index < floor.z_index and floor.z_index < bg.z_index)
	var points := {
		"spawn": (hub.get_node("PlayerSpawn") as Node2D).global_position,
		"GateNormal": (hub.get_node("GateNormal") as Node2D).global_position,
		"GateRed": (hub.get_node("GateRed") as Node2D).global_position,
		"ShopVendor": (hub.get_node("ShopVendor") as Node2D).global_position,
	}
	for key: String in points:
		var at: Vector2 = points[key]
		_check("%s: floor covers %s %s" % [when, key, at], floor.covers(at - floor.global_position))
	for corner in [Vector2(216, 190), Vector2(936, 190), Vector2(216, 630), Vector2(936, 630)]:
		_check("%s: floor covers corner marker %s" % [when, corner], floor.covers(corner))
	_check("%s: floor ends before far grid (5000,5000)" % when, not floor.covers(Vector2(5000, 5000)))

func _process(delta: float) -> bool:
	t += delta
	match phase:
		0:
			if scene.get_node_or_null("Player") != null and t > 0.3:
				p = scene.get_node("Player")
				_check_hub_floor("boot")
				var g: Gate = scene.current_area.get_node("GateNormal")
				g._on_body_entered(p)
				phase = 1; t = 0
		1:
			if t > 0.4:
				_check("dungeon: current area is DungeonA", scene.current_area.name == "DungeonA")
				_check("dungeon: no HubFloor anywhere under Main", _floors().size() == 0)
				_check("dungeon: global grid still present", scene.get_node_or_null("BackgroundGrid") != null)
				var portal: ExitPortal = scene.current_area.get_node("ExitPortal")
				portal.unlock()
				portal._on_body_entered(p)
				phase = 2; t = 0
		2:
			if t > 0.4:
				_check_hub_floor("return")
				var a := HubFloor.new()
				var b := HubFloor.new()
				_check("tiles: plaza has many stones (%d)" % a.tile_colors.size(), a.tile_colors.size() > 100)
				_check("tiles: two instances produce identical tile colors", a.tile_colors == b.tile_colors)
				_check("tiles: two instances produce identical tile shapes", a.tiles == b.tiles)
				var distinct := {}
				for c in a.tile_colors:
					distinct[c] = true
				_check("tiles: colors vary per stone (%d distinct)" % distinct.size(), distinct.size() > 20)
				a.free()
				b.free()
				if fails == 0:
					print("[190] ALL PASS")
				print("[190] DONE fails=", fails)
				quit(1 if fails > 0 else 0)
	return false
