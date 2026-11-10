extends SceneTree
## #464 harness: the Fishy enemy. Sprite frames, tankiness, the straight-line
## hook (lands / misses after the aim locks / cancelled by terrain), reel-in
## + damage over time, line snaps (dash), the Mustache Warrior rally, the
## overworld post/notice variant, spawn wiring and the bestiary entry.

const DT := 1.0 / 60.0
const FISHY := preload("res://scenes/enemy_fishy.tscn")
const WARRIOR := preload("res://scenes/enemy.tscn")
const PLAYER := preload("res://scenes/player.tscn")
const OVERWORLD_FISHY_DEF := preload("res://resources/enemies/overworld_fishy.tres")
const GUARD_DEF := preload("res://resources/enemies/overworld_guard.tres")

var failures := 0

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[464] ", name, " -> PASS")
	else:
		failures += 1
		print("[464] ", name, " -> FAIL")

func _initialize() -> void:
	await _leg_a_art_and_stats()
	await _leg_b_hook_reel_dot()
	await _leg_c_aim_locks_straight_line()
	await _leg_d_terrain_cancels()
	await _leg_e_dash_snaps_line()
	await _leg_f_rally_warriors()
	await _leg_g_overworld_post()
	await _leg_h_spawn_wiring()
	await _leg_i_death_corpse()
	print("[464] failures: ", failures)
	if failures == 0:
		print("RESULT: ALL PASS")
	quit(1 if failures > 0 else 0)

# --- fixtures ---------------------------------------------------------------

func _mk_stage(with_map: bool = true) -> Array:
	var stage := Node2D.new()
	stage.name = "Stage"
	root.add_child(stage)
	var map: TerrainMap = null
	if with_map:
		map = TerrainMap.new()
		map.name = "Terrain"
		map.cell_size = 32
		stage.add_child(map)
	return [stage, map]

func _mk_player(stage: Node2D, pos: Vector2) -> Player:
	var p: Player = PLAYER.instantiate()
	p.name = "Player"
	p.collision_layer = 0
	p.collision_mask = 0
	p.set_process(false)
	stage.add_child(p)
	p.global_position = pos
	p.set_physics_process(false)
	return p

func _mk(scene: PackedScene, stage: Node2D, map: TerrainMap, pos: Vector2, def: EnemyDefinition = null) -> Enemy:
	var e: Enemy = scene.instantiate()
	e.collision_layer = 0
	e.collision_mask = 0
	e.player_path = NodePath("../Player")
	e.terrain = map
	if def != null:
		e.definition = def
	e.set_physics_process(false)
	stage.add_child(e)
	e.global_position = pos
	return e

func _beh(e: Enemy) -> EnemyBehaviorFishy:
	return e.get("_behavior") as EnemyBehaviorFishy

func _drive(e: Enemy, frames: int) -> void:
	for i in frames:
		if is_instance_valid(e):
			e._physics_process(DT)

## Steps until the Fishy reaches `state` (or `limit` frames). Returns frames used.
func _drive_until(e: Enemy, state: int, limit: int = 240) -> int:
	for i in limit:
		if _beh(e).state == state:
			return i
		e._physics_process(DT)
	return limit

# --- legs -------------------------------------------------------------------

