extends SceneTree
## #420 harness: the barricade object and the barricade-deploying Moustache
## variant (Daniel, 2026-11-09: high-HP wooden structure, blocks spells,
## destroyed by players, decays from placement for at most 30s; deployed as
## cover by a special moustache man who runs to open space when there is no
## viable cover toward the player; "a variant and a separate entry in the
## bestiary"; "block both friendly and enemy - piercing and lobbed spells
## are not blocked. Any player source damage").
##
## Legs:
##   (A) variant: own scene + definition + behavior + bestiary entry; the
##       regular Mustache Warrior scene is untouched.
##   (B) barricade joins "cover" and "barricades", starts at max_hp.
##   (C) decay: drains max_hp / 30 per second; alive at 29s, gone at 30s.
##   (D) player ordinary shot: damages and is blocked (despawns at it).
##   (E) enemy ordinary shot: blocked, no damage.
##   (F) player piercing shot: passes through (damages once).
##   (G) enemy piercing shot: passes through, no damage.
##   (H) lobbed rock: passes over, no damage.
##   (I) player-owned summon's shot damages it; ownerless summon's does not.
##   (J) non-projectile player damage (Water splash dispatch) is accepted.
##   (K) barricader in open ground with no cover: deploys a barricade
##       between itself and the player, then HOLDs behind it.
##   (L) cover exists (a tree toward the player): no barricade.
##   (M) not open where it stands (wall right behind): it runs to open
##       space first, then deploys clear of the wall.
##   (N) a regular Mustache Warrior never deploys.
##   (O) one live barricade per deployer.

const DT := 1.0 / 60.0

var failures := 0
var _player_scene: PackedScene = preload("res://scenes/player.tscn")
var _barricader_scene: PackedScene = preload("res://scenes/enemy_barricader.tscn")
var _warrior_scene: PackedScene = preload("res://scenes/enemy.tscn")
var _barricade_scene: PackedScene = preload("res://scenes/barricade.tscn")
var _projectile_scene: PackedScene = preload("res://scenes/projectile.tscn")

func _check(cond: bool, name: String) -> void:
	if not cond:
		failures += 1
	print("[420] ", name, " -> ", "PASS" if cond else "FAIL")

func _initialize() -> void:
	Bestiary.save_path = "user://test420_bestiary.cfg"
	Bestiary.clear()
	_leg_a_variant()
	await _leg_b_c_barricade_basics()
	await _leg_d_to_j_spells()
	await _leg_k_deploys_in_open()
	await _leg_l_uses_existing_cover()
	await _leg_m_runs_to_open_space()
	await _leg_n_regular_never_deploys()
	Bestiary.clear()
	print("[420] failures: ", failures)
	print("RESULT: ", "ALL PASS" if failures == 0 else "FAILURES")
	quit(1 if failures > 0 else 0)

# --- helpers -----------------------------------------------------------------

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
	var p: Player = _player_scene.instantiate()
	p.name = "Player"
	p.collision_layer = 0
	p.collision_mask = 0
	p.set_process(false)
	stage.add_child(p)
	p.global_position = pos
	p.set_physics_process(false)
	return p

func _mk_enemy(scene: PackedScene, stage: Node2D, map: TerrainMap, pos: Vector2) -> Enemy:
	var e: Enemy = scene.instantiate()
	e.collision_layer = 0
	e.collision_mask = 0
	e.player_path = NodePath("../Player")
	e.terrain = map
	e.set_physics_process(false)
	stage.add_child(e)
	e.global_position = pos
	return e

func _barricade(stage: Node2D, pos: Vector2, decay: bool = false) -> Barricade:
	var b: Barricade = _barricade_scene.instantiate()
	b.position = pos
	stage.add_child(b)
	b.set_physics_process(decay)
	return b

func _spell(dmg: float, tags: Array[StringName] = []) -> Spell:
	var s := Spell.new()
	s.spell_name = "Fixture Bolt"
	s.damage = dmg
	s.radius = 4.0
	s.range = 400.0
	s.projectile_speed = 500.0
	s.tags = tags
	return s

## A real projectile flying DOWN through `target` from 100px above it.
func _fire(stage: Node2D, spell: Spell, target: Vector2, source: Node2D) -> Projectile:
	var pr: Projectile = _projectile_scene.instantiate()
	pr.setup(spell, Vector2.DOWN, source)
	stage.add_child(pr)
	pr.global_position = target + Vector2(0, -100)
	return pr

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _beh(e: Enemy) -> RefCounted:
	return e.get("_behavior") as RefCounted

func _cover_state(e: Enemy) -> int:
	return (_beh(e).get("_cover") as RefCounted).get("_state")

func _barricades() -> Array:
	var out: Array = []
	for b in get_nodes_in_group(&"barricades"):
		if is_instance_valid(b) and not b.is_queued_for_deletion():
			out.append(b)
	return out

func _drive_real(e: Enemy, frames: int, p: Player) -> void:
	e.set_physics_process(true)
	for i in frames:
		p.global_rotation = (e.global_position - p.global_position).angle() # aimed at
		await physics_frame
	e.set_physics_process(false)

