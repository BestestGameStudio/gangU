extends Node2D
## #146 (A5) EVIDENCE fixture - TEST-ONLY, harness-only. Full ELIMINATION
## flow in a test dungeon: 3 weaker mobs -> the boss spawns from the
## objective's exported boss_scene -> the boss kill completes the objective
## -> the locked ExitPortal opens. This fixture is NOT production: objective
## mounting in real dungeons belongs to main.gd's area mounts (A2+), and
## this scene is never reachable in the exported game.
## GANGU_AUTOTEST=1: auto-casts TEST projectiles (stand-in for #3/#4),
## asserts the phase ordering with [146] PASS/FAIL lines and quits with the
## failure count as the process exit code. Negative leg: on the pre-#146
## base the ELIMINATION type does not exist, so the boss never spawns and
## the boss-phase assertions FAIL.
## GANGU_CAPTURE_DIR set + real renderer: saves harness-only PNG captures
## (headless runs use the dummy renderer, so captures are skipped there).

const TestProjectileScene := preload("res://scenes/test_projectile.tscn")

@onready var debug: Label = $DebugLabel

var _objective: DungeonObjective
var _portal: ExitPortal
var _mobs: Array = []
var _autotest := false
var _cast_timer := 0.0
var _fails := 0
var _boss: Node = null
var _boss_ever_spawned := false
var _done := false
var _target_checked := false
var _want_boss_capture := false
var _status := ""
var _capture_dir := ""

func _check(label: String, ok: bool) -> void:
	if not ok:
		_fails += 1
	print("[146] ", label, " -> ", "PASS" if ok else "FAIL")

func _ready() -> void:
	_autotest = OS.get_environment("GANGU_AUTOTEST") == "1"
	_capture_dir = OS.get_environment("GANGU_CAPTURE_DIR")
	_objective = $DungeonObjective
	_portal = $ExitPortal
	_mobs = [$Mob1, $Mob2, $Mob3]
	_objective.objective_progress_changed.connect(_on_progress)
	_objective.objective_completed.connect(_on_completed)
	var has_boss_signal := _objective.has_signal("boss_spawned")
	_check("framework exposes the additive boss_spawned signal", has_boss_signal)
	if has_boss_signal:
		_objective.boss_spawned.connect(_on_boss_spawned)
	if _autotest:
		# Watchdog: the full flow must finish well inside this window.
		get_tree().create_timer(45.0).timeout.connect(_on_watchdog)

func _mobs_all_dead() -> bool:
	for m in _mobs:
		if is_instance_valid(m) and m.hp > 0:
			return false
	return true

func _on_progress(c: int, t: int) -> void:
	_status = "objective_progress_changed(" + str(c) + "/" + str(t) + ")"
	print("[146] progress ", c, "/", t, " id=", _objective.dungeon_id)
	if c < 3:
		_check("no boss before the mobs are cleared (progress " + str(c) + "/" + str(t) + ")", _boss == null)
	if c == 3:
		_check("all 3 mobs dead at mob phase end", _mobs_all_dead())
		_check("objective NOT completed by the mob kills alone", not _objective.is_cleared())

func _on_boss_spawned(b: Node) -> void:
	_boss = b
	_boss_ever_spawned = true
	_status = "boss_spawned"
	print("[146] boss spawned signal, node=", b.name)
	_check("boss spawns only after every mob is dead", _mobs_all_dead())
	_check("spawned boss joins the boss group (shipped convention)", b.is_in_group("boss"))
	# Fixture styling only (evidence readability): bigger, tougher, static.
	b.max_hp = 40
	b.speed = 0.0
	b.scale = Vector2(2, 2)
	# Capture a beat later so the boss is mid-fight and visibly on screen
	# (viewport readback can lag the spawn frame).
	get_tree().create_timer(0.6).timeout.connect(func(): _want_boss_capture = true)

func _on_completed(id: StringName) -> void:
	_status = "objective_completed(" + str(id) + ")"
	print("[146] COMPLETED id=", id, " is_cleared=", _objective.is_cleared())
	_check("completed dungeon id is elimination_dungeon", id == &"elimination_dungeon")
	_check("completion required the boss kill", _boss_ever_spawned and is_instance_valid(_boss) and _boss.hp <= 0)
	_check("is_cleared() true after completion", _objective.is_cleared())
	_check("locked exit portal opens on completion", not _portal.locked)
	# Let the portal label refresh, then close out.
	get_tree().create_timer(0.5).timeout.connect(_finish)

func _on_watchdog() -> void:
	if _done:
		return
	_check("watchdog: full flow completed within 45s", false)
	_finish()

func _finish() -> void:
	if _done:
		return
	_done = true
	_check("portal label shows EXIT after unlock", _portal.get_node("StateLabel").text == "EXIT")
	_capture("final_unlocked")
	print("[146] DONE fails=", _fails)
	if _autotest:
		get_tree().quit(_fails)

func _capture(shot_name: String) -> void:
	# Headless runs use the dummy renderer (no pixels); capture needs a real
	# renderer, e.g. xvfb-run. Labeled harness-only evidence.
	if _capture_dir == "" or DisplayServer.get_name() == "headless":
		return
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(_capture_dir + "/test146_" + shot_name + ".png")

func _cast() -> void:
	var p := Player.find(get_tree())
	if p == null or p.get("hp") <= 0:
		return
	var dir: Vector2
	if _autotest:
		var targets: Array = []
		for e in get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("boss"):
			if is_instance_valid(e) and e.hp > 0:
				targets.append(e)
		# Nearest first keeps the harness deterministic.
		targets.sort_custom(func(a, b): return p.global_position.distance_squared_to(a.global_position) < p.global_position.distance_squared_to(b.global_position))
		var tgt = targets[0] if targets.size() > 0 else null
		dir = p.global_position.direction_to(tgt.global_position) if tgt else Vector2.UP
	else:
		dir = p.global_position.direction_to(get_global_mouse_position())
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var proj := TestProjectileScene.instantiate()
	proj.direction = dir
	proj.global_position = p.global_position + dir * 28.0
	add_child(proj)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cast"):
		_cast()

func _process(delta: float) -> void:
	if not _target_checked:
		_target_checked = true
		_check("3 test mobs present at objective ready", get_tree().get_nodes_in_group("enemies").size() == 3)
		_check("target is mobs + 1 (0/4 at ready, monotonic for UI)", _objective.progress() == Vector2i(0, 4))
	if _want_boss_capture and _boss != null and _boss.is_inside_tree():
		_want_boss_capture = false
		print("[146] capture boss_phase: progress=", _objective.progress(), " boss_hp=", _boss.hp)
		_capture("boss_phase")
	var pr: Vector2i = _objective.progress()
	var boss_state := "none"
	if _boss_ever_spawned:
		# A freed (killed) boss compares == null in this engine build, so
		# track the spawn flag separately instead of testing _boss for null.
		boss_state = "alive" if is_instance_valid(_boss) and _boss.hp > 0 else "dead"
	debug.text = "objective " + str(_objective.dungeon_id) + " " + str(pr.x) + "/" + str(pr.y) + " | cleared=" + str(_objective.is_cleared()) + " | boss=" + boss_state + " | portal=" + ("LOCKED" if _portal.locked else "EXIT") + " | " + _status
	if _autotest and not _done:
		_cast_timer += delta
		if _cast_timer >= 1.2:
			_cast_timer = 0.0
			_cast()
