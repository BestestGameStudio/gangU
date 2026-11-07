class_name DungeonObjective
extends Node
## #8: data-driven dungeon objective / clear condition.
## One objective node per dungeon; exported type + target configure it.
## Consumes Enemy.died (#5). Exposes progress + completion for UI (#11),
## run manager (#6) and gate/exit rules (#9).

signal objective_progress_changed(current: int, target: int)
signal objective_completed(dungeon_id: StringName)

enum ObjectiveType { CLEAR_ALL_ENEMIES, DEFEAT_BOSS }

@export var objective_type: ObjectiveType = ObjectiveType.CLEAR_ALL_ENEMIES
@export var dungeon_id: StringName = &"dungeon"
## CLEAR_ALL_ENEMIES: 0 means "every enemy present in the scene at ready".
## DEFEAT_BOSS: ignored, target is always 1 (the boss).
@export var target_count: int = 0

var _current: int = 0
var _target: int = 0
var _is_completed: bool = false

func is_cleared() -> bool:
	return _is_completed

func progress() -> Vector2i:
	return Vector2i(_current, _target)

func _ready() -> void:
	if objective_type == ObjectiveType.DEFEAT_BOSS:
		_target = 1
		for boss in get_tree().get_nodes_in_group("boss"):
			boss.died.connect(_on_target_died)
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
	if _current >= _target:
		_is_completed = true
		objective_completed.emit(dungeon_id)
