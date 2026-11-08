extends SceneTree
## TerrainFog harness: three-state reveal logic over a bounded rect, the
## world-position API, target following, the debug scene's end state, and
## the unchanged-centre no-op.

const BOUNDS := Rect2i(0, 0, 20, 20)

var failures := 0
var phase := 0
var t := 0.0
var map: TerrainMap
var fog: TerrainFog
var follower: Node2D
var scene: Node2D

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[168] ", name, " -> PASS")
	else:
		failures += 1
		print("[168] ", name, " -> FAIL")

func _count(f: TerrainFog, rect: Rect2i, state: TerrainFog.State) -> int:
	var n := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if f.state_at_cell(Vector2i(x, y)) == state:
				n += 1
	return n

func _initialize() -> void:
	map = TerrainMap.new()
	root.add_child(map)
	fog = TerrainFog.new()
	fog.map = map
	fog.bounds = BOUNDS
	fog.vision_radius = 2
	root.add_child(fog)
	scene = load("res://scenes/test168_fog_debug.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene

func _process(delta: float) -> bool:
	t += delta
	match phase:
		0:
			if not map.is_node_ready() or not fog.is_node_ready() or not scene.is_node_ready():
				if t > 4.0:
					_check(false, "nodes never became ready")
					return _done()
				return false
			_run_logic_legs()
			follower = Node2D.new()
			root.add_child(follower)
			follower.global_position = map.cell_to_world(Vector2i(3, 15))
			fog.target = follower
			phase = 1
		1:
			_check(fog.state_at_cell(Vector2i(3, 15)) == TerrainFog.State.VISIBLE, "target following: target cell VISIBLE after a frame")
			_check(fog.state_at_cell(Vector2i(5, 15)) == TerrainFog.State.VISIBLE, "target following: disc edge VISIBLE")
			follower.global_position = map.cell_to_world(Vector2i(15, 15))
			phase = 2
		2:
			_check(fog.state_at_cell(Vector2i(15, 15)) == TerrainFog.State.VISIBLE, "target following: moved target cell VISIBLE")
			_check(fog.state_at_cell(Vector2i(3, 15)) == TerrainFog.State.SEEN, "target following: previous target cell now SEEN")
			fog.target = null
			phase = 3
		3:
			if not scene.walk_done:
				if t > 10.0:
					_check(false, "debug scene walk never finished")
					return _done()
				return false
			var dfog: TerrainFog = scene.fog
			var drect := Rect2i(0, 0, scene.GRID_W, scene.GRID_H)
			_check(_count(dfog, drect, TerrainFog.State.VISIBLE) > 0, "debug scene: has VISIBLE cells after walk")
			_check(_count(dfog, drect, TerrainFog.State.SEEN) > 0, "debug scene: has SEEN cells after walk")
			_check(_count(dfog, drect, TerrainFog.State.UNSEEN) > 0, "debug scene: has UNSEEN cells after walk")
			_check(dfog.state_at_cell(scene.WALK_TO) == TerrainFog.State.VISIBLE, "debug scene: marker end cell VISIBLE")
			_check(dfog.state_at_cell(scene.WALK_FROM) == TerrainFog.State.SEEN, "debug scene: walk start cell SEEN")
			_check(dfog.state_at_cell(Vector2i(16, 5)) == TerrainFog.State.UNSEEN, "debug scene: far side UNSEEN")
			return _done()
	return false

func _run_logic_legs() -> void:
	var total := BOUNDS.size.x * BOUNDS.size.y
	_check(_count(fog, BOUNDS, TerrainFog.State.UNSEEN) == 400, "fresh fog: all 400 cells UNSEEN")

	var c := Vector2i(10, 10)
	fog.update_vision(map.cell_to_world(c))
	_check(fog.state_at_cell(c) == TerrainFog.State.VISIBLE, "centre cell VISIBLE")
	_check(fog.state_at_cell(c + Vector2i(2, 0)) == TerrainFog.State.VISIBLE, "axis cell at distance r VISIBLE")
	_check(fog.state_at_cell(c + Vector2i(0, -2)) == TerrainFog.State.VISIBLE, "vertical axis cell at distance r VISIBLE")
	_check(fog.state_at_cell(c + Vector2i(1, 1)) == TerrainFog.State.VISIBLE, "diagonal (1,1) VISIBLE")
	_check(fog.state_at_cell(c + Vector2i(2, 1)) == TerrainFog.State.UNSEEN, "offset (2,1) just outside disc UNSEEN")
	_check(fog.state_at_cell(c + Vector2i(3, 0)) == TerrainFog.State.UNSEEN, "axis cell at r+1 UNSEEN")
	_check(_count(fog, BOUNDS, TerrainFog.State.VISIBLE) == 13, "r=2 disc is exactly 13 VISIBLE cells")
	_check(_count(fog, BOUNDS, TerrainFog.State.SEEN) == 0, "no SEEN cells after a single update")

	var before_visible := _count(fog, BOUNDS, TerrainFog.State.VISIBLE)
	fog.update_vision(map.cell_to_world(c))
	_check(_count(fog, BOUNDS, TerrainFog.State.VISIBLE) == before_visible and _count(fog, BOUNDS, TerrainFog.State.SEEN) == 0, "same-centre update is a no-op")
	var cell_corner := Vector2(c * map.cell_size) + Vector2(1, 1)
	fog.update_vision(cell_corner)
	_check(_count(fog, BOUNDS, TerrainFog.State.VISIBLE) == 13 and _count(fog, BOUNDS, TerrainFog.State.SEEN) == 0, "moved-but-same-cell position is a no-op")
	fog.vision_radius = 1
	fog.update_vision(map.cell_to_world(c))
	_check(_count(fog, BOUNDS, TerrainFog.State.VISIBLE) == 5 and _count(fog, BOUNDS, TerrainFog.State.SEEN) == 8, "radius change applies without moving: r=1 disc is 5 VISIBLE, 8 SEEN")
	fog.vision_radius = 2
	fog.update_vision(map.cell_to_world(c))
	_check(_count(fog, BOUNDS, TerrainFog.State.VISIBLE) == 13 and _count(fog, BOUNDS, TerrainFog.State.SEEN) == 0, "radius restored: r=2 disc is 13 VISIBLE again")

	var d := Vector2i(16, 4)
	fog.update_vision(map.cell_to_world(d))
	_check(fog.state_at_cell(c) == TerrainFog.State.SEEN, "old centre now SEEN")
	_check(fog.state_at_cell(c + Vector2i(-2, 0)) == TerrainFog.State.SEEN, "old disc edge now SEEN")
	_check(fog.state_at_cell(d) == TerrainFog.State.VISIBLE, "new centre VISIBLE")
	_check(fog.state_at_cell(d + Vector2i(0, 2)) == TerrainFog.State.VISIBLE, "new disc edge VISIBLE")
	_check(fog.state_at_cell(Vector2i(2, 18)) == TerrainFog.State.UNSEEN, "never-visited cell UNSEEN")
	_check(_count(fog, BOUNDS, TerrainFog.State.VISIBLE) == 13, "new disc is 13 VISIBLE cells")
	_check(_count(fog, BOUNDS, TerrainFog.State.SEEN) == 13, "old disc is 13 SEEN cells (explored kept, visible dropped)")
	_check(_count(fog, BOUNDS, TerrainFog.State.UNSEEN) == total - 26, "remaining 374 cells UNSEEN")

	fog.update_vision(map.cell_to_world(c + Vector2i(1, 0)))
	_check(fog.state_at_cell(c) == TerrainFog.State.VISIBLE, "revisit: SEEN cell VISIBLE again when back in range")
	_check(fog.state_at_cell(d) == TerrainFog.State.SEEN, "revisit: the far disc is now SEEN")
	_check(fog.state_at_cell(c + Vector2i(3, 0)) == TerrainFog.State.VISIBLE, "revisit: newly reached cell VISIBLE")
	_check(fog.state_at(map.cell_to_world(c)) == fog.state_at_cell(c), "world API: state_at(cell_to_world(C)) matches state_at_cell(C) (VISIBLE)")
	_check(fog.state_at(map.cell_to_world(d)) == TerrainFog.State.SEEN, "world API: state_at reads SEEN at the far centre")
	_check(fog.state_at(map.cell_to_world(Vector2i(2, 18))) == TerrainFog.State.UNSEEN, "world API: state_at reads UNSEEN at a never-visited cell")

	fog.reset()
	_check(_count(fog, BOUNDS, TerrainFog.State.UNSEEN) == 400, "reset: all 400 cells UNSEEN")
	fog.update_vision(map.cell_to_world(c))
	_check(_count(fog, BOUNDS, TerrainFog.State.VISIBLE) == 13, "reset clears cached centre: same cell re-reveals 13")

	fog.reset()
	fog.update_vision(map.cell_to_world(Vector2i(0, 0)))
	_check(_count(fog, BOUNDS, TerrainFog.State.VISIBLE) == 6, "corner disc clipped to 6 in-bounds cells")
	var wide := Rect2i(-3, -3, 26, 26)
	_check(_count(fog, wide, TerrainFog.State.VISIBLE) == 6, "corner disc marks nothing outside bounds")
	_check(fog.state_at_cell(Vector2i(-1, 0)) == TerrainFog.State.UNSEEN, "out-of-bounds cell inside the disc reads UNSEEN")
	_check(fog.state_at_cell(Vector2i(-50, -50)) == TerrainFog.State.UNSEEN, "far out-of-bounds cell reads UNSEEN")
	fog.update_vision(map.cell_to_world(Vector2i(19, 19)))
	_check(_count(fog, wide, TerrainFog.State.SEEN) + _count(fog, wide, TerrainFog.State.VISIBLE) == 12, "explored stays in bounds after a second clipped disc")
	fog.reset()

func _done() -> bool:
	print("[168] RESULT: ", "FAIL (%d)" % failures if failures > 0 else "PASS")
	quit(1 if failures > 0 else 0)
	return true
