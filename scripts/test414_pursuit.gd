extends SceneTree
## #414 harness: overworld pursuit update (Daniel, 2026-11-09:
## "Patrollers should drop their route and follow the player using the
## cover mechanic. Make the chase distance larger", "have fewer guards
## and more patrollers", "moustache men periodically find nearby cover if
## holding cover for over 5s. Once they begin charging dont stop", and
## "return to its old route" for the post-chase state; 900px /
## 5-guards-14-patrollers tuning confirmed "yes that sounds good").
##   (A) scene data: every guarded entrance keeps exactly ONE posted
##       guard; Normal's slime post is now a slime PATROLLER with a route.
##   (B) patroller pursuit (fixture, no terrain): strolls its loop while
##       unaggroed; engages; keeps chasing at 700px (past the old 520
##       leash); gives up past the new 900; RETURNS TO ITS OLD ROUTE.
##   (C) the stationary guard is unchanged (production mount): engages,
##       gives up at its 520 post leash, walks home.
##   (D) the migrant is unchanged (production mount): engages, gives up
##       at 520, resumes its journey.
##   (E) cover hold-relocate (fixture, two covers): holding one cover
##       over 5s DASHes to a DIFFERENT nearby cover, even while aimed at.
##   (F) hold-relocate with no alternative cover: keeps holding the same
##       cover (aimed at, 7s).
##   (G) committed charge: once CHARGE begins, re-aiming at the mob never
##       breaks it; only contact ends it.
## Fixture idioms follow test406 (collisions off, real physics frames,
## harness-owned aim); production-mount legs follow test373.

const DT := 1.0 / 60.0

var failures := 0
var _player_scene: PackedScene
var _enemy_scene: PackedScene

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[414] ", label, " -> ", "PASS" if ok else "FAIL")

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _initialize() -> void:
	_player_scene = load("res://scenes/player.tscn")
	_enemy_scene = load("res://scenes/enemy.tscn")
	_scene_leg_a()
	await _production_legs_cd()
	await _leg_b_patrol_pursuit()
	await _leg_e_hold_relocate()
	await _leg_f_relocate_no_alternative()
	await _leg_g_committed_charge()
	print("[414] DONE failures=", failures)
	if failures == 0:
		print("RESULT: ALL PASS")
	quit(1 if failures > 0 else 0)

# --- fixture helpers (test406 idiom) -----------------------------------------

func _mk_stage(with_map: bool = true) -> Array:
	var stage := Node2D.new()
	stage.name = "Stage414"
	root.add_child(stage)
	var map: TerrainMap = null
	if with_map:
		map = TerrainMap.new()
		map.name = "Terrain"
		map.cell_size = 32
		stage.add_child(map)
	return [stage, map]

func _mk_player(stage: Node2D, pos: Vector2) -> Player:
	var p: Player = _player_scene.instantiate()
	p.name = "Player"
	p.collision_layer = 0
	p.collision_mask = 0
	p.set_process(false) # the harness owns player.rotation (aim)
	stage.add_child(p)
	p.global_position = pos
	p.set_physics_process(false)
	return p

func _mk_enemy(stage: Node2D, map: TerrainMap, pos: Vector2, definition: EnemyDefinition = null) -> Enemy:
	var e: Enemy = _enemy_scene.instantiate()
	e.collision_layer = 0
	e.collision_mask = 0
	e.player_path = NodePath("../Player")
	e.terrain = map
	if definition != null:
		e.definition = definition # before tree entry so _ready applies it
	e.set_physics_process(false)
	stage.add_child(e)
	e.global_position = pos
	return e

func _aim_at(p: Player, pos: Vector2) -> void:
	p.global_rotation = (pos - p.global_position).angle()

func _aim_away(p: Player, pos: Vector2) -> void:
	p.global_rotation = (pos - p.global_position).angle() + PI

func _cover(e: Enemy) -> RefCounted:
	return (e.get("_behavior") as RefCounted).get("_cover")

func _state(e: Enemy) -> int:
	return _cover(e).get("_state")

func _blocked_cell_on_segment(map: TerrainMap, a: Vector2, b: Vector2) -> bool:
	var dist := a.distance_to(b)
	var steps := int(ceil(dist / (map.cell_size * 0.5))) + 1
	for i in steps + 1:
		var cell := map.world_to_cell(a.lerp(b, float(i) / steps))
		if map.movement_at_cell(cell) == TerrainTypes.Movement.BLOCKING:
			return true
	return false

