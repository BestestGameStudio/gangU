extends SceneTree
## #373 harness: overworld enemy roles (production main.tscn + overworld).
##   (A) scene data: each guarded entrance has exactly ONE stationary gate
##       guard; the rest of its enemies patrol a closed loop; the overworld
##       carries migrants (Roamers) on long open paths. Moving roles
##       outnumber guards; every route point is on the field and migrant
##       paths keep clear of the arrival point.
##   (B) production mount: roles arrive with their routes (global space).
##   (C) with the player idle at the arrival point: gate guards hold their
##       posts, patrols walk their loop (several corners visited, staying on
##       their beat), migrants travel far along their path, nobody hurts the
##       player.
##   (D) a migrant reaches its destination, rests, then migrates back.
##   (E) patrols and migrants keep the guard's aggro / leash: they engage a
##       nearby player, give up past the leash and resume their route.
##   (F) #348 composition: clearing DungeonA removes its guard AND patrol,
##       migrants stay (they belong to no entrance).

var failures := 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[373] ", label, " -> ", "PASS" if ok else "FAIL")

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _enter(main: Node, gate_name: String) -> void:
	var gate: Gate = main.area_loader.current_area.get_node(gate_name)
	gate._on_body_entered(main.get_node("Player"))
	await _frames(3)

func _role(e: Enemy) -> String:
	if e._behavior is EnemyBehaviorPatrol:
		return "patrol"
	if e._behavior is EnemyBehaviorMigrate:
		return "migrant"
	if e._behavior is EnemyBehaviorGuard:
		return "guard"
	return "other"

## #461: the overworld's hashed tall-grass patches hide the player, which
## also drops aggro. Leash legs measure distance only, so they stand the
## player on open ground at that distance.
func _open_ground(viewer: Enemy, from: Vector2, dist: float) -> Vector2:
	for i in 16:
		var at := from + Vector2.DOWN.rotated(TAU * i / 16.0) * dist
		if not TallGrass.conceals_at(viewer.sight_map(), at):
			return at
	return from + Vector2.DOWN * dist

## #478: the overworld's day bird dives an idle player in the open on its
## own clock. These flow legs assert #414 guard/patrol/migrant roles only,
## so the bird and its driver are removed on entry.
func _remove_bird(main: Node) -> void:
	var mgr: OverworldBird = main.area_loader.current_area.get_node_or_null("OverworldBird") as OverworldBird
	if mgr == null:
		return
	if mgr.bird != null and is_instance_valid(mgr.bird):
		mgr.bird.free()
	mgr.free()

func _by_role(main: Node, role: String) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for n in main.area_loader.current_area.get_children():
		if n is Enemy and _role(n) == role:
			out.append(n)
	return out

func _def_role(entry: Dictionary) -> String:
	var d := entry.get("definition") as EnemyDefinition
	if d == null or d.behavior == null:
		return "none"
	if d.behavior == EnemyBehaviorPatrol:
		return "patrol"
	if d.behavior == EnemyBehaviorMigrate:
		return "migrant"
	if d.behavior == EnemyBehaviorGuard:
		return "guard"
	if d.behavior is EnemyBehaviorFishy and d.behavior._notice_radius() == 420.0 and d.behavior._leash_radius() == 800.0:
		return "fishy" # #464: holds its post like a guard, casts from range
	return "other"

func _initialize() -> void:
	_scene_legs()
	await _flow_legs()
	print("[373] DONE failures=", failures)
	if failures == 0:
		print("RESULT: ALL PASS")
	quit(1 if failures > 0 else 0)

