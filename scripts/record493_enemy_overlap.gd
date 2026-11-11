extends SceneTree
## #493 rendered fixture (real overworld scene, real physics - no layers
## zeroed). Six slimes chase a parked player. Phase 1 strips the enemy-enemy
## exceptions to show the OLD behavior (they jostle into a ring around the
## player); phase 2 restores them (the shipped #493 behavior) and the pack
## collapses into one overlapping stack. Run under xvfb with --write-movie;
## quits itself.

var _p: Player
var _enemies: Array[Enemy] = []
var _label: Label
var _phase := ""
const CENTER := Vector2(560, 600)

func _initialize() -> void:
	var area: Node2D = (load("res://scenes/overworld.tscn") as PackedScene).instantiate()
	root.add_child(area)
	current_scene = area
	_p = (load("res://scenes/player.tscn") as PackedScene).instantiate()
	_p.name = "Player"
	_p.add_to_group("player")
	area.add_child(_p)
	_p.global_position = CENTER
	_p.set_physics_process(false)
	for i in 6:
		var e: Enemy = (load("res://scenes/enemy.tscn") as PackedScene).instantiate()
		e.player_path = NodePath("../Player")
		e.contact_damage = 0
		area.add_child(e)
		e.global_position = CENTER + Vector2.RIGHT.rotated(TAU * i / 6.0) * 220.0
		_enemies.append(e)
	var cam := Camera2D.new()
	area.add_child(cam)
	cam.global_position = CENTER
	cam.zoom = Vector2(1.6, 1.6)
	cam.make_current()
	var hud := CanvasLayer.new()
	area.add_child(hud)
	_label = Label.new()
	_label.position = Vector2(24, 24)
	_label.add_theme_font_size_override("font_size", 30)
	hud.add_child(_label)
	await _run_frames(2)

	# Phase 1: old behavior (enemy-enemy exceptions removed).
	for a in _enemies:
		for b in _enemies:
			if a != b:
				a.remove_collision_exception_with(b)
	for e in _enemies:
		e.collision_mask |= PhysicsLayers.ENEMY # old behavior: enemies block each other
	_phase = "BEFORE (old): enemies block each other -> ring around the player"
	await _run_frames(120)

	# Phase 2: shipped #493 behavior.
	for e in _enemies:
		e.collision_mask &= ~PhysicsLayers.ENEMY
		e.global_position = CENTER + (e.global_position - CENTER).normalized() * 220.0
	_phase = "AFTER (#493): enemies pass through each other -> one stack"
	await _run_frames(120)
	quit(0)

func _run_frames(n: int) -> void:
	for i in n:
		await physics_frame
		_p.hp = _p.max_hp
		_label.text = "#493: enemies don't collide with each other\n%s" % _phase
		await process_frame
