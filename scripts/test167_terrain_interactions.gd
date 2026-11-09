extends SceneTree
## #167 (Terrain B1) harness: spell -> terrain element interactions (headless).
## Proves: the shipped registry validates and holds freeze_water (cold +
## water -> ice); dispatch is by element tag only, first-match in list order,
## and a new rule is pure data (no code); TerrainMap.interact_cell turns water
## into walkable ICE once, emits cell_interacted, and leaves other tiles and
## non-cold spells alone; the frozen cell admits non-swimmers and reconnects a
## river-split map; a cold projectile freezes every water cell on its path and
## keeps flying, a plain one leaves the water; a rule marked
## consumes_projectile stops a non-piercing shot (piercing continues); the real
## player slot-cast path with the shipped Frost Shard freezes water.

var failures := 0

func _check(cond: bool, name: String) -> void:
	if not cond:
		failures += 1
	print("[167] ", name, " -> ", "PASS" if cond else "FAIL")

func _new_map(stage: Node, offset: Vector2 = Vector2.ZERO) -> TerrainMap:
	var m := TerrainMap.new()
	m.cell_size = 64
	m.position = offset
	stage.add_child(m)
	return m

func _fire(stage: Node, spell: Spell, from: Vector2, dir: Vector2, src: Node2D) -> Projectile:
	var p: Projectile = load("res://scenes/projectile.tscn").instantiate()
	p.setup(spell, dir, src)
	stage.add_child(p)
	p.global_position = from
	return p

func _shooter(stage: Node, map: TerrainMap, at: Vector2) -> Player:
	var s: Player = load("res://scenes/player.tscn").instantiate()
	stage.add_child(s)
	s.global_position = at
	s.terrain = map
	s.set_physics_process(false)
	s.get_node("SpellCaster").set_process(false)
	return s

## A vertical river at columns 4..6, rows 0..6.
func _river(map: TerrainMap) -> void:
	var cells := {}
	for x in range(4, 7):
		for y in range(0, 7):
			cells[Vector2i(x, y)] = TerrainTypes.WATER
	map.set_cells(cells)

func _alive(p: Variant) -> bool:
	return is_instance_valid(p) and not p.is_queued_for_deletion()

