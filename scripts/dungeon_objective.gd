class_name DungeonObjective
extends Node
## #8: data-driven dungeon objective / clear condition.
## One objective node per dungeon; exported type + target configure it.
## Consumes Enemy.died (#5). Exposes progress + completion for UI (#11),
## run manager (#6) and gate/exit rules (#9).
## #146 (A5): additive ELIMINATION type - clear the weaker mobs, then a boss
## spawns from the exported boss_scene; the boss kill completes the dungeon.
## Existing types are untouched: same signals, same counting, same defaults.

signal objective_progress_changed(current: int, target: int)
signal objective_completed(dungeon_id: StringName)
## #146: emitted when the ELIMINATION boss phase starts. The boss enters the
## tree deferred (D14); the emitted node may not be inside the tree yet.
signal boss_spawned(boss: Node)
## #337 DEFENSE: a wave started (1-based index).
signal wave_started(wave: int, total: int)
## #337 DEFENSE: the defended core was destroyed. Waves stop; the objective can
## no longer complete. Main unlocks the exit portal so the run never soft-locks.
signal objective_failed(dungeon_id: StringName)

## #337: DEFENSE is additive like ELIMINATION (#146): defend the area's
## DefenseCore through a fixed number of periodic waves.
enum ObjectiveType { CLEAR_ALL_ENEMIES, DEFEAT_BOSS, ELIMINATION, DEFENSE }

@export var objective_type: ObjectiveType = ObjectiveType.CLEAR_ALL_ENEMIES
@export var dungeon_id: StringName = &"dungeon"
## CLEAR_ALL_ENEMIES: 0 means "every enemy present in the scene at ready".
## DEFEAT_BOSS: ignored, target is always 1 (the boss).
## ELIMINATION: weaker mobs to clear before the boss spawns; 0 means "every
## enemy present in the scene at ready". Total progress target is mobs + 1,
## so UI progress stays monotonic across the two phases.
@export var target_count: int = 0
## ELIMINATION only: instantiated once the mobs are cleared. The spawned
## boss must carry a `died` signal (e.g. scenes/enemy.tscn); that death
## completes the objective.
@export var boss_scene: PackedScene
## ELIMINATION only: global position for the boss spawn.
@export var boss_spawn_position: Vector2 = Vector2.ZERO

@export_group("Defense (#337)")
## The defended object; unset = the sibling node named "DefenseCore".
## All numbers below are tunable implementer defaults, not approved balance.
@export var defense_core: DefenseCore
## Fixed wave count (Daniel: waves, not a survival timer). Progress target.
@export var wave_count: int = 5
## Wave n (1-based) spawns wave_base_size + (n - 1) * wave_size_growth enemies.
@export var wave_base_size: int = 3
@export var wave_size_growth: int = 1
## Seconds before wave 1 spawns.
@export var first_wave_delay: float = 3.0
## Seconds between wave spawns (periodic). If the field is cleared earlier the
## next wave comes after clear_break instead, so nobody waits around.
@export var wave_interval: float = 15.0
@export var clear_break: float = 3.0
## Mixed behaviour (Daniel): this share of every wave goes for the core (and
## turns on the player only when they come close); the rest hunt the player.
@export_range(0.0, 1.0) var core_attacker_share: float = 0.5
## #369/#368: 1-based wave indexes that are boss waves. The HUD wave bar
## (#369) renders these with skull icons. Empty until boss waves (#368)
## land; marking a wave here has no effect on composition or spawning.
@export var boss_waves: Array[int] = []
@export var wave_enemy_scene: PackedScene
@export var wave_reward_table: RewardTable
## Area-local spawn positions; enemies of a wave are spread over them.
@export var wave_spawn_points: Array[Vector2] = []
## Relative to a spawned enemy (child of the area): "../../Player" in Main.
@export var wave_player_path: NodePath = NodePath("../../Player")
## #367: grid pathfinding handed to every wave enemy (maze defense). Null -
## DungeonE - keeps the straight-line chase.
@export var wave_nav: FlowNav

var _current: int = 0
var _target: int = 0
var _is_completed: bool = false
var _mob_target: int = 0
var _boss_spawned: bool = false

func is_cleared() -> bool:
	return _is_completed

func progress() -> Vector2i:
	return Vector2i(_current, _target)

