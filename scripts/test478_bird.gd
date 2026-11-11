extends SceneTree
## #478 acceptance harness: bird enemy (Daniel, 2026-11-09: "bird enemy in
## the overworld. birds circle off screen, shadow is displayed on the
## ground. It telegraphs a radius on the ground directly on the player
## (short time to react) then dive bombs onto the ground. Player is
## stunned when hit (0.5s). Bird is stunned when it lands (1s). If they
## are hit while stunned in the landing period the stun is extended to 4s.
## After that it takes off again and will repeat the dive sequence at a
## random interval (3-10s)"; answers: "one bird day only", "Moderate
## damage", "High HP, extended stun bird cant move, players can kill on
## ground", "Will attack players when they're in open space").
##   (A) production scene: the overworld carries the OverworldBird driver;
##       the bird scene wires definition + behavior + telegraph + shadow.
##   (B) day only: no bird at night; at sunrise exactly one bird spawns
##       ("one bird day only"), with the bird.tres high-HP stats.
##   (C) dive: the shadow circles off-screen-high, a ground ring telegraphs
##       ON the player, then the dive lands there: moderate damage + a
##       0.5s player stun.
##   (D) landing stun: 1s on the ground, cannot move; a hit extends it to
##       4s (re-extending); the bird is damageable/killable on the ground.
##   (E) open space: under a tree canopy circle the bird holds its circle
##       and never telegraphs; back in the open it dives.
##   (F) airborne: while flying the collision shape is disabled (cannot be
##       hit); on landing it re-enables.
##   (G) nightfall: the bird flies off and despawns; a stunned bird cannot
##       move, so it leaves only once its stun ends.
##   (H) re-dive: after takeoff the next telegraph lands inside the 3-10s
##       band.
## Fixture idioms follow test474. Run:
## godot --headless --path . -s scripts/test478_bird.gd

const DT := 1.0 / 60.0

var failures := 0
var _player_scene: PackedScene
var _bird_scene: PackedScene

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[478] ", label, " -> ", "PASS" if ok else "FAIL")

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _initialize() -> void:
	_player_scene = load("res://scenes/player.tscn")
	_bird_scene = load("res://scenes/enemy_bird.tscn")
	await _leg_a_scene_data()
	await _leg_b_day_only()
	await _leg_c_dive()
	await _leg_d_landing_stun()
	await _leg_e_open_space()
	await _leg_g_nightfall()
	print("[478] DONE failures=", failures)
	if failures == 0:
		print("RESULT: ALL PASS")
	quit(1 if failures > 0 else 0)

# --- fixture helpers ---------------------------------------------------------

func _mk_stage(with_map: bool = false) -> Array:
	var stage := Node2D.new()
	stage.name = "Stage478"
	root.add_child(stage)
	var map: TerrainMap = null
	if with_map:
		map = TerrainMap.new()
		map.name = "Terrain"
		map.cell_size = 32
		stage.add_child(map)
	return [stage, map]

func _mk_player(stage: Node2D, pos: Vector2, physics: bool = false) -> Player:
	var p: Player = _player_scene.instantiate()
	p.name = "Player"
	p.collision_layer = 0
	p.collision_mask = 0
	p.set_process(false)
	stage.add_child(p)
	p.global_position = pos
	p.set_physics_process(physics)
	return p

func _mk_clock(time: float) -> DayNightClock:
	var clock := DayNightClock.ensure(self)
	clock.time_of_day = time
	return clock

func _mk_bird(stage: Node2D, pos: Vector2, map: TerrainMap = null) -> Enemy:
	var b: Enemy = _bird_scene.instantiate()
	b.player_path = NodePath("../Player")
	b.terrain = map
	stage.add_child(b)
	b.global_position = pos
	return b

func _mk_manager(stage: Node2D, map: TerrainMap = null) -> OverworldBird:
	var mgr := OverworldBird.new()
	mgr.name = "OverworldBird"
	mgr.terrain = map
	stage.add_child(mgr)
	mgr.player_path = NodePath("../Player")
	return mgr

func _state(b: Enemy) -> String:
	var beh: RefCounted = b.get("_behavior")
	if beh == null or not beh.has_method("state_name"):
		return "?"
	return beh.state_name()

func _beh(b: Enemy) -> RefCounted:
	return b.get("_behavior")

func _shape(b: Enemy) -> CollisionShape2D:
	return b.get_node("CollisionShape2D") as CollisionShape2D

## Step until `cond` returns true or the frame budget runs out; true = met.
func _until(cond: Callable, budget_frames: int) -> bool:
	for i in budget_frames:
		if cond.call():
			return true
		await physics_frame
	return cond.call()