func _scene_legs() -> void:
	var ow: Node2D = load("res://scenes/overworld.tscn").instantiate()
	var ground := ow.get_node("Ground") as OverworldGround
	ground.build_from(ow)
	var spawn: Vector2 = (ow.get_node("PlayerSpawn") as Node2D).position
	var counts := {"guard": 0, "patrol": 0, "migrant": 0}
	var on_field := true
	for node in ow.get_node("EntranceGuards").get_children():
		var g := node as EntranceGuards
		var guards := 0
		var patrols_ok := true
		for entry: Dictionary in g.entries:
			var role := _def_role(entry)
			counts[role] = counts.get(role, 0) + 1
			if role == "guard":
				guards += 1
				_check(not entry.has("route"), "(A) %s gate guard has no route" % g.name)
			elif role == "fishy":
				_check(not entry.has("route"), "(A) %s Fishy (#464) holds a post, no route" % g.name)
			elif role == "patrol":
				var r: Array = entry.get("route", [])
				if r.size() < 3 or (r[0] as Vector2) != entry["position"]:
					patrols_ok = false
				for p: Vector2 in r:
					on_field = on_field and ground.covers(p)
			else:
				patrols_ok = false
		# #414: every guarded entrance keeps exactly ONE posted guard -
		# GuardsNormal's #392 slime post is now a slime PATROLLER.
		_check(guards == 1, "(A) %s has 1 gate guard (got %d)" % [g.name, guards])
		_check(patrols_ok, "(A) every other %s enemy patrols a closed loop starting at its spawn" % g.name)
	var roamers := ow.get_node_or_null("Roamers") as AreaSpawnData
	_check(roamers != null and not roamers is EntranceGuards, "(A) overworld has a Roamers carrier tied to no dungeon")
	var clear_of_spawn := true
	var long_paths := true
	if roamers:
		for entry: Dictionary in roamers.entries:
			var role := _def_role(entry)
			counts[role] = counts.get(role, 0) + 1
			_check(role == "migrant", "(A) roamer at %s is a migrant" % entry["position"])
			var r: Array = entry.get("route", [])
			var length := 0.0
			for i in r.size():
				on_field = on_field and ground.covers(r[i])
				if i > 0:
					length += (r[i] as Vector2).distance_to(r[i - 1])
					var q := Geometry2D.get_closest_point_to_segment(spawn, r[i - 1], r[i])
					clear_of_spawn = clear_of_spawn and q.distance_to(spawn) > EnemyBehaviorGuard.AGGRO_RADIUS + 150.0
			long_paths = long_paths and length > 900.0
	_check(long_paths, "(A) every migration path is long (> 900 px)")
	_check(clear_of_spawn, "(A) migration paths keep clear of the arrival point")
	_check(on_field, "(A) every route point is on the overworld field")
	_check(counts["guard"] == 5 and counts["patrol"] == 14 and counts["migrant"] == 4, "(A) #414 mix: 5 gate guards, 14 patrols, 4 migrants (%s)" % [counts])
	_check(counts["patrol"] + counts["migrant"] > counts["guard"], "(A) moving roles are the norm")
	ow.free()

