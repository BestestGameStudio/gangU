class_name DefenseEncounter
extends Node
## Trigger-started, region-local defense. No objective UI or global enemy scans.
## The host owns run lifetime: destroying/rebuilding Main resets core and state.
signal encounter_started(encounter_id: StringName)
signal encounter_finished(encounter_id: StringName, cleared: bool)
signal boss_spawned(boss: Node)
signal wave_started(wave: int, total: int)
signal progress_changed(current: int, target: int)
@export var encounter_id: StringName = &"dungeon_e"
@export var trigger: LocationTrigger
@export var barriers: Array[NodePath] = []
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
## (#369) renders these with skull icons. #368: a boss wave spawns its usual
## wave_size(n) enemies PLUS wave_boss_count instances of wave_boss_scene;
## the wave only counts as cleared once its bosses are dead too. No
## wave_boss_scene = the wave is only marked (no boss spawns).
@export var boss_waves: Array[int] = []
## #368: boss enemy of a boss wave (an Enemy scene; joins the "boss" group
## and is announced through boss_spawned). Main sets the Siege Brute.
@export var wave_boss_scene: PackedScene
## #368: bosses per boss wave (implementer default, balance is open).
@export var wave_boss_count: int = 1
## #368: true = the boss marches on the core (turning on the player only when
## they come close, like core attackers); false = it hunts the player.
@export var wave_boss_targets_core: bool = true
## #368: seconds after its wave starts before the boss walks in. The wave's
## regulars have cleared the spawn point by then, so the boss never spawns
## inside one of them (a body spawned exactly on another is pushed out
## arbitrarily - in DungeonE that threw it out of the arena). The boss is
## reserved in the wave's alive count from the start, so the wave cannot
## read cleared before its boss arrives.
@export var wave_boss_delay: float = 1.5
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
var _failed: bool = false
var _active: bool = false
var _started: bool = false
var _waves_spawned: int = 0
var _next_wave_t: float = 0.0
var _wave_alive: Array[int] = []
var _spawner: EnemySpawner
var _pending_bosses: Array = []
var _owned_enemies: Array[Enemy] = []
var _player: Player

func _ready() -> void:
	_setup_defense()
	if trigger != null:
		trigger.triggered.connect(_on_triggered)
	set_physics_process(false)

func _on_triggered(_trigger: LocationTrigger, body: Node2D) -> void:
	start(body as Player)

func start(p_player: Player = null) -> bool:
	if _started or defense_core == null or defense_core.is_destroyed() or wave_enemy_scene == null:
		return false
	_started = true
	_active = true
	_player = p_player
	if is_instance_valid(_player) and not _player.died.is_connected(_on_player_died):
		_player.died.connect(_on_player_died)
	if trigger != null:
		trigger.disarm()
	_set_barriers(true)
	set_physics_process(true)
	encounter_started.emit(encounter_id)
	return true

func is_active() -> bool:
	return _active

func is_inert() -> bool:
	return _started or (defense_core != null and defense_core.is_destroyed())

func is_cleared() -> bool:
	return _is_completed

func progress() -> Vector2i:
	return Vector2i(_current, _target)

func _set_barriers(locked: bool) -> void:
	for path in barriers:
		var barrier := get_node_or_null(path)
		if barrier != null and barrier.has_method("set_locked"):
			barrier.set_locked(locked)

func _on_player_died() -> void:
	if _active:
		_finish(false)

func _finish(cleared: bool) -> void:
	if not _active:
		return
	_active = false
	_is_completed = cleared
	_pending_bosses.clear()
	set_physics_process(false)
	_set_barriers(false)
	encounter_finished.emit(encounter_id, cleared)

func _complete_empty_wave(_wave: int) -> void:
	# A refused/invalid spawn is not a victory. End unlocked, never clear.
	_failed = true
	_finish(false)

func is_failed() -> bool:
	return _failed

func waves_spawned() -> int:
	return _waves_spawned

## Total waves in this defense.
func total_waves() -> int:
	return _target

## #369: 1-based wave n is marked as a boss wave (skull on the HUD bar).
func is_boss_wave(n: int) -> bool:
	return n in boss_waves

## #369: seconds until the next wave spawns, or -1 when no wave is pending
## (all waves spawned, the objective completed or failed, or not DEFENSE).
func next_wave_remaining() -> float:
	if not _active:
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
		push_error("DefenseEncounter: DEFENSE needs a DefenseCore (export or sibling named DefenseCore); the objective can never complete.")
	else:
		defense_core.destroyed.connect(_on_core_destroyed)
	if wave_enemy_scene == null:
		push_error("DefenseEncounter: DEFENSE needs wave_enemy_scene; no waves will spawn.")
	if wave_spawn_points.is_empty():
		wave_spawn_points = [Vector2.ZERO]
	_spawner = EnemySpawner.new()
	_spawner.name = "WaveSpawner"
	add_child(_spawner)
	var area := get_parent()
	_spawner.setup([], wave_player_path, area.get_node_or_null("Terrain") as TerrainMap if area else null, area)

