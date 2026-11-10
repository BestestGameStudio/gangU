extends SceneTree
## Recording only, no assertions or tests. The first beat is live walking
## and production spawning/AI. Clear beat uses explicitly disclosed damage.
var scene: Node
var p: Player
var caption: Label
var frame := 0
var target := Vector2.ZERO

func _initialize() -> void:
	call_deferred("_record")

func _record() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await _frames(4)
	scene.area_loader.enter_overworld()
	await _frames(4)
	p = scene.get_node("Player")
	p.max_hp = 10000
	p.hp = 10000
	var village: AbandonedVillage = scene.area_loader.current_area.get_node("AbandonedVillage")
	var focus := Node2D.new()
	scene.add_child(focus)
	focus.global_position = village.global_position
	var cam: Camera2D = scene.get_node("FollowCamera")
	cam.target = focus
	cam.zoom = Vector2(0.85, 0.85)
	# Arrive outside the west road. From here movement is production input.
	p.global_position = village.global_position + Vector2(-620, 0)
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
	caption.text = "#484 village demo | Staged arrival, 10,000 HP; production movement, event and AI\nWalk west road into the abandoned village: 30 mustache men surround it"
	await _frames(50)
	Input.action_press("move_right")
	await _frames(55)
	Input.action_release("move_right")
	await _frames(100)
	var mode := OS.get_cmdline_user_args()
	if mode.has("escape") or mode.has("west"):
		var direction := "move_left" if mode.has("west") else "move_right"
		caption.text = "ESCAPE | Production walking through the %s road\nAmbushers despawn; no 100c clear reward" % ("west" if mode.has("west") else "east")
		Input.action_press(direction)
		await _frames(65)
		Input.action_release(direction)
	else:
		caption.text = "CLEAR | Disclosed synthetic damage kills the 30 ambushers to show reward flow\nNot a combat demonstration. Village clear/reward code is unchanged."
		for enemy in village.ambushers:
			if is_instance_valid(enemy):
				enemy.apply_damage(9999)
				await _frames(2)
		await _frames(30)
		Input.action_press("move_right")
		await _frames(16)
		Input.action_release("move_right")
	await _frames(80)
	print("[recording] village status: ", village.status, "; wallet: ", scene.get_node("CurrencyWallet").balance())
	scene.queue_free()
	await _frames(4)
	quit()

func _frames(n: int) -> void:
	for i in n:
		await process_frame