func _flow_legs() -> void:
	Bestiary.save_path = "user://test373_bestiary.cfg"
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(3)
	var p: Player = main.get_node("Player")
	await _enter(main, "GateOverworld")
	var ow: Node2D = main.area_loader.current_area
	_remove_bird(main) # #478: role legs only
	_check(ow.name == "Overworld", "(B) in the overworld")
	var guards := _by_role(main, "guard")
	var patrols := _by_role(main, "patrol")
	var migrants := _by_role(main, "migrant")
	_check(guards.size() == 5 and patrols.size() == 14 and migrants.size() == 4, "(B) mounted 5 guards / 14 patrols / 4 migrants (#414, got %d/%d/%d)" % [guards.size(), patrols.size(), migrants.size()])
	_check(patrols.all(func(e: Enemy) -> bool: return (e._behavior as EnemyBehaviorGuard).route.size() >= 3), "(B) every patrol received its loop")
	_check(migrants.all(func(e: Enemy) -> bool: return (e._behavior as EnemyBehaviorGuard).route.size() >= 3), "(B) every migrant received its path")
	var start := {}
	for e in guards + patrols + migrants:
		start[e] = e.global_position

	# (C) 10 s with the player idle at the arrival point
	var corners := {}
	var max_off := {}
	for e in patrols:
		corners[e] = 0
		max_off[e] = 0.0
	var last_wp := {}
	for e in patrols:
		last_wp[e] = (e._behavior as EnemyBehaviorPatrol).waypoint
	for f in 600:
		await physics_frame
		for e in patrols:
			var b := e._behavior as EnemyBehaviorPatrol
			if b.waypoint != last_wp[e]:
				corners[e] += 1
				last_wp[e] = b.waypoint
			max_off[e] = maxf(max_off[e], e.global_position.distance_to(start[e]))
	var held := guards.all(func(e: Enemy) -> bool: return e.global_position.distance_to(start[e]) <= 2.0)
	_check(held, "(C) gate guards hold their posts")
	var walked := patrols.all(func(e: Enemy) -> bool: return corners[e] >= 3)
	_check(walked, "(C) every patrol walked >= 3 corners of its loop in 10 s (%s)" % [corners.values()])
	var on_beat := patrols.all(func(e: Enemy) -> bool: return max_off[e] <= 260.0)
	_check(on_beat, "(C) patrols stay on their beat (max %.0f px from spawn)" % max_off.values().max())
	var travelled := migrants.all(func(e: Enemy) -> bool: return e.global_position.distance_to(start[e]) > 250.0)
	_check(travelled, "(C) every migrant travelled > 250 px along its path")
	_check(patrols.all(func(e: Enemy) -> bool: return not (e._behavior as EnemyBehaviorGuard).engaged) and migrants.all(func(e: Enemy) -> bool: return not (e._behavior as EnemyBehaviorGuard).engaged), "(C) nobody engaged the idle player")
	_check(p.hp == p.max_hp, "(C) the idle player took no damage (hp %d)" % p.hp)

	# (D) a migrant completes its journey, rests, and comes back
	var m: Enemy = null
	for e in migrants:
		var r := (e._behavior as EnemyBehaviorMigrate).route
		if r[0].x < 0.0 and r[r.size() - 1].y < -500.0:
			m = e # the west-edge migrant
	var mb := m._behavior as EnemyBehaviorMigrate
	m.speed = 600.0 # fast-forward the journey; the logic is speed-independent
	var dest: Vector2 = mb.route[mb.route.size() - 1]
	var rested := false
	for f in 600:
		await physics_frame
		if mb.resting:
			rested = true
			break
	_check(rested and m.global_position.distance_to(dest) <= EnemyBehaviorGuard.HOME_EPSILON + 1.0, "(D) the migrant reached its destination and rests (%.1f px off)" % m.global_position.distance_to(dest))
	_check(mb.direction == -1, "(D) and turns around for the journey back")
	var at_rest := m.global_position
	await _frames(60)
	_check(m.global_position.distance_to(at_rest) <= 1.0, "(D) it stays put while resting")
	var home_again := false
	for f in 900:
		await physics_frame
		if m.global_position.distance_to(mb.route[0]) <= EnemyBehaviorGuard.HOME_EPSILON + 1.0:
			home_again = true
			break
	_check(home_again, "(D) after resting it migrates all the way back")

	# (E) moving roles keep aggro / leash; #414: the patrol's give-up
	# distance is the larger 900, then it RETURNS TO ITS OLD ROUTE.
	var pt: Enemy = patrols[0]
	var pb := pt._behavior as EnemyBehaviorPatrol
	p.global_position = pt.global_position + Vector2(0, -120)
	await _frames(20)
	_check(pb.engaged, "(E) a patrol engages a player inside its aggro radius")
	p.global_position = _open_ground(pt, pb.engaged_from, 700.0)
	await _frames(30)
	_check(pb.engaged, "(E) #414: still chasing at 700px (past the old 520 leash)")
	p.global_position = _open_ground(pt, pb.engaged_from, 1400.0)
	await _frames(4)
	_check(not pb.engaged, "(E) the patrol gives up past its 900px chase distance")
	var wp_before := pb.waypoint
	var resumed := false
	for f in 900:
		await physics_frame
		if pb.waypoint != wp_before:
			resumed = true
			break
	_check(resumed, "(E) #414: and returns to its old route (Daniel)")
	p.hp = p.max_hp
	var mg: Enemy = migrants[0]
	var mgb := mg._behavior as EnemyBehaviorMigrate
	p.global_position = mg.global_position + Vector2(0, 150)
	await _frames(20)
	_check(mgb.engaged, "(E) a migrant engages a player inside its aggro radius")
	p.global_position = mgb.engaged_from + Vector2(0, 1200)
	await _frames(4)
	_check(not mgb.engaged, "(E) the migrant gives up past its leash")
	var pos_before := mg.global_position
	await _frames(120)
	_check(mg.global_position.distance_to(pos_before) > 30.0, "(E) and continues its migration")
	p.hp = p.max_hp

	# (F) clearing DungeonA: its entrance enemies go, migrants stay
	p.global_position = (ow.get_node("PlayerSpawn") as Node2D).global_position
	await _enter(main, "GateNormal")
	for _round in 8: # #392: slimes split; kill until none remain
		var alive := get_nodes_in_group("enemies").filter(func(n): return is_instance_valid(n) and not n.is_queued_for_deletion())
		if alive.is_empty():
			break
		for e in alive:
			e.apply_damage(9999)
		await _frames(3)
	_check(main.area_loader.cleared_dungeons.has(&"dungeon_a"), "(F) DungeonA cleared")
	(main.area_loader.current_area.get_node("ExitPortal") as ExitPortal)._on_body_entered(p)
	await _frames(3) # #378: the exit lands back in the overworld at the DungeonA entrance
	var gate_a: Vector2 = main.area_loader.current_area.get_node("GateNormal").global_position
	var near_a := 0
	for e in _by_role(main, "guard") + _by_role(main, "patrol"):
		if e.global_position.distance_to(gate_a) <= 260.0:
			near_a += 1
	_check(near_a == 0, "(F) the cleared entrance has neither its gate guard nor its patrol")
	_check(_by_role(main, "guard").size() == 4 and _by_role(main, "patrol").size() == 11, "(F) 4 guards / 11 patrols remain (#414)")
	_check(_by_role(main, "migrant").size() == 4, "(F) all 4 migrants still roam")