func _teardown(stage: Node2D) -> void:
	stage.queue_free()
	await process_frame
	await process_frame

# --- legs --------------------------------------------------------------------

func _leg_a_variant() -> void:
	var e: Enemy = _barricader_scene.instantiate()
	_check(e.cover_seek, "A: barricader opts into the cover machine")
	_check(e.definition != null and e.definition.behavior == EnemyBehaviorBarricader, "A: barricader definition uses EnemyBehaviorBarricader")
	e.free()
	var w: Enemy = _warrior_scene.instantiate()
	_check(w.definition == null, "A: regular Mustache Warrior unchanged (no definition / default behavior)")
	w.free()
	var entry := Bestiary.catalog_entry(&"mustache_barricader")
	_check(not entry.is_empty() and entry["scene"] == "res://scenes/enemy_barricader.tscn" and not entry["boss"], "A: separate non-boss bestiary entry")
	_check(Bestiary.id_for_scene("res://scenes/enemy_barricader.tscn") == &"mustache_barricader"
		and Bestiary.id_for_scene("res://scenes/enemy.tscn") == &"mustache_warrior", "A: variant and warrior resolve to different bestiary ids")

func _leg_b_c_barricade_basics() -> void:
	var s := _mk_stage(false)
	var stage: Node2D = s[0]
	var b := _barricade(stage, Vector2(300, 300))
	await process_frame
	_check(b.is_in_group(&"cover") and b.is_in_group(&"barricades"), "B: joins the cover and barricades groups")
	_check(b.hp == b.max_hp and b.max_hp >= 100, "B: starts at its (high) max_hp")
	var died := [0]
	b.died.connect(func(): died[0] += 1)
	for i in 10:
		b._physics_process(1.0)
	_check(abs(b.hp - (b.max_hp - b.max_hp / 3)) <= 1, "C: 10s of decay drains a third of max_hp")
	for i in 19:
		b._physics_process(1.0)
	_check(b.hp > 0 and died[0] == 0, "C: still standing at 29s")
	b._physics_process(1.0)
	_check(died[0] == 1 and b.is_queued_for_deletion(), "C: gone at 30s (max lifetime), dies once")
	b._physics_process(1.0)
	_check(died[0] == 1, "C: post-death ticks are no-ops")
	await _teardown(stage)

func _leg_d_to_j_spells() -> void:
	var s := _mk_stage(false)
	var stage: Node2D = s[0]
	var player := _mk_player(stage, Vector2(3000, 3000))
	var foe: Enemy = _mk_enemy(_warrior_scene, stage, null, Vector2(-3000, 3000))
	await process_frame

	# D: player ordinary shot - damaged and blocked.
	var b1 := _barricade(stage, Vector2(300, 300))
	await _frames(2)
	var pr := _fire(stage, _spell(10.0), b1.global_position, player)
	await _frames(20)
	_check(b1.hp == b1.max_hp - 10, "D: player shot damages the barricade (exact)")
	_check(not is_instance_valid(pr), "D: player shot is blocked (despawned at the barricade)")

	# E: enemy ordinary shot - blocked, no damage.
	var b2 := _barricade(stage, Vector2(600, 300))
	await _frames(2)
	pr = _fire(stage, _spell(10.0), b2.global_position, foe)
	await _frames(20)
	_check(b2.hp == b2.max_hp, "E: enemy shot deals no damage")
	_check(not is_instance_valid(pr), "E: enemy shot is blocked")

	# F: player piercing shot passes through and damages once.
	var b3 := _barricade(stage, Vector2(900, 300))
	await _frames(2)
	pr = _fire(stage, _spell(10.0, [SpellTags.PIERCING]), b3.global_position, player)
	await _frames(20)
	_check(is_instance_valid(pr) and pr.global_position.y > b3.global_position.y + 40.0, "F: player piercing shot passes through")
	_check(b3.hp == b3.max_hp - 10, "F: piercing shot damages it once on the way")

	# G: enemy piercing shot passes through, no damage.
	var b4 := _barricade(stage, Vector2(1200, 300))
	await _frames(2)
	pr = _fire(stage, _spell(10.0, [SpellTags.PIERCING]), b4.global_position, foe)
	await _frames(20)
	_check(is_instance_valid(pr) and pr.global_position.y > b4.global_position.y + 40.0, "G: enemy piercing shot passes through")
	_check(b4.hp == b4.max_hp, "G: enemy piercing shot deals no damage")

	# H: lobbed rock passes over, no damage.
	var b5 := _barricade(stage, Vector2(1500, 300))
	await _frames(2)
	pr = _fire(stage, _spell(10.0, [SpellTags.LOBBED]), b5.global_position, foe)
	await _frames(20)
	_check(is_instance_valid(pr) and pr.global_position.y > b5.global_position.y + 40.0, "H: lobbed rock flies over")
	_check(b5.hp == b5.max_hp, "H: lobbed rock deals no damage")

	# I: summon-sourced shots.
	var owned := Summon.new()
	owned.player = player
	var stray := Summon.new()
	var b6 := _barricade(stage, Vector2(1800, 300))
	var b7 := _barricade(stage, Vector2(2100, 300))
	await _frames(2)
	_fire(stage, _spell(10.0), b6.global_position, owned)
	_fire(stage, _spell(10.0), b7.global_position, stray)
	await _frames(20)
	_check(b6.hp == b6.max_hp - 10, "I: player-owned summon's shot damages it")
	_check(b7.hp == b7.max_hp, "I: ownerless summon's shot does not")
	owned.free()
	stray.free()

	# J: non-projectile player damage (Water splash dispatch path).
	var b8 := _barricade(stage, Vector2(2400, 300))
	await _frames(1)
	WaterSplash.deal_damage(b8, _spell(12.0), player)
	_check(b8.hp == b8.max_hp - 12, "J: splash (non-projectile player damage) is accepted")
	_check(Barricade.is_player_side(player) and not Barricade.is_player_side(foe) and not Barricade.is_player_side(null), "J: player-side source rule")
	await _teardown(stage)