func _teardown(stage: Node2D) -> void:
	stage.queue_free()
	await process_frame
	await process_frame

# --- (A) scene data -----------------------------------------------------------

func _scene_leg_a() -> void:
	var ow: Node2D = load("res://scenes/overworld.tscn").instantiate()
	for node in ow.get_node("EntranceGuards").get_children():
		var g := node as EntranceGuards
		var guards := 0
		for entry: Dictionary in g.entries:
			var d := entry.get("definition") as EnemyDefinition
			if d != null and d.behavior == EnemyBehaviorGuard:
				guards += 1
		_check(guards == 1, "(A) %s keeps exactly one posted guard (got %d)" % [g.name, guards])
	var normal := ow.get_node("EntranceGuards/GuardsNormal") as EntranceGuards
	var slime_patrols := 0
	for entry: Dictionary in normal.entries:
		if (entry["enemy"] as PackedScene).resource_path == "res://scenes/enemy_slime.tscn":
			var d := entry.get("definition") as EnemyDefinition
			if d != null and d.behavior == EnemyBehaviorPatrol and entry.has("route"):
				slime_patrols += 1
	_check(slime_patrols == 1, "(A) Normal's slime is now a patroller with a route (#414)")
	ow.free()

# --- production-mount helpers (test373 idiom) ---------------------------------

func _enter(main: Node, gate_name: String) -> void:
	var gate: Gate = main.current_area.get_node(gate_name)
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

func _by_role(main: Node, role: String) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for n in main.current_area.get_children():
		if n is Enemy and _role(n) == role:
			out.append(n)
	return out

# --- (C)/(D) production mount: guard + migrant unchanged -----------------------

func _production_legs_cd() -> void:
	Bestiary.save_path = "user://test414_bestiary.cfg"
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(3)
	var p: Player = main.get_node("Player")
	await _enter(main, "GateOverworld")
	var ow: Node2D = main.current_area
	_check(ow.name == "Overworld", "(C/D) in the overworld")

	# (C) the stationary guard keeps its 520 post leash and walks home.
	var g0: Enemy = null
	for e in _by_role(main, "guard"):
		if e.global_position.distance_to(ow.get_node("GateRed").global_position) < 160.0:
			g0 = e
			break
	var post: Vector2 = g0.global_position
	p.global_position = post + Vector2(0, -150)
	await _frames(20)
	_check((g0._behavior as EnemyBehaviorGuard).engaged, "(C) the posted guard still engages")
	p.global_position = post + Vector2(0, 600)
	await _frames(6)
	_check(not (g0._behavior as EnemyBehaviorGuard).engaged, "(C) the guard still gives up at its 520 leash")
	for f in 300:
		p.hp = p.max_hp # harness pins HP: nearby patrollers may reach the player
		await physics_frame
	_check(g0.global_position.distance_to(post) <= EnemyBehaviorGuard.HOME_EPSILON + 1.0, "(C) and walks back to its post (%.1f px off)" % g0.global_position.distance_to(post))
	p.hp = p.max_hp

	# (D) the migrant keeps its 520 leash and resumes its journey.
	var migrants := _by_role(main, "migrant")
	var mg: Enemy = migrants[0]
	var mgb := mg._behavior as EnemyBehaviorMigrate
	p.global_position = mg.global_position + Vector2(0, 150)
	await _frames(20)
	_check(mgb.engaged, "(D) a migrant engages a player inside its aggro radius")
	p.global_position = mgb.engaged_from + Vector2(0, 700)
	await _frames(4)
	_check(not mgb.engaged, "(D) the migrant still gives up at its 520 leash")
	var pos_before := mg.global_position
	for f in 120:
		p.hp = p.max_hp
		await physics_frame
	_check(mg.global_position.distance_to(pos_before) > 30.0, "(D) and continues its migration")
	p.hp = p.max_hp
	# Leave the production scene quiet for the fixture legs: park the
	# player far from every enemy anchor.
	p.global_position = Vector2(-2000, 3000)
	await _frames(30)
	p.hp = p.max_hp

