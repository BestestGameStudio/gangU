extends SceneTree
## RECORDING-ONLY showcase driver for #464 (not a test, not loaded by the
## game). Boots main.tscn, enters DungeonB through the overworld red gate
## (production spawns: 3 Mustache Warriors + the Fishy) and parks the hero
## in the Fishy's range. The hero stands still (no input), so the clip
## shows the wind-up telegraph, the straight cast, the hook landing, the
## reel-in and the warriors grouping up. RECORDING-ONLY: HP floor so a
## death never reloads the run, and a small state readout over the Fishy.
## Usage:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x720 \
##     --write-movie /tmp/ci/shots/frame.png --fixed-fps 30 --quit-after 330 \
##     --script res://tools/showcase/record464_fishy.gd

var scene: Node
var p: Player
var fishy: Enemy
var focus: Node2D
var label: Label
var frame := 0

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	p = scene.get_node("Player")
	p.set_process(false)
	var cam: Camera2D = scene.get_node("FollowCamera")
	focus = Node2D.new()
	scene.add_child(focus)
	cam.target = focus
	await _frames(10)
	scene.enter_overworld()
	await _frames(3)
	var g: Gate = scene.current_area.get_node("GateRed")
	g.gate_type = Gate.GateType.RED
	g._on_body_entered(p)
	await _frames(6)
	for e in get_nodes_in_group("enemies"):
		if e.scene_file_path == "res://scenes/enemy_fishy.tscn":
			fishy = e
	if fishy == null:
		push_error("record464: no Fishy in %s" % scene.current_area.name)
		quit(1)
		return
	p.global_position = fishy.global_position + Vector2(340, -60)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 12)
	label.z_index = 60
	scene.current_area.add_child(label)
	var layer := CanvasLayer.new()
	layer.layer = 100
	scene.add_child(layer)
	var banner := Label.new()
	banner.text = "#464 Fishy - production DungeonB spawns, hero idle (no input), HP floor on"
	banner.position = Vector2(8, 80)
	banner.add_theme_font_size_override("font_size", 16)
	layer.add_child(banner)
	while true:
		await physics_frame
		_tick()

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _tick() -> void:
	frame += 1
	if p.hp < 40:
		p.heal(60)
	if not is_instance_valid(fishy):
		return
	focus.global_position = p.global_position.lerp(fishy.global_position, 0.5)
	var b := fishy.get("_behavior") as EnemyBehaviorFishy
	label.text = "Fishy: %s%s" % [EnemyBehaviorFishy.State.keys()[b.state], "" if b.last_result == &"" else "  (last: %s)" % b.last_result]
	label.global_position = fishy.global_position + Vector2(-40, -60)
