extends SceneTree
## Scratch demo driver for #622 (not committed to main): boots the game,
## shows whether the corner Settings button exists, clicks it if present,
## then shows Esc opening/closing the Settings panel.
var pl: Node

func _initialize() -> void:
	_run.call_deferred()

func _wait(sec: float) -> void:
	var n := int(sec / 0.1)
	for i in n:
		if pl != null and is_instance_valid(pl):
			pl.set("hp", pl.get("max_hp"))
		await create_timer(0.1).timeout

func _press_esc() -> void:
	var down := InputEventKey.new()
	down.keycode = KEY_ESCAPE
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.keycode = KEY_ESCAPE
	up.pressed = false
	Input.parse_input_event(up)

func _run() -> void:
	var main: Node = load("res://game/core/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	for i in 3:
		await physics_frame
	pl = main.get_node("Player")
	var panel: Node = main.get_node("SettingsPanel")
	await _wait(2.0)
	var btn: Node = panel.find_child("OpenSettings", true, false)
	print("DEMO corner Settings button present = ", btn != null)
	if btn != null:
		print("DEMO corner button visible = ", btn.visible)
		await _wait(1.5)
		(btn as Button).pressed.emit()
		await _wait(1.5)
		print("DEMO after corner-button click: settings open = ", panel.is_open())
		await _wait(2.0)
		panel.close()
		await _wait(1.0)
		print("DEMO after close: settings open = ", panel.is_open())
	else:
		await _wait(2.0)
	_press_esc()
	await _wait(1.5)
	print("DEMO after Esc: settings open = ", panel.is_open())
	await _wait(2.5)
	_press_esc()
	await _wait(1.0)
	print("DEMO after second Esc: settings open = ", panel.is_open())
	await _wait(1.0)
	quit(0)
