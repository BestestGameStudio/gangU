extends SceneTree
## #400 demo recording driver (evidence fixture, NOT production config):
## boots the real main.tscn and shows the post-clear gate cooldown.
## Labels: the cooldown is shortened to 6s so the clip stays short
## (production default is 60s), the DungeonA clear uses synthetic
## apply_damage kills, and successful entries trigger the gate's body
## callback directly. The refused bump at the closed gate is real
## input-map walking. Record: xvfb-run godot --path . -s this --write-movie out.avi

var main: Node
var p: Player
var phase := 0
var t := 0.0

func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("/tmp/demo400_%s.png" % name)
	print("[demo400] shot ", name)

func _gate(n: String) -> Gate:
	return main.current_area.get_node_or_null(n) as Gate

func _enter_via(n: String, below: float = 70.0) -> void:
	var g := _gate(n)
	if g == null:
		return
	p.global_position = g.global_position + Vector2(0, below)
	g._on_body_entered(p) # synthetic trigger (labeled); walking bump below is real

func _stop_walk() -> void:
	for a in ["move_up", "move_down", "move_left", "move_right"]:
		Input.action_release(a)

func _initialize() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	main.gate_reentry_cooldown_seconds = 3.0 # DEMO shortening; production is 60s
	p = main.get_node("Player")

func _process(delta: float) -> bool:
	t += delta
	match phase:
		0: # hub -> overworld
			if t > 0.6:
				_enter_via("GateOverworld")
				phase = 1; t = 0
		1:
			if main.current_area.name == "Overworld" and t > 0.6:
				var g := _gate("GateNormal")
				p.global_position = g.global_position + Vector2(0, 100)
				_shot("1_overworld_gates_open")
				phase = 2; t = 0
		2: # into DungeonA
			if t > 0.7:
				_enter_via("GateNormal")
				phase = 3; t = 0
		3: # synthetic clear, then exit portal
			if main.current_area.name == "DungeonA" and t > 0.8:
				for e in get_nodes_in_group("enemies"):
					e.apply_damage(9999)
				phase = 4; t = 0
		4:
			if t > 0.7:
				var portal := main.current_area.get_node_or_null("ExitPortal") as ExitPortal
				if portal != null:
					p.global_position = portal.global_position
					portal._on_body_entered(p)
				phase = 5; t = 0
		5: # back at the entrance: gate closed + dimmed
			if main.current_area.name == "Overworld" and t > 0.6:
				_shot("2_gate_closed_after_clear")
				phase = 6; t = 0
		6: # real walking bump into the closed gate: nothing happens
			var g := _gate("GateNormal")
			if g == null:
				phase = 7; t = 0
			elif t < 2.2:
				var d: Vector2 = (g.global_position - p.global_position).normalized()
				Input.action_press("move_up" if d.y < 0 else "move_down")
				if absf(d.x) > 0.3:
					Input.action_press("move_right" if d.x >= 0 else "move_left")
			else:
				_stop_walk()
				_shot("3_bumped_closed_gate_still_overworld")
				p.global_position = g.global_position + Vector2(0, 100)
				phase = 7; t = 0
		7: # wait out the (shortened) cooldown
			var g := _gate("GateNormal")
			if g != null and not g.is_disabled():
				_shot("4_gate_rearmed")
				phase = 8; t = 0
		8:
			if t > 0.6:
				_enter_via("GateNormal")
				phase = 9; t = 0
		9:
			if main.current_area.name == "DungeonA":
				_shot("5_reentered_after_cooldown")
				print("[demo400] DONE")
				quit(0)
	if t > 25.0 and phase < 9:
		print("[demo400] TIMEOUT at phase ", phase, " area=", main.current_area.name if main.current_area else "?")
		quit(1)
	return false