func _ready() -> void:
	if objective_type == ObjectiveType.DEFENSE:
		_setup_defense()
		return
	if objective_type == ObjectiveType.DEFEAT_BOSS:
		_target = 1
		for boss in get_tree().get_nodes_in_group("boss"):
			boss.died.connect(_on_target_died)
	elif objective_type == ObjectiveType.ELIMINATION:
		var mobs := get_tree().get_nodes_in_group("enemies")
		_mob_target = target_count if target_count > 0 else mobs.size()
		_target = _mob_target + 1
		for m in mobs:
			_watch(m)
		if boss_scene == null:
			push_error("DungeonObjective: ELIMINATION requires boss_scene; the objective can never complete.")
		elif _mob_target == 0:
			_spawn_boss()
	else:
		var enemies := get_tree().get_nodes_in_group("enemies")
		_target = target_count if target_count > 0 else enemies.size()
		for e in enemies:
			_watch(e)

## #392: count a mob's death and, for enemies that spawn children on death
## (EnemySlime.children_spawned, emitted before this objective sees the death),
## also count each child. Scoped to enemies this objective already watches.
func _watch(e: Node) -> void:
	e.died.connect(_on_target_died)
	if e.has_signal("children_spawned"):
		e.children_spawned.connect(_on_children_spawned)

func _on_children_spawned(kids: Array) -> void:
	if _is_completed:
		return
	for k in kids:
		_target += 1
		if objective_type == ObjectiveType.ELIMINATION:
			_mob_target += 1
		_watch(k)
	objective_progress_changed.emit(_current, _target)

func _on_target_died() -> void:
	if _is_completed:
		return
	_current += 1
	objective_progress_changed.emit(_current, _target)
	if objective_type == ObjectiveType.ELIMINATION and _current == _mob_target and not _boss_spawned:
		_spawn_boss()
	if _current >= _target:
		_is_completed = true
		objective_completed.emit(dungeon_id)

## #146: boss phase. Deferred add (D14): died() can fire inside a physics
## callback, so the boss never enters the tree synchronously.
func _spawn_boss() -> void:
	if _boss_spawned:
		return
	_boss_spawned = true
	if boss_scene == null:
		push_error("DungeonObjective: ELIMINATION boss_scene is not set; the objective can never complete.")
		return
	var boss := boss_scene.instantiate()
	if boss is Node2D:
		boss.global_position = boss_spawn_position
	# #396: a boss moves on its area's terrain like the mobs do (spawned
	# mobs get it from EnemySpawner); no Terrain node = flat, as before.
	if boss is Enemy and get_parent() != null:
		boss.terrain = get_parent().get_node_or_null("Terrain") as TerrainMap
	# Group consistency with the shipped convention (test_dungeon_boss.tscn,
	# DEFEAT_BOSS ready-scan): the boss joins the "boss" group. Its own
	# script may also add "enemies" on ready; mob connections were already
	# made at objective ready, so no double-count is possible here.
	boss.add_to_group("boss")
	if boss.has_signal("died"):
		boss.died.connect(_on_target_died)
	else:
		push_error("DungeonObjective: ELIMINATION boss_scene root lacks a `died` signal; the objective can never complete.")
	get_parent().call_deferred("add_child", boss)
	boss_spawned.emit(boss)

# --- #337 DEFENSE ----------------------------------------------------------
# Progress is (waves cleared, wave_count). A wave counts as cleared once it has
# spawned and every enemy in it is dead, so overlapping waves stay monotonic.
# Completion: every wave cleared while the core still stands. Core destroyed:
# objective_failed, no more waves, never completes.

var _failed: bool = false
var _waves_spawned: int = 0
var _next_wave_t: float = 0.0
## alive count per wave (index = wave - 1)
var _wave_alive: Array[int] = []
var _spawner: EnemySpawner = null

func is_failed() -> bool:
	return _failed

func waves_spawned() -> int:
	return _waves_spawned

## #369: total waves in this defense (the progress target).
func total_waves() -> int:
	return _target

## #369: 1-based wave n is marked as a boss wave (skull on the HUD bar).
func is_boss_wave(n: int) -> bool:
	return n in boss_waves

## #369: seconds until the next wave spawns, or -1 when no wave is pending
## (all waves spawned, the objective completed or failed, or not DEFENSE).
func next_wave_remaining() -> float:
	if objective_type != ObjectiveType.DEFENSE or _is_completed or _failed:
		return -1.0
	if _waves_spawned >= _target:
		return -1.0
	return maxf(_next_wave_t, 0.0)