func _leg_k_deploys_in_open() -> void:
	var s := _mk_stage()
	var stage: Node2D = s[0]
	var map: TerrainMap = s[1]
	var p := _mk_player(stage, Vector2(1300, 1000))
	var e := _mk_enemy(_barricader_scene, stage, map, Vector2(1000, 1000))
	await process_frame
	e.global_position = Vector2(1000, 1000)
	p.global_position = Vector2(1300, 1000)
	await _drive_real(e, 120, p)
	var bs := _barricades()
	_check(bs.size() == 1, "K: no cover around -> deploys exactly one barricade")
	if bs.size() == 1:
		var b: Barricade = bs[0]
		_check(b.deployer == e, "K: barricade records its deployer")
		var t := Geometry2D.get_closest_point_to_segment(b.global_position, e.global_position, p.global_position)
		_check(t.distance_to(b.global_position) < 16.0 and b.global_position.x > e.global_position.x, "K: barricade sits between deployer and player")
		_check(_cover_state(e) == EnemyBehaviorCover.State.HOLD, "K: deployer HOLDs behind its barricade")
		# O: one live barricade per deployer.
		await _drive_real(e, 240, p)
		_check(_barricades().size() == 1 and int(_beh(e).get("deployed")) == 1, "O: no second barricade while the first stands")
	await _teardown(stage)

func _leg_l_uses_existing_cover() -> void:
	var s := _mk_stage()
	var stage: Node2D = s[0]
	var map: TerrainMap = s[1]
	var tree := Vector2i(36, 31)
	map.set_cell(tree, TerrainTypes.OBSTACLE)
	var tp := map.cell_to_world(tree)
	var p := _mk_player(stage, tp + Vector2(220, 0))
	var e := _mk_enemy(_barricader_scene, stage, map, tp + Vector2(-150, 0))
	await process_frame
	e.global_position = tp + Vector2(-150, 0)
	p.global_position = tp + Vector2(220, 0)
	await _drive_real(e, 180, p)
	_check(_barricades().is_empty(), "L: viable cover toward the player -> no barricade")
	_check(_cover_state(e) == EnemyBehaviorCover.State.HOLD, "L: holds the existing tree instead")
	await _teardown(stage)

func _leg_m_runs_to_open_space() -> void:
	var s := _mk_stage()
	var stage: Node2D = s[0]
	var map: TerrainMap = s[1]
	# A wall column right behind the start (away from the player): not cover
	# toward the player, but the start is not "open space".
	var start := map.cell_to_world(Vector2i(31, 31))
	for y in range(27, 36):
		map.set_cell(Vector2i(30, y), TerrainTypes.OBSTACLE)
	var p := _mk_player(stage, start + Vector2(330, 0))
	var e := _mk_enemy(_barricader_scene, stage, map, start)
	await process_frame
	e.global_position = start
	p.global_position = start + Vector2(330, 0)
	var spot: Variant = (_beh(e) as EnemyBehaviorBarricader).find_open_spot(e, p)
	_check(spot != null and (spot as Vector2) != start, "M: start is not open space -> an open spot elsewhere is chosen")
	await _drive_real(e, 150, p)
	var bs := _barricades()
	_check(bs.size() == 1, "M: deploys after running to open space")
	_check(e.global_position.distance_to(start) > 20.0, "M: moved away from the wall before deploying")
	if bs.size() == 1:
		var wall_x := map.cell_to_world(Vector2i(30, 31)).x + 16.0
		_check((bs[0] as Node2D).global_position.x - wall_x >= Barricade.WIDTH * 0.5, "M: barricade placed clear of the wall")
	await _teardown(stage)

func _leg_n_regular_never_deploys() -> void:
	var s := _mk_stage()
	var stage: Node2D = s[0]
	var map: TerrainMap = s[1]
	var p := _mk_player(stage, Vector2(1300, 1000))
	var e := _mk_enemy(_warrior_scene, stage, map, Vector2(1000, 1000))
	await process_frame
	e.global_position = Vector2(1000, 1000)
	p.global_position = Vector2(1300, 1000)
	await _drive_real(e, 120, p)
	_check(_barricades().is_empty(), "N: regular Mustache Warrior never deploys a barricade")
	await _teardown(stage)