func _physics_process(delta: float) -> void:
	if not _active:
		return
	_tick_pending_bosses(delta)
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
	if not _active or _waves_spawned >= _target or wave_enemy_scene == null:
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
		var e := _spawner.request_spawn(SpawnEntry.new(at, wave_enemy_scene, wave_reward_table))
		if e == null:
			continue
		_owned_enemies.append(e)
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
		if e is EnemySlime:
			(e as EnemySlime).children_spawned.connect(_on_wave_children_spawned.bind(wave))
	if is_boss_wave(wave) and wave_boss_scene != null and wave_boss_count > 0:
		_wave_alive[wave - 1] += wave_boss_count
		_pending_bosses.append([wave_boss_delay, wave])
		if wave_boss_delay <= 0.0:
			_tick_pending_bosses(0.0)
	wave_started.emit(wave, _target)
	if _wave_alive[wave - 1] == 0:
		_complete_empty_wave(wave)
	progress_changed.emit(_current, _target)

## #368: the bosses of boss wave n. They come in at spawn points the regular
## enemies of the wave start from too (offset by the wave index, so a boss
## does not always use the same entrance), count toward that wave's alive
## total and drop from the definition's reward table (no direct table).
## Their wave_boss_count slots were reserved in _wave_alive at wave start; a
## boss the spawner refuses releases its slot like a death would.
func _spawn_wave_bosses(wave: int) -> void:
	var pts := wave_spawn_points.size()
	for b in wave_boss_count:
		var at: Vector2 = wave_spawn_points[(wave + b * 2 + 1) % pts]
		var boss := _spawner.request_spawn(SpawnEntry.new(at, wave_boss_scene))
		if boss == null:
			_on_wave_enemy_died(wave)
			continue
		_owned_enemies.append(boss)
		boss.nav = wave_nav
		if wave_boss_targets_core:
			boss.objective_target = defense_core
		boss.add_to_group("boss")
		boss.died.connect(_on_wave_enemy_died.bind(wave))
		if boss is EnemySlime:
			(boss as EnemySlime).children_spawned.connect(_on_wave_children_spawned.bind(wave))
		boss_spawned.emit(boss)

## #368: counts down pending boss arrivals and spawns the due ones. Runs from
## _physics_process (or spawn_next_wave), never from a physics callback (D14).
func _tick_pending_bosses(delta: float) -> void:
	if _pending_bosses.is_empty() or not _active:
		return
	var due: Array[int] = []
	for p: Array in _pending_bosses:
		p[0] -= delta
		if p[0] <= 0.0:
			due.append(p[1])
	_pending_bosses = _pending_bosses.filter(func(p: Array) -> bool: return p[0] > 0.0)
	for wave in due:
		_spawn_wave_bosses(wave)

## #368: boss arrivals still waiting out wave_boss_delay.
func pending_bosses() -> int:
	return _pending_bosses.size() * maxi(wave_boss_count, 0)

## #368: live bosses of the current defense (harness / HUD introspection).
func wave_bosses() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for n in _owned_enemies:
		if is_instance_valid(n) and n.hp > 0 and n.is_in_group("boss"):
			out.append(n)
	return out

func _alive_total() -> int:
	var t := 0
	for c in _wave_alive:
		t += c
	return t

func _on_wave_enemy_died(wave: int) -> void:
	if wave < 1 or wave > _wave_alive.size():
		return
	_wave_alive[wave - 1] -= 1
	if not _active or _wave_alive[wave - 1] > 0:
		return
	_current += 1
	progress_changed.emit(_current, _target)
	if _current >= _target:
		_is_completed = true
		_finish(true)

## #392: death-spawned descendants (EnemySlime) belong to the same wave; wire
## their deaths and any further splits into the wave's alive count.
func _on_wave_children_spawned(kids: Array, wave: int) -> void:
	if wave < 1 or wave > _wave_alive.size():
		return
	for k: Node in kids:
		var kid := k as Enemy
		if kid == null:
			continue
		_owned_enemies.append(kid)
		_wave_alive[wave - 1] += 1
		kid.died.connect(_on_wave_enemy_died.bind(wave))
		if kid is EnemySlime:
			(kid as EnemySlime).children_spawned.connect(_on_wave_children_spawned.bind(wave))

func _on_core_destroyed() -> void:
	if not _active:
		return
	_failed = true
	_finish(false)