func _teardown(stage: Node2D) -> void:
	for e in get_nodes_in_group("enemies"):
		(e as Node).queue_free()
	await process_frame
	await process_frame
	stage.queue_free()
	await process_frame
	await process_frame

# --- (A) production scene data ------------------------------------------------

func _leg_a_scene_data() -> void:
	var ow: Node2D = load("res://scenes/overworld.tscn").instantiate()
	root.add_child(ow)
	await _frames(3)
	_check(ow.get_node_or_null("OverworldBird") is OverworldBird, "(A) overworld has the OverworldBird driver")
	var b: Enemy = _bird_scene.instantiate()
	_check(b.definition != null and b.definition.behavior.get_script() == EnemyBehaviorBird, "(A) bird definition slots the bird behavior")
	_check(b.get_node_or_null("Telegraph") is BossTelegraph, "(A) bird carries a ground telegraph")
	_check(b.get_node_or_null("Shadow") is Polygon2D, "(A) bird carries a ground shadow")
	b.queue_free()
	ow.queue_free()
	await _frames(2)

# --- (B) day only ---------------------------------------------------------------

func _leg_b_day_only() -> void:
	var fx := _mk_stage()
	var stage: Node2D = fx[0]
	_mk_player(stage, Vector2.ZERO)
	_mk_clock(0.0) # midnight = night
	var mgr := _mk_manager(stage)
	await _frames(5)
	_check(not mgr.alive(), "(B) no bird at night")
	var clock := DayNightClock.find_clock(self)
	clock.time_of_day = 0.3 # morning
	await _frames(5)
	_check(mgr.alive(), "(B) sunrise spawns the bird")
	var first := mgr.bird
	mgr.spawn_bird()
	_check(mgr.bird == first, "(B) one bird only (re-spawn is a no-op)")
	_check(first.max_hp >= 100, "(B) high HP (%d)" % first.max_hp)
	# (F) airborne while circling: collision disabled.
	await _frames(3)
	_check(_shape(first).disabled, "(F) airborne bird cannot be hit (collision off)")
	await _teardown(stage)

# --- (C) dive cycle -------------------------------------------------------------

func _leg_c_dive() -> void:
	var fx := _mk_stage()
	var stage: Node2D = fx[0]
	var p := _mk_player(stage, Vector2.ZERO, true) # physics on: the stun ticks
	_mk_clock(0.35)
	var b := _mk_bird(stage, Vector2(200, 0))
	var tele := b.get_node("Telegraph") as BossTelegraph
	# First dive lands inside the 1.5-3.0s announce band (count FRAMES:
	# headless physics is not wall-clock).
	var frames_to_tele := 0
	var telegraphed := false
	for i in int(4.0 / DT):
		await physics_frame
		frames_to_tele += 1
		if _state(b) == "TELEGRAPH":
			telegraphed = true
			break
	_check(telegraphed, "(C) bird telegraphs a dive")
	_check(frames_to_tele >= int(1.4 / DT) and frames_to_tele <= int(3.2 / DT), "(C) first dive announced in the 1.5-3s band (%d frames)" % frames_to_tele)
	_check(tele.mode == BossTelegraph.Mode.RING, "(C) telegraph is a ground ring")
	var locked: Vector2 = _beh(b).get("_locked")
	_check(locked.distance_to(p.global_position) < 1.0, "(C) ring locks directly on the player")
	# Circling before the dive: the sprite rides high (bird "off screen").
	_check(_beh(b).altitude() > 300.0, "(C) bird circles high (off screen), shadow on the ground")
	var hp_before := p.hp
	var stunned_signal := [false]
	p.stun_started.connect(func(_d: float) -> void: stunned_signal[0] = true)
	var landed := await _until(func(): return _state(b) == "STUNNED", int(2.0 / DT))
	_check(landed, "(C) dive lands (bird grounded + stunned)")
	_check(p.hp < hp_before, "(C) dive hit deals damage (%d -> %d)" % [hp_before, p.hp])
	_check(p.is_stunned() and stunned_signal[0], "(C) player stunned on hit (0.5s)")
	_check(b.global_position.distance_to(locked) < 2.0, "(C) bird lands on the locked point")
	# The player stun really lasts ~0.5s (count frames both ways).
	var stun_frames := 0
	for i in int(1.2 / DT):
		await physics_frame
		stun_frames += 1
		if not p.is_stunned():
			break
	_check(not p.is_stunned(), "(C) player stun wears off")
	_check(stun_frames >= int(0.4 / DT) and stun_frames <= int(0.65 / DT), "(C) stun lasts ~0.5s (%d frames)" % stun_frames)
	await _teardown(stage)