func _leg_a_art_and_stats() -> void:
	var stage: Node2D = _mk_stage(false)[0]
	_mk_player(stage, Vector2(2000, 0))
	var f := _mk(FISHY, stage, null, Vector2.ZERO)
	await process_frame
	var sf: SpriteFrames = f.sprite.sprite_frames
	var want := {&"idle": 4, &"walk": 4, &"attack": 2, &"hurt": 2, &"death": 2, &"cast": 5, &"cast_hold": 1, &"reel": 4, &"retract": 4, &"hook": 1}
	var ok := true
	for anim in want:
		if not sf.has_animation(anim) or sf.get_frame_count(anim) != want[anim]:
			ok = false
			print("  missing/odd anim ", anim)
	_check(ok, "A: fishy_frames has idle/walk/attack/hurt/death/cast/cast_hold/reel/retract/hook")
	_check(sf.get_animation_loop(&"reel") and not sf.get_animation_loop(&"cast") and not sf.get_animation_loop(&"death"), "A: reel loops, cast and death are one-shots")
	var img := sf.get_frame_texture(&"idle", 0).get_image()
	var green := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.5 and c.g > c.r + 0.12 and c.g > c.b + 0.12:
				green += 1
	_check(green > 40, "A: idle frame shows the green hair (%d px)" % green)
	_check(f.get("_behavior") is EnemyBehaviorFishy, "A: definition behavior slot is the Fishy")
	var warrior: Enemy = WARRIOR.instantiate()
	var slime: Enemy = load("res://scenes/enemy_slime.tscn").instantiate()
	stage.add_child(warrior)
	stage.add_child(slime)
	await process_frame
	var min_boss := 1 << 30
	for path in ["mustache_warlord", "head_boss", "beast_boss", "defense_wave_boss"]:
		min_boss = mini(min_boss, (load("res://resources/enemies/%s.tres" % path) as EnemyDefinition).max_hp)
	_check(f.max_hp > 2 * maxi(warrior.max_hp, slime.max_hp) - 20 and f.max_hp < min_boss, "A: tankier than normal enemies (%d vs %d/%d), below every boss (%d)" % [f.max_hp, warrior.max_hp, slime.max_hp, min_boss])
	_check(OVERWORLD_FISHY_DEF.max_hp == f.max_hp and OVERWORLD_FISHY_DEF.behavior == EnemyBehaviorFishyGuard, "A: overworld definition keeps the stats, swaps in the post/notice behavior")
	stage.queue_free()
	await process_frame

func _leg_b_hook_reel_dot() -> void:
	var s := _mk_stage()
	var stage: Node2D = s[0]
	var p := _mk_player(stage, Vector2(700, 400))
	var f := _mk(FISHY, stage, s[1], Vector2(400, 400))
	await process_frame
	var b := _beh(f)
	_drive_until(f, EnemyBehaviorFishy.State.WINDUP)
	_check(b.state == EnemyBehaviorFishy.State.WINDUP, "B: in range with a clear line -> winds up a cast")
	_check(f.sprite.current_action() == &"cast", "B: wind-up plays the cast animation")
	var tele := f.get_node("Telegraph") as BossTelegraph
	_check(tele.mode == BossTelegraph.Mode.LINE, "B: wind-up shows the line telegraph")
	_drive_until(f, EnemyBehaviorFishy.State.CAST)
	_drive(f, 1)
	var line := f.get_node("FishingLine") as FishingLine
	_check(line.active, "B: the line is drawn while the hook flies")
	_drive_until(f, EnemyBehaviorFishy.State.HOOKED, 60)
	_check(b.is_hooked() and b.hooked_player == p, "B: the hook lands on the player in its lane")
	_check(f.sprite.current_action() == &"reel", "B: hooked -> reel animation")
	var hp0 := p.hp
	var d0 := p.global_position.distance_to(f.global_position)
	_drive(f, 30)
	var d1 := p.global_position.distance_to(f.global_position)
	_check(d1 < d0 - 150.0, "B: the player is reeled in toward the Fishy (%.0f -> %.0f px in 0.5s)" % [d0, d1])
	_check(p.hp < hp0, "B: the line deals damage while hooked (%d -> %d)" % [hp0, p.hp])
	_check(line.taut, "B: the line is taut while reeling")
	_drive_until(f, EnemyBehaviorFishy.State.RECOVER, 120)
	_check(b.last_result == &"reeled", "B: reel ends when the player arrives (%s)" % b.last_result)
	_check(p.global_position.distance_to(f.global_position) <= EnemyBehaviorFishy.REEL_STOP + 1.0, "B: player ends next to the Fishy")
	_drive_until(f, EnemyBehaviorFishy.State.APPROACH, 120)
	_drive(f, 1)
	_check(not line.active, "B: the line is reeled back in afterwards")
	stage.queue_free()
	await process_frame