func _initialize() -> void:
	var stage := Node2D.new()
	stage.name = "Stage"
	root.add_child(stage)
	current_scene = stage
	await process_frame

	# --- A. shipped data ---
	_check(TerrainInteractions.validate().is_empty(), "shipped interaction registry validates (%s)" % [TerrainInteractions.validate()])
	var freeze: TerrainInteraction = load("res://resources/terrain_interactions/freeze_water.tres")
	_check(TerrainInteractions.rules().has(freeze) and TerrainInteractions.rules()[0] is TerrainInteraction, "freeze_water is registered (typed rule resource)")
	_check(freeze.id == &"freeze_water" and freeze.spell_tag == SpellTags.COLD and freeze.tile_tag == &"water" and freeze.result_type == TerrainTypes.ICE, "freeze_water: cold + water -> ice")
	_check(not freeze.consumes_projectile, "freeze_water lets the shot keep flying")
	_check(SpellTags.is_valid(SpellTags.COLD), "COLD is in the spell tag vocabulary")
	_check(TerrainTypes.element_tags(TerrainTypes.WATER).has(&"water") and TerrainTypes.is_walkable(TerrainTypes.ICE), "WATER carries the water tag; ICE is walkable")
	var frost: Spell = load("res://resources/spells/frost_shard.tres")
	_check(frost != null and frost.tags.has(SpellTags.COLD) and frost.tags.has(SpellTags.PROJECTILE) and SpellTags.unknown_tags(frost.tags).is_empty(), "Frost Shard is a cold-tagged projectile spell")

	# --- B. dispatch by tag ---
	_check(TerrainInteractions.find([SpellTags.COLD], [&"water"]) == freeze, "cold spell on a water-tagged tile -> freeze_water")
	_check(TerrainInteractions.find([SpellTags.PROJECTILE, SpellTags.COLD], [&"water", &"extra"]) == freeze, "extra tags on either side do not block the match")
	_check(TerrainInteractions.find([SpellTags.BURN], [&"water"]) == null, "a non-cold spell does not match")
	_check(TerrainInteractions.find([SpellTags.COLD], [&"ice"]) == null, "a cold spell on ice does not match")
	_check(TerrainInteractions.find([], [&"water"]) == null and TerrainInteractions.find([SpellTags.COLD], []) == null, "untagged spell / tile never match")
	# Extensibility: a brand-new rule is data only.
	var melt := TerrainInteraction.new()
	melt.id = &"melt_ice"
	melt.spell_tag = SpellTags.BURN
	melt.tile_tag = &"ice"
	melt.result_type = TerrainTypes.WATER
	var shadow := TerrainInteraction.new()
	shadow.id = &"shadow"
	shadow.spell_tag = SpellTags.COLD
	shadow.tile_tag = &"water"
	shadow.result_type = TerrainTypes.SNOW
	var custom: Array[TerrainInteraction] = [freeze, melt, shadow]
	_check(TerrainInteractions.validate(custom).is_empty(), "a custom rule list validates")
	_check(TerrainInteractions.find([SpellTags.BURN], [&"ice"], custom) == melt, "a new data-only rule dispatches (burn + ice -> water)")
	_check(TerrainInteractions.find([SpellTags.COLD], [&"water"], custom) == freeze, "first matching rule wins (list order is priority)")
	var bad := TerrainInteraction.new()
	bad.id = &"bad"
	bad.spell_tag = &"bogus"
	bad.tile_tag = &"water"
	bad.result_type = TerrainTypes.WATER
	var bad_list: Array[TerrainInteraction] = [bad, freeze, freeze]
	var errs := TerrainInteractions.validate(bad_list)
	_check(errs.size() == 3, "validate flags unknown spell tag, self-refiring result and duplicate id (%s)" % [errs])

	# --- C. TerrainMap.interact_cell ---
	var m := _new_map(stage)
	await process_frame
	_river(m)
	var events: Array = []
	m.cell_interacted.connect(func(c, o, n, id): events.append([c, o, n, id]))
	var cold: Array[StringName] = [SpellTags.PROJECTILE, SpellTags.COLD]
	var plain: Array[StringName] = [SpellTags.PROJECTILE]
	var w := Vector2i(5, 3)
	_check(m.interaction_for_cell(w, cold) == freeze and m.interaction_for_cell(w, plain) == null, "interaction_for_cell answers by tag")
	_check(m.interact_cell(w, plain) == null and m.tile_type_at_cell(w) == TerrainTypes.WATER, "a plain spell leaves water as water")
	_check(m.interact_cell(w, cold) == freeze, "a cold spell freezes the water cell")
	_check(m.tile_type_at_cell(w) == TerrainTypes.ICE and m.is_walkable_at_cell(w), "frozen cell is ICE and walkable")
	_check(m.debug_layer_cells(true).has(w) and not m.debug_layer_cells(false).has(w), "ICE redrawn on the walkable layer")
	_check(events == [[w, TerrainTypes.WATER, TerrainTypes.ICE, &"freeze_water"]], "cell_interacted fired once with the rule id")
	_check(m.interact_cell(w, cold) == null and events.size() == 1, "re-hitting ice with cold is a no-op")
	_check(m.interact_cell(Vector2i(0, 0), cold) == null and m.tile_type_at_cell(Vector2i(0, 0)) == TerrainTypes.GROUND, "ground is untouched")
	m.set_cell(Vector2i(1, 1), TerrainTypes.OBSTACLE)
	_check(m.interact_cell(Vector2i(1, 1), cold) == null and m.tile_type_at_cell(Vector2i(1, 1)) == TerrainTypes.OBSTACLE, "an untagged wall is untouched")
	_check(m.interact_at(m.cell_to_world(Vector2i(4, 3)), cold) == freeze, "interact_at resolves world positions")
	# Per-map rule list (an area can swap rules without code).
	var only_melt: Array[TerrainInteraction] = [melt]
	m.interaction_rules = only_melt
	_check(m.interact_cell(Vector2i(6, 0), cold) == null, "a map without freeze_water does not freeze")
	_check(m.interact_cell(w, [SpellTags.BURN]) == melt and m.tile_type_at_cell(w) == TerrainTypes.WATER, "a map-specific rule (melt) applies")
	m.queue_free()
	await process_frame

	# --- C2. movement + navigation through the frozen cell ---
	var nm := _new_map(stage, Vector2(0, 2048))
	await process_frame
	var bounds := {}
	for x in range(-1, 12):
		bounds[Vector2i(x, -1)] = TerrainTypes.OBSTACLE
		bounds[Vector2i(x, 7)] = TerrainTypes.OBSTACLE
	for y in range(-1, 8):
		bounds[Vector2i(-1, y)] = TerrainTypes.OBSTACLE
		bounds[Vector2i(11, y)] = TerrainTypes.OBSTACLE
	nm.set_cells(bounds)
	_river(nm)
	var left := nm.cell_to_world(Vector2i(1, 3))
	var right := nm.cell_to_world(Vector2i(9, 3))
	_check(not TerrainNav.is_navigable(nm, left, right), "fixture: the river splits the map")
	var shore := nm.cell_to_world(Vector2i(3, 3)) + Vector2(30, 0)
	_check(not TerrainMotion.can_enter(nm, nm.cell_to_world(Vector2i(4, 3)), false), "a non-swimmer cannot enter water")
	for x in range(4, 7):
		nm.interact_cell(Vector2i(x, 3), cold)
	_check(TerrainNav.is_navigable(nm, left, right), "a frozen row bridges the river")
	_check(TerrainMotion.can_enter(nm, nm.cell_to_world(Vector2i(4, 3)), false), "a non-swimmer can enter the ice")
	var v := TerrainMotion.resolve(nm, shore, Vector2.ZERO, Vector2(320, 0), 1.0 / 60.0, false)
	_check(v.x > 0.0, "a non-swimmer walks onto the ice (vx %.1f)" % v.x)
	var on_ice := nm.cell_to_world(Vector2i(5, 3))
	var slide := TerrainMotion.resolve(nm, on_ice, Vector2(320, 0), Vector2.ZERO, 1.0 / 60.0, false)
	_check(slide.x > 300.0, "ice keeps its low friction: the mover slides (vx %.1f)" % slide.x)
	_check(not TerrainMotion.can_enter(nm, nm.cell_to_world(Vector2i(5, 2)), false), "unfrozen water next to the bridge still blocks")
	nm.queue_free()
	await process_frame

	# --- D. projectiles ---
	var pm := _new_map(stage, Vector2(0, 4096))
	await process_frame
	_river(pm)
	var shooter := _shooter(stage, pm, pm.to_global(Vector2(32, 600)))
	await process_frame
	var pev: Array = []
	pm.cell_interacted.connect(func(c, _o, _n, _id): pev.append(c))
	var start := pm.cell_to_world(Vector2i(1, 3))
	var p := _fire(stage, frost, start, Vector2.RIGHT, shooter)
	for i in 50:
		await physics_frame
	var row: Array = [Vector2i(4, 3), Vector2i(5, 3), Vector2i(6, 3)]
	_check(pev == row, "a Frost Shard freezes each water cell on its path, in flight order (%s)" % [pev])
	var still_water := true
	for x in range(4, 7):
		for y in [2, 4]:
			still_water = still_water and pm.tile_type_at_cell(Vector2i(x, y)) == TerrainTypes.WATER
	_check(still_water, "cells beside the flight line stay water")
	_check(_alive(p) and p.global_position.x > pm.cell_to_world(Vector2i(6, 3)).x, "the shot keeps flying past the frozen cells")
	if is_instance_valid(p):
		p.queue_free()
	pev.clear()
	var bolt: Spell = load("res://resources/spells/placeholder_bolt.tres")
	var start2 := pm.cell_to_world(Vector2i(1, 5))
	var p2 := _fire(stage, bolt, start2, Vector2.RIGHT, shooter)
	for i in 40:
		await physics_frame
	_check(pev.is_empty() and pm.tile_type_at_cell(Vector2i(5, 5)) == TerrainTypes.WATER, "a non-cold bolt leaves the water")
	_check(_alive(p2), "a non-cold bolt still passes over water")
	if is_instance_valid(p2):
		p2.queue_free()
	# a terrain-less source never touches the map
	_fire(stage, frost, pm.cell_to_world(Vector2i(1, 1)), Vector2.RIGHT, null)
	for i in 40:
		await physics_frame
	_check(pev.is_empty() and pm.tile_type_at_cell(Vector2i(5, 1)) == TerrainTypes.WATER, "a terrain-less source freezes nothing")
	# consumes_projectile: the shot stops on the first transformed cell
	var stop_rule: TerrainInteraction = freeze.duplicate()
	stop_rule.id = &"freeze_and_stop"
	stop_rule.consumes_projectile = true
	var stop_list: Array[TerrainInteraction] = [stop_rule]
	pm.interaction_rules = stop_list
	var p3 := _fire(stage, frost, pm.cell_to_world(Vector2i(1, 0)), Vector2.RIGHT, shooter)
	for i in 40:
		await physics_frame
	_check(pev == [Vector2i(4, 0)] and pm.tile_type_at_cell(Vector2i(5, 0)) == TerrainTypes.WATER, "a consuming rule freezes only the first cell (%s)" % [pev])
	_check(not _alive(p3), "a consuming rule stops a non-piercing shot")
	pev.clear()
	var pierce: Spell = frost.duplicate()
	var pt: Array[StringName] = [SpellTags.PROJECTILE, SpellTags.COLD, SpellTags.PIERCING]
	pierce.tags = pt
	var p4 := _fire(stage, pierce, pm.cell_to_world(Vector2i(1, 6)), Vector2.RIGHT, shooter)
	for i in 50:
		await physics_frame
	_check(pev == [Vector2i(4, 6), Vector2i(5, 6), Vector2i(6, 6)] and _alive(p4), "a PIERCING cold shot freezes the whole row even under a consuming rule")
	if is_instance_valid(p4):
		p4.queue_free()
	var registry: Array[TerrainInteraction] = []
	pm.interaction_rules = registry
	shooter.queue_free()
	await process_frame

	# --- E. real player slot cast with the shipped spell ---
	var cm := _new_map(stage, Vector2(0, 8192))
	await process_frame
	var player: Player = load("res://scenes/player.tscn").instantiate()
	stage.add_child(player)
	player.terrain = cm
	player.set_physics_process(false)
	await process_frame
	var caster: SpellCaster = player.get_node("SpellCaster")
	var aim := caster.get_global_mouse_position()
	player.global_position = aim - Vector2(400, 0)
	await process_frame
	aim = caster.get_global_mouse_position()
	var water_cell := cm.world_to_cell(player.global_position.lerp(aim, 0.5))
	cm.set_cell(water_cell, TerrainTypes.WATER)
	caster.unlock_spell(frost)
	var slot := caster.get_slots().find(frost)
	_check(slot != -1, "Frost Shard auto-binds to a slot")
	var cev: Array = []
	cm.cell_interacted.connect(func(c, _o, _n, id): cev.append([c, id]))
	caster.cast_slot(slot)
	for i in 60:
		await physics_frame
	_check(cev == [[water_cell, &"freeze_water"]] and cm.tile_type_at_cell(water_cell) == TerrainTypes.ICE, "slot-cast Frost Shard freezes the water between caster and aim (%s)" % [cev])

	player.queue_free()
	cm.queue_free()
	await process_frame

	# --- F. the evidence scene end to end (non-swimmer, river, ice bridge) ---
	var demo: Node2D = load("res://scenes/test167_freeze_debug.tscn").instantiate()
	stage.add_child(demo)
	await process_frame
	var dmap: TerrainMap = demo.get_node("TerrainMap")
	var dp: Player = demo.get_node("Player")
	var river_edge := dmap.cell_to_world(Vector2i(8, 5)).x - dmap.cell_size * 0.5
	for i in 80: # 1.33 s of walking right
		await physics_frame
	_check(not dp.can_swim and dp.global_position.x < river_edge, "demo: the non-swimmer is stopped at the river (x %.0f < %.0f)" % [dp.global_position.x, river_edge])
	for i in 280:
		await physics_frame
	var frozen := 0
	for x in range(8, 11):
		for y in range(4, 7):
			if dmap.tile_type_at_cell(Vector2i(x, y)) == TerrainTypes.ICE:
				frozen += 1
	_check(frozen == 9 and demo._frozen == 9, "demo: three Frost Shards froze a 3x3 ice bridge (%d)" % frozen)
	_check(dmap.tile_type_at_cell(Vector2i(9, 2)) == TerrainTypes.WATER, "demo: the rest of the river is still water")
	_check(dp.global_position.x > dmap.cell_to_world(Vector2i(10, 5)).x + dmap.cell_size * 0.5, "demo: the non-swimmer crossed the ice (x %.0f)" % dp.global_position.x)
	Input.action_release(&"move_right")
	demo.queue_free()

	print("[167] failures: ", failures)
	if failures == 0:
		print("RESULT: ALL PASS")
	quit(1 if failures > 0 else 0)
