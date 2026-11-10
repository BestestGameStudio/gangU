extends SceneTree
## TerrainMap's cached, allocation-free cell queries (can_enter_cell,
## is_hard_obstacle_cell, blocks_projectiles_at_cell, speed/friction,
## is_walkable_at_cell, movement_at_cell, conceals_at) answer exactly what
## the copying type_properties() says, for every built-in type, every
## palette tile and an unknown id; a palette swap drops the cache; and
## type_properties() still hands out a fresh, writable copy.
## Run: godot --headless --path . -s scripts/test_terrain_queries.gd

const HIGHLANDS: TerrainPalette = preload("res://resources/terrain_palettes/highlands.tres")
const F := TerrainTypes.Movement.FALLING

var failures := 0

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[queries] ", name, " -> PASS")
	else:
		failures += 1
		print("[queries] ", name, " -> FAIL")

func _initialize() -> void:
	var m := TerrainMap.new()
	m.cell_size = 32
	root.add_child(m)
	_agree(m, "built-in map")
	m.palette = HIGHLANDS
	_agree(m, "highlands palette")
	var swap := TerrainPalette.new()
	var pit := TerrainTile.new()
	pit.id = TerrainTypes.GRASS
	pit.movement = F
	swap.tiles = [pit]
	m.set_cell(Vector2i(0, 0), TerrainTypes.GRASS)
	_check(m.can_enter_cell(Vector2i(0, 0), false), "grass is enterable before the palette swap")
	m.palette = swap
	_check(not m.can_enter_cell(Vector2i(0, 0), true) and m.is_hard_obstacle_cell(Vector2i(0, 0)), "palette swap drops the cache: grass restyled as a pit is not enterable")
	_agree(m, "restyled palette")
	var a := m.type_properties(TerrainTypes.WATER)
	a["walkable"] = true
	(a["element_tags"] as Array).append(&"lava")
	var b := m.type_properties(TerrainTypes.WATER)
	_check(not b["walkable"] and not (b["element_tags"] as Array).has(&"lava") and not m.is_walkable_at_cell(_cell_of(m, TerrainTypes.WATER)), "type_properties is a writable copy; mutating it changes nothing")
	m.free()
	print("[queries] ", "RESULT: ALL PASS" if failures == 0 else "RESULT: %d FAILED" % failures)
	quit(1 if failures > 0 else 0)

func _cell_of(m: TerrainMap, type: StringName) -> Vector2i:
	var c := Vector2i(100, 100)
	m.set_cell(c, type)
	return c

func _agree(m: TerrainMap, label: String) -> void:
	var types: Array[StringName] = TerrainTypes.ALL.duplicate()
	if m.palette != null:
		types.append_array(m.palette.custom_ids())
	types.append(&"lava")
	var bad := PackedStringArray()
	var i := 0
	for type in types:
		var c := Vector2i(i, 7)
		i += 1
		if m.is_valid_type(type):
			m.set_cell(c, type)
		else:
			m._cells[c] = type
		var p := m.type_properties(type)
		var falling: bool = p["movement"] == F
		var ok: bool = m.is_walkable_at_cell(c) == p["walkable"] \
			and m.movement_at_cell(c) == p["movement"] \
			and m.conceals_at(m.cell_to_world(c)) == p["conceals"] \
			and m.blocks_projectiles_at_cell(c) == p["blocks_projectiles"] \
			and is_equal_approx(m.speed_multiplier_at_cell(c), p["speed_multiplier"]) \
			and is_equal_approx(m.friction_at_cell(c), p["friction"]) \
			and m.is_hard_obstacle_cell(c) == (falling or (not p["walkable"] and not p["swimmable"]))
		for swim in [false, true]:
			ok = ok and m.can_enter_cell(c, swim) == (not falling and (p["walkable"] or (p["swimmable"] and swim)))
		if not ok:
			bad.append(type)
	_check(bad.is_empty(), "%s: cached queries match type_properties for %d types (mismatch: %s)" % [label, types.size(), bad])
