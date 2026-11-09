extends SceneTree
## RECORDING-ONLY showcase driver for #391 (not a test, not loaded by the game).
## Boots main.tscn, enters the overworld, walks the hero straight INTO a
## tree (he stops at it instead of passing through), sidesteps around it,
## then releases a chaser on the far side of the tree - it paths AROUND the
## tree to reach the hero instead of stalling on it.
## Usage (see .claude/skills/showcase-video):
##   xvfb-run -a godot --rendering-driver opengl3 --path . \
##     --write-movie out.avi --fixed-fps 30 \
##     --script res://tools/showcase/record_tree_collision.gd

const FPS := 30.0

var scene: Node
var p: Player
var cam: Camera2D
var focus: Node2D
var ground: OverworldGround
var map: TerrainMap
var frame := 0
var move_target = null

func say(s: String) -> void:
	print("[rec391 %5.2fs] %s" % [frame / FPS, s])

func _press(dir: Vector2) -> void:
	for pair in [[&"move_right", dir.x], [&"move_left", -dir.x], [&"move_down", dir.y], [&"move_up", -dir.y]]:
		if pair[1] > 0.0:
			Input.action_press(pair[0], pair[1])
		else:
			Input.action_release(pair[0])

func _tick() -> void:
	frame += 1
	if move_target != null:
		var to: Vector2 = (move_target as Vector2) - p.global_position
		_press(Vector2.ZERO if to.length() < 4.0 else to.normalized())
	else:
		_press(Vector2.ZERO)
	if p.hp < 40:
		p.heal(60) # RECORDING-ONLY: keep the hero alive for the shot

func _wait(sec: float) -> void:
	for i in int(sec * FPS):
		await physics_frame
		_tick()

## An isolated tree near the arrival point, so the shot stays compact.
func _pick_tree() -> Dictionary:
	var spawn: Vector2 = ground.spawn
	var best: Dictionary = {}
	var best_score := -INF
	for d in ground.decor:
		if d["kind"] != "tree" or d["r"] < 22.0:
			continue
		var at: Vector2 = d["at"]
		if at.distance_to(spawn) > 620.0:
			continue
		var nearest := INF
		for o in ground.decor:
			if o != d:
				nearest = minf(nearest, at.distance_to(o["at"]))
		var score: float = minf(nearest, 160.0) - at.distance_to(spawn) * 0.05
		if score > best_score:
			best_score = score
			best = d
	return best

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	p = scene.get_node("Player")
	p.set_process(false) # movement is driven here via Input actions
	cam = scene.get_node("FollowCamera")
	p.speed = 170.0 # RECORDING-ONLY: calmer walk for the camera
	focus = Node2D.new()
	scene.add_child(focus)
	cam.target = focus
	cam.follow_speed = 3.5

	say("hub -> overworld")
	await _wait(1.0)
	scene.enter_overworld()
	await _wait(0.5)
	ground = scene.current_area.get_node("Ground") as OverworldGround
	map = scene.current_area.get_node("Terrain") as TerrainMap

	var tree := _pick_tree()
	var t: Vector2 = tree["at"]
	say("tree at %s (r %.0f)" % [t, tree["r"]])
	focus.global_position = t
	cam.global_position = t
	# Hero starts south of the tree.
	p.global_position = t + Vector2(0, 150)
	await _wait(0.8)

	# --- Beat 1: walk straight at the tree - blocked. ---
	say("beat 1: walking INTO the tree (blocked)")
	move_target = t + Vector2(0, -140) # through the tree
	await _wait(2.6)
	say("hero stopped %0.1fpx from the tree centre" % p.global_position.distance_to(t))
	await _wait(0.6)

	# --- Beat 2: sidestep around it. ---
	say("beat 2: around the tree by hand")
	move_target = t + Vector2(120, 60)
	await _wait(1.6)
	move_target = t + Vector2(100, -110)
	await _wait(1.8)

	# --- Beat 3: a chaser released on the far side paths around. ---
	say("beat 3: chaser released north of the tree")
	move_target = t + Vector2(0, 40) # hero holds just south of the tree
	p.add_to_group("player") # RECORDING-ONLY: let the spawned enemy resolve its target in _ready
	var enemy: Enemy = load("res://scenes/enemy.tscn").instantiate()
	enemy.terrain = map
	enemy.global_position = t + Vector2(0, -140)
	scene.current_area.add_child(enemy)
	await _wait(5.0)
	say("chaser reached %0.1fpx from the hero" % enemy.global_position.distance_to(p.global_position))
	await _wait(1.2)
	move_target = null
	say("done")
	quit(0)
