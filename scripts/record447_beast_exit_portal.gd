extends SceneTree
## #447 rendered fixture: the Beast den's exit portal, production flow.
## Locked gray portal while the Beast lives (the existing locked look);
## synthetic kill (label says so - not natural combat); the portal unlocks
## into the full purple portal look. Run under xvfb with --write-movie.

var _frame := 0
var _label: Label
var _scene: Node
const KILL_AT := 120 # 2s
const END := 360 # 6s

func _setup() -> void:
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)
	current_scene = _scene
	var hud := CanvasLayer.new()
	hud.layer = 10
	root.add_child(hud)
	_label = Label.new()
	_label.position = Vector2(24, 24)
	_label.add_theme_font_size_override("font_size", 30)
	hud.add_child(_label)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_setup()
	if _frame == 10:
		var p: Player = _scene.get_node("Player")
		_scene.enter_overworld()
		var gate := _scene.current_area.get_node_or_null("GateBeast") as Gate
		gate._on_body_entered(p)
	if _frame == 30:
		# Camera on the exit portal.
		var portal: Node2D = _scene.current_area.get_node_or_null("ExitPortal")
		if portal != null:
			var cam := Camera2D.new()
			_scene.current_area.add_child(cam)
			cam.position = portal.position + Vector2(0, 60)
			cam.make_current()
		_label.text = "#447 beast den exit portal - LOCKED (existing look)"
	if _frame == KILL_AT:
		for b in get_nodes_in_group("boss"):
			b.apply_damage(9999) # synthetic kill for the demo, not natural combat
		_label.text = "#447 beast dies (synthetic kill) - portal unlocks purple"
	if _frame >= END:
		quit(0)
	return false
