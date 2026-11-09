extends SceneTree
## RECORDING-ONLY showcase driver for #369 (not a test, not loaded by the game).
## Boots main.tscn, enters GateDefense and plays the full defense: waits for
## each wave, kills enemies one beat at a time so the HUD wave bar (#369)
## visibly fills, and lets the next-wave countdown run before and between
## waves. God-mode player so the take never restarts.
## Usage (mirrors record_showcase.gd):
##   godot --path . --write-movie out.avi --fixed-fps 60 \
##         --script res://tools/showcase/record_defense_waves.gd

const FPS := 60.0
## One kill per beat: slow enough that the bar fill steps are readable.
const KILL_BEAT := 0.9
## Hard cap on the take length.
const MAX_SEC := 150.0

var frame := 0

func say(s: String) -> void:
	print("[rec %5.1fs] %s" % [frame / FPS, s])

func _frames(n: int) -> void:
	for i in n:
		await physics_frame
		frame += 1

func _alive(area: Node) -> Array:
	var out := []
	for e in get_nodes_in_group(&"enemies"):
		if e.get_parent() == area and (e as Enemy).hp > 0:
			out.append(e)
	return out

func _initialize() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	var p: Player = main.get_node("Player")
	p.max_hp = 100000
	p.hp = 100000
	main.enter_overworld()
	await _frames(4)
	var gate := main.current_area.get_node("GateDefense") as Gate
	gate._on_body_entered(p)
	await _frames(4)
	var area: Node = main.current_area
	var obj := area.get_node("DungeonObjective") as DungeonObjective
	if obj == null:
		say("no defense objective mounted; aborting")
		quit(1)
		return
	say("entered %s, defending through %d waves" % [area.name, obj.total_waves()])
	# Park near the core so the fight and the core stay on screen.
	var core := obj.core()
	if core != null:
		p.global_position = core.global_position + Vector2(80, 60)
	var kills := 0
	while not obj.is_cleared() and not obj.is_failed() and frame < int(MAX_SEC * FPS):
		await physics_frame
		frame += 1
		if frame % int(KILL_BEAT * FPS) == 0:
			var alive := _alive(area)
			if not alive.is_empty():
				alive[0].apply_damage(99999)
				kills += 1
	say("done: cleared=%s failed=%s kills=%d" % [obj.is_cleared(), obj.is_failed(), kills])
	await _frames(int(4 * FPS)) # hold the full bar + COMPLETE row
	quit(0)