func _leg_c_aim_locks_straight_line() -> void:
	var s := _mk_stage()
	var stage: Node2D = s[0]
	var p := _mk_player(stage, Vector2(900, 400))
	var f := _mk(FISHY, stage, s[1], Vector2(400, 400))
	await process_frame
	var b := _beh(f)
	_drive_until(f, EnemyBehaviorFishy.State.WINDUP)
	var frames_to_lock := int(ceil(EnemyBehaviorFishy.AIM_LOCK_AT / DT)) + 1
	_drive(f, frames_to_lock)
	var locked := b.aim_dir
	p.global_position += Vector2(0, 120) # sidestep after the lock
	_drive_until(f, EnemyBehaviorFishy.State.CAST)
	_check(b.aim_dir.is_equal_approx(locked), "C: the aim stays locked after AIM_LOCK_AT")
	var hp0 := p.hp
	var start := b.hook_pos
	_drive_until(f, EnemyBehaviorFishy.State.RECOVER, 120)
	_check(b.last_result == &"miss" and p.hp == hp0, "C: a sidestepped cast misses (%s)" % b.last_result)
	var flown := b.hook_pos - start
	_check(absf(flown.normalized().cross(locked)) < 0.001, "C: the hook flew in a straight line")
	_check(flown.length() >= EnemyBehaviorFishy.HOOK_RANGE - 1.0 and EnemyBehaviorFishy.HOOK_RANGE >= 500.0, "C: very long range (%.0f px)" % flown.length())
	stage.queue_free()
	await process_frame

func _leg_d_terrain_cancels() -> void:
	var s := _mk_stage()
	var stage: Node2D = s[0]
	var map: TerrainMap = s[1]
	var p := _mk_player(stage, Vector2(800, 400))
	var f := _mk(FISHY, stage, map, Vector2(400, 400))
	await process_frame
	var b := _beh(f)
	_drive_until(f, EnemyBehaviorFishy.State.WINDUP)
	# A wall appears in the lane after the wind-up started.
	# Long enough that the Fishy cannot walk around it within the leg.
	var wall := map.world_to_cell(Vector2(600, 400))
	for dy in range(-20, 21):
		map.set_cell(wall + Vector2i(0, dy), TerrainTypes.OBSTACLE)
	var hp0 := p.hp
	_drive_until(f, EnemyBehaviorFishy.State.RECOVER, 120)
	_check(b.last_result == &"terrain", "D: the cast is cancelled when the hook hits terrain (%s)" % b.last_result)
	_check(not b.is_hooked() and p.hp == hp0, "D: the player behind the wall is not hooked")
	var wall_x := map.cell_to_world(wall).x - map.cell_size * 0.5
	# Sampled at quarter-cell steps, so the stop is within 8 px of the face.
	_check(b.hook_pos.x <= wall_x + map.cell_size * 0.25 + 1.0 and b.hook_pos.x > wall_x - 20.0, "D: the hook stops at the wall face (x %.1f, wall %.1f)" % [b.hook_pos.x, wall_x])
	# With the wall still there the Fishy will not start another cast.
	_drive(f, 240)
	_check(b.state != EnemyBehaviorFishy.State.WINDUP and b.state != EnemyBehaviorFishy.State.CAST, "D: no cast while terrain blocks the line")
	# Tree canopies (#407 projectile blockers) cancel it too.
	for dy in range(-20, 21):
		map.clear_cell(wall + Vector2i(0, dy))
	var blockers: Array[Vector3] = [Vector3(600, 400, 20)]
	map.set_projectile_blockers(blockers)
	f.global_position = Vector2(400, 400)
	b.state = EnemyBehaviorFishy.State.APPROACH
	b.set("_cooldown", 0.0)
	b._begin_windup(f, p)
	_drive_until(f, EnemyBehaviorFishy.State.RECOVER, 120)
	_check(b.last_result == &"terrain", "D: a tree canopy cancels the cast too (%s)" % b.last_result)
	stage.queue_free()
	await process_frame