# --- (B) patroller pursuit (fixture, no terrain) -------------------------------

func _leg_b_patrol_pursuit() -> void:
	var s: Array = _mk_stage(false)
	var stage: Node2D = s[0]
	var p: Player = _mk_player(stage, Vector2(1000, 3000)) # far away at first
	var patrol_def: EnemyDefinition = load("res://resources/enemies/overworld_patrol.tres")
	var e: Enemy = _mk_enemy(stage, null, Vector2(1000, 1000), patrol_def)
	var b := e._behavior as EnemyBehaviorPatrol
	_check(b != null, "(B) the patrol definition builds a patrol behavior")
	b.configure_route(PackedVector2Array([Vector2(1000, 1000), Vector2(1100, 1000), Vector2(1100, 1100)]))
	await process_frame
	e.global_position = Vector2(1000, 1000)
	p.global_position = Vector2(1000, 3000)
	# Unaggroed: it strolls its loop.
	e.set_physics_process(true)
	await physics_frame
	for i in 150:
		await physics_frame
	_check(b.waypoint != 0, "(B) unaggroed it strolls its loop (waypoint advanced)")
	_check(not b.engaged, "(B) and never engaged the far-away player")
	# Engage.
	p.global_position = e.global_position + Vector2(0, -120)
	await _frames(20)
	_check(b.engaged, "(B) it engages a player inside its aggro radius")
	# Past the OLD 520 leash it keeps chasing (Daniel: larger chase distance).
	p.global_position = b.engaged_from + Vector2(0, 700)
	var dist_at_700: float = e.global_position.distance_to(p.global_position)
	for i in 150:
		await physics_frame
	_check(b.engaged, "(B) still chasing at 700px (past the old 520 leash)")
	_check(e.global_position.distance_to(p.global_position) < dist_at_700 - 100.0, "(B) it follows the player (closed > 100px)")
	# Past the NEW 900 leash it gives up...
	p.global_position = b.engaged_from + Vector2(0, 1400)
	await _frames(4)
	_check(not b.engaged, "(B) it gives up past the 900px chase distance")
	# ...and RETURNS TO ITS OLD ROUTE (Daniel). Fast-forward the stroll
	# speed like test373 (D): the logic is speed-independent.
	e.speed = 600.0
	var wp_before := b.waypoint
	var resumed := false
	for f in 900:
		await physics_frame
		if b.waypoint != wp_before:
			resumed = true
			break
	_check(resumed, "(B) it returns to its old route after giving up")
	_check(e.global_position.distance_to(Vector2(1100, 1000)) <= EnemyBehaviorGuard.HOME_EPSILON + 2.0, "(B) back on the loop at its waypoint")
	e.set_physics_process(false)
	await _teardown(stage)

# --- (E) cover hold-relocate ----------------------------------------------------

func _settle_hold(stage_data: Array, p: Player, e: Enemy) -> bool:
	e.set_physics_process(true)
	await physics_frame
	var settled := false
	for i in 400:
		_aim_at(p, e.global_position)
		await physics_frame
		if _state(e) == EnemyBehaviorCover.State.HOLD:
			settled = true
			break
	e.set_physics_process(false)
	return settled

func _leg_e_hold_relocate() -> void:
	var s: Array = _mk_stage()
	var stage: Node2D = s[0]
	var map: TerrainMap = s[1]
	map.set_cell(Vector2i(20, 20), TerrainTypes.OBSTACLE)
	map.set_cell(Vector2i(23, 20), TerrainTypes.OBSTACLE)
	var tree1: Vector2 = map.cell_to_world(Vector2i(20, 20))
	var tree2: Vector2 = map.cell_to_world(Vector2i(23, 20))
	var p: Player = _mk_player(stage, tree2 + Vector2(220, 0))
	var e: Enemy = _mk_enemy(stage, map, tree1 + Vector2(-220, 0))
	await process_frame
	e.global_position = tree1 + Vector2(-220, 0)
	p.global_position = tree2 + Vector2(220, 0)
	_check(await _settle_hold(s, p, e), "(E) settled into HOLD behind the first cover")
	var first_cover: Vector2 = _cover(e).get("_cover_pos")
	var first_hold := e.global_position
	# Keep aiming the whole time: over 5s of holding it must relocate.
	var saw_dash := false
	var relocated := false
	e.set_physics_process(true)
	await physics_frame
	for i in 600:
		_aim_at(p, e.global_position)
		await physics_frame
		if _state(e) == EnemyBehaviorCover.State.DASH:
			saw_dash = true
		if _state(e) == EnemyBehaviorCover.State.HOLD and (_cover(e).get("_cover_pos") as Vector2) != first_cover:
			relocated = true
			break
	e.set_physics_process(false)
	_check(saw_dash, "(E) #414: holding > 5s triggers a relocate DASH, even while aimed at")
	_check(relocated, "(E) it holds a DIFFERENT cover afterwards")
	_check(e.global_position.distance_to(first_hold) > 20.0, "(E) it actually moved")
	_check(_blocked_cell_on_segment(map, e.global_position, p.global_position), "(E) the new hold is sheltered")
	await _teardown(stage)

