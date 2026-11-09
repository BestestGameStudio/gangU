extends SceneTree
## Isolated #402 card-component checks. No shared equip_panel wiring yet.
var failures := 0
func ck(ok: bool, label: String) -> void:
	print("[402] ", label, " -> ", "PASS" if ok else "FAIL")
	if not ok: failures += 1
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var row := HBoxContainer.new()
	row.position = Vector2(80, 80)
	row.add_theme_constant_override("separation", 12)
	root.add_child(row)
	var a := UpgradeCard.new()
	var b := UpgradeCard.new()
	row.add_child(a)
	row.add_child(b)
	a.setup("Split shot [S]", "Fires three projectiles in a spread.\nEach projectile: 8 damage.", false)
	b.setup("Beam [S]", "Pierces enemies along its path.\nRange: 600 px.", true, Color(0.45, 0.7, 1.0))
	for i in 8: await process_frame
	ck(a.name_label.text == "Split shot [S]", "exact supplied upgrade name")
	ck(a.description_label.text.begins_with("Fires three"), "supplied description displayed")
	ck(a.action_label.text == "Choose upgrade", "cast route label")
	ck(b.action_label.text.contains("token"), "token route label")
	ck(b.global_position.x >= a.global_position.x + a.size.x, "side-by-side nonoverlapping cards")
	ck(a.splash.size.y >= 86, "visible splash placeholder")
	ck(a.splash.get_child(0).text == "PLACEHOLDER ART", "placeholder honestly labelled")
	var children_ignore := true
	for child in a.find_children("*", "Control", true, false):
		children_ignore = children_ignore and child.mouse_filter == Control.MOUSE_FILTER_IGNORE
	ck(children_ignore, "decorative children do not intercept click")
	var clicked := [false]
	a.pressed.connect(func(): clicked[0] = true)
	var at := a.get_global_rect().get_center()
	for press in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = press
		root.push_input(event)
		await process_frame
	ck(clicked[0], "viewport mouse click reaches card action")
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png("/downloads/402_isolated_cards.png")
	print("[402] DONE failures=", failures)
	quit(failures)
