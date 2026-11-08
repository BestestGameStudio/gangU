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

enum ObjectiveType { CLEAR_ALL_ENEMIES, DEFEAT_BOSS, ELIMINATION }

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
	if objective_type == ObjectiveType.DEFEAT_BOSS:
		_target = 1
		for boss in get_tree().get_nodes_in_group("boss"):
			boss.died.connect(_on_target_died)
	elif objective_type == ObjectiveType.ELIMINATION:
		var mobs := get_tree().get_nodes_in_group("enemies")
		_mob_target = target_count if target_count > 0 else mobs.size()
		_target = _mob_target + 1
		for m in mobs:
			m.died.connect(_on_target_died)
		if boss_scene == null:
			push_error("DungeonObjective: ELIMINATION requires boss_scene; the objective can never complete.")
		elif _mob_target == 0:
			_spawn_boss()
	else:
		var enemies := get_tree().get_nodes_in_group("enemies")
		_target = target_count if target_count > 0 else enemies.size()
		for e in enemies:
			e.died.connect(_on_target_died)

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