# --- (F) hold-relocate with no alternative --------------------------------------

func _leg_f_relocate_no_alternative() -> void:
	var s: Array = _mk_stage()
	var stage: Node2D = s[0]
	var map: TerrainMap = s[1]
	map.set_cell(Vector2i(20, 20), TerrainTypes.OBSTACLE)
	var tree: Vector2 = map.cell_to_world(Vector2i(20, 20))
	var p: Player = _mk_player(stage, tree + Vector2(220, 0))
	var e: Enemy = _mk_enemy(stage, map, tree + Vector2(-220, 0))
	await process_frame
	e.global_position = tree + Vector2(-220, 0)
	p.global_position = tree + Vector2(220, 0)
	_check(await _settle_hold(s, p, e), "(F) settled into HOLD")
	var first_cover: Vector2 = _cover(e).get("_cover_pos")
	var held := e.global_position
	e.set_physics_process(true)
	await physics_frame
	for i in 420: # 7s aimed: past the 5s relocate clock
		_aim_at(p, e.global_position)
		await physics_frame
	e.set_physics_process(false)
	_check(_state(e) == EnemyBehaviorCover.State.HOLD, "(F) no other cover around: it keeps HOLDing")
	_check((_cover(e).get("_cover_pos") as Vector2) == first_cover, "(F) same cover (relocate excludes the held one, finds none)")
	_check(e.global_position.distance_to(held) < 6.0, "(F) and does not wander")
	await _teardown(stage)

# --- (G) committed charge --------------------------------------------------------

func _leg_g_committed_charge() -> void:
	var s: Array = _mk_stage()
	var stage: Node2D = s[0]
	var map: TerrainMap = s[1]
	map.set_cell(Vector2i(20, 20), TerrainTypes.OBSTACLE)
	var tree: Vector2 = map.cell_to_world(Vector2i(20, 20))
	var p: Player = _mk_player(stage, tree + Vector2(220, 0))
	var e: Enemy = _mk_enemy(stage, map, tree + Vector2(-220, 0))
	await process_frame
	e.global_position = tree + Vector2(-220, 0)
	p.global_position = tree + Vector2(220, 0)
	_check(await _settle_hold(s, p, e), "(G) settled into HOLD first")
	# Mouse away until the charge begins.
	var charging := false
	e.set_physics_process(true)
	await physics_frame
	for i in 400:
		_aim_away(p, e.global_position)
		await physics_frame
		if _state(e) == EnemyBehaviorCover.State.CHARGE:
			charging = true
			break
	_check(charging, "(G) the 3s away-timer starts a charge")
	# Re-aim AT the mob the instant it charges: the charge must not stop.
	var broke := false
	var hp_before: int = p.hp
	for i in 300:
		_aim_at(p, e.global_position)
		await physics_frame
		if _state(e) != EnemyBehaviorCover.State.CHARGE and _state(e) != EnemyBehaviorCover.State.ENGAGED:
			broke = true
		if p.hp < hp_before:
			break
	e.set_physics_process(false)
	_check(not broke, "(G) #414: re-aiming never breaks a running charge (Daniel: dont stop)")
	_check(p.hp < hp_before, "(G) the committed charge runs all the way to contact")
	_check(_state(e) == EnemyBehaviorCover.State.ENGAGED, "(G) only contact ends it (then ENGAGED)")
	await _teardown(stage)
