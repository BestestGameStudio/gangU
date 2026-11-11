class_name BossLair
extends Node2D
## #550: boss lair encounter wiring - locks its EncounterBarrier doors while a
## live boss is inside, unlocks when every registered boss is dead (#182 D12
## lock-in as physical overworld doors, now on the shared #605 barrier).
##
## Contract (origin lead, 2026-11-10):
## - Component only. The 548 host owns placement, trigger/barrier/boss scene
##   wiring and registration timing (including a delayed DungeonB Warlord);
##   this node only resolves the exported NodePaths and runs the lifecycle.
## - ENTRY starts the encounter ONLY when at least one registered boss is
##   alive and clearable: barriers lock on start. Zero alive on entry means
##   the lair stays OPEN - a cleared lair never retraps and no clear is
##   manufactured for an empty one.
## - Success: unlock ONCE, when ALL registered bosses are dead. Accounting is
##   local (Enemy.died connections made in register_boss); no global scans.
## - Player death: unlock WITHOUT clear (the run restarts via RunManager).
## - A boss registered after entry never retro-locks an open lair; the host
##   owns late-registration policy (e.g. re-fire the trigger or lock itself).
## - Encounter-agnostic state only: no art, AI, music, spawn or balance
##   decisions here; boss scenes/behavior/music are unchanged.

## Stable id for this lair, used in encounter_finished; empty falls back to
## the node name (same convention as LocationTrigger.id()).
@export var encounter_id: StringName = &""
## LocationTrigger the player walks into to start the encounter. Its event
## stays null: AreaLoader's null-event guard lets it emit `triggered` only.
@export var trigger: NodePath
## EncounterBarrier doors (or anything with set_locked / lock / unlock).
@export var barriers: Array[NodePath] = []
## Bosses registered from the start; the host can register more later
## (delayed DungeonB Warlord) via register_boss().
@export var bosses: Array[NodePath] = []

## Emitted exactly once per activation: cleared=true on all bosses dead,
## cleared=false on player death. Consumers (549 cleared flag, map marks)
## are host-side; nothing here persists run state.
signal encounter_finished(id: StringName, cleared: bool)
## Forwarded when a live boss is registered, for hosts that route it to the
## existing boss_spawned consumers (player_path assignment, boss theme).
signal boss_spawned(boss: Node)

var _registered: Array[Enemy] = []
var _active := false
var _player: Player = null


func _ready() -> void:
	var t := get_node_or_null(trigger) as LocationTrigger
	if t != null:
		t.triggered.connect(_on_triggered)
	else:
		push_warning("BossLair: trigger path did not resolve to a LocationTrigger.")
	for path in bosses:
		register_boss(get_node_or_null(path) as Enemy)


func id() -> StringName:
	return encounter_id if encounter_id != &"" else StringName(name)


## Register a boss for this lair. Already-dead or freed bosses are recorded
## as dead so they can never cause a lock. Live registration while the
## encounter is active simply extends the clear requirement.
func register_boss(boss: Enemy) -> void:
	if boss == null or _registered.has(boss):
		return
	_registered.append(boss)
	if boss.hp > 0:
		boss.died.connect(_on_boss_died.bind(boss), CONNECT_ONE_SHOT)
		boss_spawned.emit(boss)


## Called by the entry trigger. Starts the encounter only with a live,
## clearable registered boss; otherwise the lair stays open.
func start(player: Node2D) -> void:
	if _active or _alive_bosses().is_empty():
		return
	_active = true
	_player = player as Player
	if _player != null and not _player.died.is_connected(_on_player_died):
		_player.died.connect(_on_player_died, CONNECT_ONE_SHOT)
	_set_barriers_locked(true)


func is_active() -> bool:
	return _active


func _on_triggered(_t: LocationTrigger, body: Node2D) -> void:
	start(body)


func _on_boss_died(boss: Enemy) -> void:
	_registered.erase(boss)
	if _active and _alive_bosses().is_empty():
		_finish(true)


func _on_player_died() -> void:
	if _active:
		_finish(false)


func _finish(cleared: bool) -> void:
	_active = false
	_player = null
	_set_barriers_locked(false)
	encounter_finished.emit(id(), cleared)


func _alive_bosses() -> Array[Enemy]:
	var alive: Array[Enemy] = []
	for boss in _registered:
		if is_instance_valid(boss) and boss.hp > 0:
			alive.append(boss)
	return alive


func _set_barriers_locked(locked_state: bool) -> void:
	for path in barriers:
		var b := get_node_or_null(path)
		if b != null and b.has_method("set_locked"):
			b.set_locked(locked_state)
