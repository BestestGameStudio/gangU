extends SceneTree
## Recording only, no assertions or tests (#546). Staged arrival at the
## village, 10,000 HP; production movement, spawn, AI and collision.
## Beat 1: the hero walks into a house and the well and is stopped.
## Beat 2: the ambushers appear outside the tree ring and run in.
var scene: Node
var p: Player
var caption: Label

func _initialize() -> void:
	call_deferred("_record")

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _hold(action: String, until: Callable, max_frames: int) -> void:
	Input.action_press(action)
	for i in max_frames:
		await process_frame
		if until.call():
			break
	Input.action_release(action)

func _record() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await _frames(4)
	scene.enter_overworld()
	await _frames(4)
	p = scene.get_node("Player")
	p.max_hp = 10000
	p.hp = 10000
	var village: AbandonedVillage = scene.current_area.get_node("AbandonedVillage")
	var c := village.global_position
	var focus := Node2D.new()
	scene.add_child(focus)
	focus.global_position = c
	var cam: Camera2D = scene.get_node("FollowCamera")
	cam.target = focus
	cam.zoom = Vector2(0.5, 0.5)
	p.global_position = c + Vector2(-700, 0)
	var layer := CanvasLayer.new()
	layer.layer = 30
	scene.add_child(layer)
	var back := ColorRect.new()
	back.position = Vector2(10, 85)
	back.size = Vector2(1260, 75)
	back.color = Color(0.04, 0.05, 0.04, 0.94)
	layer.add_child(back)
	caption = Label.new()
	caption.position = Vector2(24, 91)
	caption.add_theme_font_size_override("font_size", 21)
	layer.add_child(caption)
	caption.text = "#546 village demo | Staged start at the clearing, 10,000 HP; production movement and collision\nWalk in along the west road: the centre trigger starts the ambush"
	await _frames(40)
	await _hold("move_right", func(): return p.global_position.x > c.x - 270, 200)
	caption.text = "Ambush started: the mustache men spawn OUTSIDE the tree ring (radius 540) and run in"
	await _frames(100)
	caption.text = "Houses block the hero: walk up, then right into the first house"
	await _hold("move_up", func(): return p.global_position.y < c.y - 140, 120)
	await _hold("move_right", func(): return false, 45)
	print("[recording] into house: ", p.global_position - c)
	await _frames(20)
	caption.text = "The well is solid too: walk back down and right into it"
	await _hold("move_down", func(): return p.global_position.y > c.y - 2, 150)
	await _hold("move_right", func(): return false, 45)
	print("[recording] into well: ", p.global_position - c, " status: ", village.status)
	await _frames(20)
	await _frames(60)
	var near := 0
	for e in village.ambushers:
		if is_instance_valid(e) and e.global_position.distance_to(c) < 500:
			near += 1
	print("[recording] ambushers inside ring now: ", near, "/", village.ambushers.size(), " status: ", village.status)
	await _frames(100)
	scene.queue_free()
	await _frames(4)
	quit()