func core() -> DefenseCore:
	return defense_core

## Enemies in wave n (1-based).
func wave_size(n: int) -> int:
	return maxi(1, wave_base_size + (n - 1) * wave_size_growth)

func _setup_defense() -> void:
	_target = maxi(wave_count, 1)
	_next_wave_t = first_wave_delay
	if defense_core == null and get_parent() != null:
		defense_core = get_parent().get_node_or_null("DefenseCore") as DefenseCore
	if defense_core == null:
		push_error("DungeonObjective: DEFENSE needs a DefenseCore (export or sibling named DefenseCore); the objective can never complete.")
	else:
		defense_core.destroyed.connect(_on_core_destroyed)
	if wave_enemy_scene == null:
		push_error("DungeonObjective: DEFENSE needs wave_enemy_scene; no waves will spawn.")
	if wave_spawn_points.is_empty():
		wave_spawn_points = [Vector2.ZERO]
	_spawner = EnemySpawner.new()
	_spawner.name = "WaveSpawner"
	add_child(_spawner)
	var area := get_parent()
	_spawner.setup([], wave_player_path, area.get_node_or_null("Terrain") as TerrainMap if area else null, area)

func _physics_process(delta: float) -> void:
	if objective_type != ObjectiveType.DEFENSE or _is_completed or _failed:
		return
	if defense_core == null or wave_enemy_scene == null or _waves_spawned >= _target:
		return
	if _waves_spawned > 0 and _alive_total() == 0:
		_next_wave_t = minf(_next_wave_t, clear_break)
	_next_wave_t -= delta
	if _next_wave_t <= 0.0:
		spawn_next_wave()

## Spawns the next wave now (public so harnesses can skip the timer).
## Called from _physics_process, never from a physics callback (D14).
func spawn_next_wave() -> void:
	if _failed or _is_completed or _waves_spawned >= _target or wave_enemy_scene == null:
		return
	_waves_spawned += 1
	_next_wave_t = wave_interval
	var wave := _waves_spawned
	var n := wave_size(wave)
	_wave_alive.append(0)
	var pts := wave_spawn_points.size()
	for i in n:
		@warning_ignore("integer_division")
		var ring := i / pts
		var at: Vector2 = wave_spawn_points[(i + wave) % pts] + Vector2.from_angle(float(i) * 2.4) * (18.0 * ring)
		var e := _spawner.request_spawn({"position": at, "enemy": wave_enemy_scene, "reward_table": wave_reward_table})
		if e == null:
			continue
		e.nav = wave_nav
		# Spread core attackers evenly through the wave: i is one when the
		# running share crosses an integer.
		if floori((i + 1) * core_attacker_share) > floori(i * core_attacker_share):
			e.objective_target = defense_core
		_wave_alive[wave - 1] += 1
		e.died.connect(_on_wave_enemy_died.bind(wave))
		# #392: a splitting wave enemy's descendants stay in its wave.
		# children_spawned fires before the parent's died, so the wave count
		# rises before it falls and a wave never reads cleared early.
		if e.has_signal("children_spawned"):
			e.children_spawned.connect(_on_wave_children_spawned.bind(wave))
	wave_started.emit(wave, _target)
	objective_progress_changed.emit(_current, _target)

func _alive_total() -> int:
	var t := 0
	for c in _wave_alive:
		t += c
	return t

func _on_wave_enemy_died(wave: int) -> void:
	_wave_alive[wave - 1] -= 1
	if _is_completed or _failed or _wave_alive[wave - 1] > 0:
		return
	_current += 1
	objective_progress_changed.emit(_current, _target)
	if _current >= _target:
		_is_completed = true
		objective_completed.emit(dungeon_id)

## #392: death-spawned descendants (EnemySlime) belong to the same wave; wire
## their deaths and any further splits into the wave's alive count.
func _on_wave_children_spawned(kids: Array, wave: int) -> void:
	if wave < 1 or wave > _wave_alive.size():
		return
	for k in kids:
		if not (k is Enemy):
			continue
		_wave_alive[wave - 1] += 1
		k.died.connect(_on_wave_enemy_died.bind(wave))
		if k.has_signal("children_spawned"):
			k.children_spawned.connect(_on_wave_children_spawned.bind(wave))

func _on_core_destroyed() -> void:
	if _is_completed or _failed:
		return
	_failed = true
	objective_failed.emit(dungeon_id)