func _leg_e_dash_snaps_line() -> void:
	var s := _mk_stage()
	var stage: Node2D = s[0]
	var p := _mk_player(stage, Vector2(750, 400))
	var f := _mk(FISHY, stage, s[1], Vector2(400, 400))
	await process_frame
	var b := _beh(f)
	_drive_until(f, EnemyBehaviorFishy.State.HOOKED)
	_check(b.is_hooked(), "E: hooked")
	_drive(f, 5)
	_check(p.try_dash(Vector2.RIGHT), "E: player dashes")
	_drive(f, 1)
	_check(not b.is_hooked() and b.last_result == &"dash", "E: a dash snaps the line (%s)" % b.last_result)
	stage.queue_free()
	await process_frame

func _leg_f_rally_warriors() -> void:
	var s := _mk_stage()
	var stage: Node2D = s[0]
	var map: TerrainMap = s[1]
	var p := _mk_player(stage, Vector2(750, 400))
	var f := _mk(FISHY, stage, map, Vector2(400, 400))
	# A cover-seeking Mustache Warrior with a wall to hide behind...
	var w := _mk(WARRIOR, stage, map, Vector2(420, 560))
	map.set_cell(map.world_to_cell(Vector2(500, 560)), TerrainTypes.OBSTACLE)
	# ...an overworld guard far outside its own aggro radius but in earshot...
	var g := _mk(WARRIOR, stage, map, Vector2(300, 150), GUARD_DEF)
	# ...and a warrior out of earshot.
	var far := _mk(WARRIOR, stage, map, Vector2(-900, 400))
	await process_frame
	var b := _beh(f)
	_check(not w.is_rallied() and not g.is_rallied(), "F: nobody is rallied before the hook lands")
	_drive_until(f, EnemyBehaviorFishy.State.HOOKED)
	_drive(f, 1)
	_check(w.is_rallied() and g.is_rallied(), "F: hooking the player rallies nearby warriors")
	_check(not far.is_rallied() and not f.is_rallied(), "F: warriors out of earshot (and the Fishy itself) are not rallied")
	_check(is_equal_approx(w.chase_speed(), w.speed * Enemy.RALLY_SPEED_MULT), "F: rallied warriors move faster")
	var wd0 := w.global_position.distance_to(p.global_position)
	var gd0 := g.global_position.distance_to(p.global_position)
	for i in 30:
		f._physics_process(DT)
		w._physics_process(DT)
		g._physics_process(DT)
	_check(w.global_position.distance_to(p.global_position) < wd0 - 40.0, "F: the warrior leaves cover and groups up on the hooked player")
	var gb := g.get("_behavior") as EnemyBehaviorGuard
	_check(gb.engaged and g.global_position.distance_to(p.global_position) < gd0 - 40.0, "F: the overworld guard engages on the rally")
	_check(b.rally_allies(f) == 2, "F: rally_allies counts the two warriors in earshot")
	# Rally wears off.
	stage.remove_child(f)
	f.free()
	for i in int(ceil(EnemyBehaviorFishy.RALLY_TIME / DT)) + 2:
		w._physics_process(DT)
	_check(not w.is_rallied(), "F: the rally wears off after RALLY_TIME")
	stage.queue_free()
	await process_frame

func _leg_g_overworld_post() -> void:
	var s := _mk_stage()
	var stage: Node2D = s[0]
	var p := _mk_player(stage, Vector2(1000, 400))
	var f := _mk(FISHY, stage, s[1], Vector2(400, 400), OVERWORLD_FISHY_DEF)
	await process_frame
	var b := _beh(f)
	_check(b is EnemyBehaviorFishyGuard, "G: overworld definition -> post/notice behavior")
	_drive(f, 180)
	_check(b.state == EnemyBehaviorFishy.State.APPROACH and f.global_position.distance_to(Vector2(400, 400)) < 2.0, "G: holds its post while the player is beyond NOTICE_RADIUS")
	p.global_position = Vector2(400 + EnemyBehaviorFishyGuard.NOTICE_RADIUS - 40.0, 400)
	_drive_until(f, EnemyBehaviorFishy.State.WINDUP)
	_check(b.engaged and b.state == EnemyBehaviorFishy.State.WINDUP, "G: notices the player inside NOTICE_RADIUS and casts")
	stage.queue_free()
	await process_frame