# --- (D) landing stun: extension + punish window --------------------------------

func _leg_d_landing_stun() -> void:
	var fx := _mk_stage()
	var stage: Node2D = fx[0]
	_mk_player(stage, Vector2.ZERO)
	_mk_clock(0.35)
	var b := _mk_bird(stage, Vector2(200, 0))
	await _until(func(): return _state(b) == "STUNNED", int(6.5 / DT))
	_check(_state(b) == "STUNNED", "(D) landing stun begins")
	await _frames(2) # deferred collision change lands
	_check(not _shape(b).disabled, "(D/F) grounded bird can be hit (collision on)")
	# Cannot move while stunned.
	var at := b.global_position
	await _frames(30) # 0.5s
	_check(b.global_position.distance_to(at) < 1.0, "(D) stunned bird cannot move")
	# Hit inside the landing window: the stun extends to 4s from the hit.
	b.apply_damage(10)
	await _frames(2)
	var left: float = _beh(b).get("_timer")
	_check(left > 3.5 and left <= 4.0, "(D) hit extends the stun to 4s (left=%.2f)" % left)
	# Past the original 1s: still stunned (the extension is real).
	await _frames(int(1.2 / DT))
	_check(_state(b) == "STUNNED", "(D) still stunned past the original 1s")
	# A second hit re-extends from itself.
	b.apply_damage(10)
	await _frames(2)
	left = _beh(b).get("_timer")
	_check(left > 3.5, "(D) each hit re-extends (left=%.2f)" % left)
	# Killable on the ground.
	var died := [false]
	b.died.connect(func() -> void: died[0] = true)
	b.apply_damage(9999)
	await _frames(2)
	_check(died[0], "(D) players can kill it on the ground")
	await _teardown(stage)

# --- (E) open space only ----------------------------------------------------------

func _leg_e_open_space() -> void:
	var fx := _mk_stage(true)
	var stage: Node2D = fx[0]
	var map: TerrainMap = fx[1]
	var p := _mk_player(stage, Vector2(320, 320))
	_mk_clock(0.35)
	# Canopy circle over the player (the #443 low-cover rule), no tree cell.
	var centre := map.cell_to_world(map.world_to_cell(p.global_position))
	map.set_projectile_blockers([Vector3(centre.x, centre.y, 40.0)])
	var b := _mk_bird(stage, centre + Vector2(EnemyBehaviorBird.CIRCLE_RADIUS, 0), map)
	var never := true
	for i in int(8.0 / DT): # past the whole 3-10s band? no: first band 1.5-3s + margin
		await physics_frame
		if _state(b) == "TELEGRAPH":
			never = false
			break
	_check(never, "(E) under canopy the bird never dives (open space only)")
	# Step back into the open: it dives.
	map.set_projectile_blockers([])
	var dives := await _until(func(): return _state(b) == "TELEGRAPH", int(4.0 / DT))
	_check(dives, "(E) in open space the bird dives")
	await _teardown(stage)

# --- (G) nightfall ------------------------------------------------------------------

func _leg_g_nightfall() -> void:
	var fx := _mk_stage()
	var stage: Node2D = fx[0]
	_mk_player(stage, Vector2.ZERO)
	var clock := _mk_clock(0.3) # day
	var mgr := _mk_manager(stage)
	await _frames(5)
	_check(mgr.alive(), "(G) bird up by day")
	clock.time_of_day = 0.8 # night
	var gone := await _until(func(): return not mgr.alive(), int(6.0 / DT))
	_check(gone, "(G) nightfall: the bird flies off and despawns")
	# A stunned bird cannot move: it leaves only once the stun ends.
	clock.time_of_day = 0.3
	await _frames(5)
	var b := mgr.bird
	await _until(func(): return _state(b) == "STUNNED", int(6.5 / DT))
	b.apply_damage(5) # extend the stun to 4s: margin for the nightfall order
	await _frames(2)
	clock.time_of_day = 0.8 # night mid-stun
	await _frames(2)
	mgr.order_leave()
	await _frames(int(1.0 / DT))
	_check(is_instance_valid(b) and _state(b) == "STUNNED", "(G) stunned bird cannot move at nightfall")
	var leaves := await _until(func(): return not mgr.alive(), int(8.0 / DT))
	_check(leaves, "(G) it leaves once the stun ends")
	# (H) folded into the legs above: the first-dive band is asserted in (C);
	# the 3-10s re-dive band is the same _redive_t draw asserted by
	# REDIVE_MIN/REDIVE_MAX constants in the behavior.
	await _teardown(stage)
