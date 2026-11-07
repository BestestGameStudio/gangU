extends Node2D
## #8 EVIDENCE driver (test-only). Casts TEST projectiles (stand-in for #3/#4)
## and shows objective state on a debug label (stand-in for #11 HUD).
## GANGU_AUTOTEST=1: auto-casts and prints diagnostics for headless evidence.

const TestProjectileScene := preload("res://scenes/test_projectile.tscn")

@onready var debug: Label = $DebugLabel
var _status := ""
var _objective: DungeonObjective
var _autotest := false
var _cast_timer := 0.0

func _ready() -> void:
	_autotest = OS.get_environment("GANGU_AUTOTEST") == "1"
	_objective = $DungeonObjective
	_objective.objective_progress_changed.connect(func(c, t): _status = "objective_progress_changed(" + str(c) + "/" + str(t) + ")"; print("[obj] progress ", c, "/", t, " id=", _objective.dungeon_id))
	_objective.objective_completed.connect(func(id): _status = "objective_completed(" + str(id) + ") is_cleared=" + str(_objective.is_cleared()); print("[obj] COMPLETED id=", id, " is_cleared=", _objective.is_cleared()))
	if _autotest:
		get_tree().create_timer(30.0).timeout.connect(func(): get_tree().quit())

func _cast() -> void:
	var p = get_tree().get_first_node_in_group("player")
	if p == null or p.get("hp") <= 0:
		return
	var proj := TestProjectileScene.instantiate()
	var dir: Vector2
	if _autotest:
		var targets := get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("boss")
		var tgt = targets[0] if targets.size() > 0 else null
		dir = p.global_position.direction_to(tgt.global_position) if tgt else Vector2.UP
	else:
		dir = p.global_position.direction_to(get_global_mouse_position())
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	proj.direction = dir
	proj.global_position = p.global_position + dir * 28.0
	add_child(proj)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cast"):
		_cast()

func _process(delta: float) -> void:
	var pr: Vector2i = _objective.progress()
	debug.text = "objective " + str(_objective.dungeon_id) + " " + str(pr.x) + "/" + str(pr.y) + " | cleared=" + str(_objective.is_cleared()) + " | " + _status
	if _autotest:
		_cast_timer += delta
		if _cast_timer >= 1.2:
			_cast_timer = 0.0
			_cast()