func _fishy_count(entries: Array) -> Array:
	var fishy := 0
	var warriors := 0
	for e in entries:
		var path := (e["enemy"] as PackedScene).resource_path
		if path == "res://scenes/enemy_fishy.tscn":
			fishy += 1
		elif path == "res://scenes/enemy.tscn":
			warriors += 1
	return [fishy, warriors]

func _walkable_entries(area: Node2D, entries: Array) -> bool:
	var map := area.get_node_or_null("Terrain") as TerrainMap
	if map == null:
		return true
	for e in entries:
		if (e["enemy"] as PackedScene).resource_path != "res://scenes/enemy_fishy.tscn":
			continue
		var at := area.to_global(e["position"])
		if not map.is_walkable_at(at):
			print("  fishy spawn on blocked terrain at ", e["position"])
			return false
	return true

func _leg_h_spawn_wiring() -> void:
	for path in ["res://scenes/dungeon_a.tscn", "res://scenes/dungeon_b.tscn"]:
		var area: Node2D = load(path).instantiate()
		root.add_child(area)
		await process_frame
		var data := area.get_node("SpawnData") as AreaSpawnData
		var c := _fishy_count(data.entries)
		_check(c[0] >= 1 and c[0] < c[1], "H: %s spawns Fishy, fewer than Mustache Warriors (%d vs %d)" % [path.get_file(), c[0], c[1]])
		_check(_walkable_entries(area, data.entries), "H: %s Fishy spawn is on walkable ground" % path.get_file())
		area.queue_free()
		await process_frame
	var ow: Node2D = load("res://scenes/overworld.tscn").instantiate()
	root.add_child(ow)
	await process_frame
	var total := [0, 0]
	var all_def := true
	for camp in ow.get_node("EntranceGuards").get_children():
		var c := _fishy_count(camp.entries)
		total[0] += c[0]
		total[1] += c[1]
		for e in camp.entries:
			if (e["enemy"] as PackedScene).resource_path == "res://scenes/enemy_fishy.tscn" and e.get("definition") != OVERWORLD_FISHY_DEF:
				all_def = false
		_check(_walkable_entries(ow, camp.entries), "H: overworld %s Fishy spawns are walkable" % camp.name)
	_check(total[0] >= 1 and total[0] * 4 <= total[1], "H: overworld camps carry Fishy, much rarer than warriors (%d vs %d)" % [total[0], total[1]])
	_check(all_def, "H: overworld Fishy uses the post/notice definition")
	ow.queue_free()
	await process_frame
	var ids := []
	for entry in Bestiary.CATALOG:
		ids.append(entry["id"])
	_check(ids.has(&"fishy") and Bestiary.id_for_scene("res://scenes/enemy_fishy.tscn") == &"fishy", "H: Fishy has a bestiary entry")

func _leg_i_death_corpse() -> void:
	var stage: Node2D = _mk_stage(false)[0]
	_mk_player(stage, Vector2(2000, 0))
	var f := _mk(FISHY, stage, null, Vector2.ZERO)
	await process_frame
	var died := [false]
	f.died.connect(func() -> void: died[0] = true)
	f.apply_damage(f.max_hp)
	await process_frame
	_check(died[0] and not is_instance_valid(f), "I: Fishy dies and frees itself (died contract)")
	_check(get_nodes_in_group(&"enemy_corpses").size() >= 1, "I: a corpse plays the death animation")
	stage.queue_free()
	await process_frame
