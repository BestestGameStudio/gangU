extends SceneTree
## #290 visual driver (render with --write-movie, not a pass/fail harness).
## Two side-by-side setups, three enemies chasing a stationary player:
## LEFT  = collision exceptions removed (pre-#290 behaviour: enemies stop
##         against the player's hull),
## RIGHT = current behaviour (enemies walk into / overlap the player).
## Contact damage is zeroed so nothing dies mid-clip.

func _pair(stage: Node2D, centre: Vector2, keep_exceptions: bool) -> void:
	var p: Player = preload("res://scenes/player.tscn").instantiate()
	p.position = centre
	stage.add_child(p)
	p.set_physics_process(false)
	var enemies: Array[Enemy] = []
	for off in [Vector2(-110, -50), Vector2(110, -30), Vector2(0, 120)]:
		var e: Enemy = preload("res://scenes/enemy.tscn").instantiate()
		e.player_path = NodePath(p.get_path())
		e.position = centre + off
		e.contact_damage = 0
		stage.add_child(e)
		enemies.append(e)
	await physics_frame
	await physics_frame
	if not keep_exceptions:
		for e in enemies:
			e.collision_mask |= PhysicsLayers.PLAYER # pre-#290: enemy hull blocks the player
			p.collision_mask |= PhysicsLayers.ENEMY

func _initialize() -> void:
	var stage := Node2D.new()
	root.add_child(stage)
	await process_frame ## node paths only resolve once root is live
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.13, 0.16)
	bg.position = Vector2(-1000, -1000)
	bg.size = Vector2(4000, 4000)
	stage.add_child(bg)
	var ui := CanvasLayer.new()
	stage.add_child(ui)
	for spec in [["BEFORE: enemies stop at the player hull", Vector2(20, 20)],
			["AFTER (#290): enemies overlap the player", Vector2(600, 20)]]:
		var l := Label.new()
		l.text = spec[0]
		l.position = spec[1]
		l.add_theme_font_size_override("font_size", 24)
		ui.add_child(l)
	_pair(stage, Vector2(760, 560), false)
	_pair(stage, Vector2(1160, 560), true)
	var cam := Camera2D.new()
	cam.position = Vector2(960, 560)
	cam.zoom = Vector2(1.4, 1.4)
	stage.add_child(cam)
	cam.make_current()
