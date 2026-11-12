extends SceneTree
## LOCAL DEMO DRIVER - not committed.
var _frame := 0
var _p: Player
var _red: Enemy
var _main: Node
var _cam: Camera2D
func _initialize() -> void:
	_main = load('res://game/core/main.tscn').instantiate()
	root.add_child(_main)
	current_scene = _main
func _process(_delta: float) -> bool:
	return false
func _physics_process(_delta: float) -> bool:
	_frame += 1
	if _frame == 10:
		_p = _main.get_node('Player')
		_p.max_hp = 99999
		_p.hp = 99999
		var hub: Node = _main.get('area_loader').current_area
		var gate := hub.get_node('GateOverworld') as Gate
		gate._on_body_entered(_p)
	if _frame == 40:
		for e in root.get_tree().get_nodes_in_group('enemies'):
			if e is Enemy and e._behavior is EnemyBehaviorIdleChase:
				_red = e
				break
		if _red != null:
			_cam = Camera2D.new()
			_cam.zoom = Vector2(1.5, 1.5)
			_red.get_parent().add_child(_cam)
			_cam.global_position = _red.global_position
			_cam.make_current()
			_p.global_position = _red.global_position + Vector2(0, -1500)
	if _red != null and _cam != null and _frame == 300:
		# step into chase range, in view
		_p.global_position = _red.global_position + Vector2(0, -450)
	if _red != null and _cam != null and _frame == 650:
		# leave chase range -> back to IDLE
		_p.global_position = _red.global_position + Vector2(0, -2000)
	return _frame > 950
