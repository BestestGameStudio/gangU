extends Node2D
## #8 EVIDENCE flow (test-only). Boots the clear-all-enemies test dungeon, then
## swaps to the defeat-boss test dungeon 2s after its completion - one run
## shows both objective types. Run the scene directly (headless autotest or a
## local evidence fixture); production main.gd/main.tscn stay untouched.

const CLEAR := preload("res://scenes/test_dungeon_clear.tscn")
const BOSS := preload("res://scenes/test_dungeon_boss.tscn")

var _current: Node

func _ready() -> void:
	_load(CLEAR)

func _load(ps: PackedScene) -> void:
	if _current and is_instance_valid(_current):
		_current.queue_free()
	_current = ps.instantiate()
	add_child(_current)
	var obj := _current.get_node_or_null("DungeonObjective")
	if obj and obj.dungeon_id == &"clear_dungeon":
		obj.objective_completed.connect(func(_id): get_tree().create_timer(2.0).timeout.connect(func(): _load(BOSS)))
