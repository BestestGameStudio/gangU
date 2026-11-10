extends SceneTree
## RECORDING-ONLY showcase driver for #490 (not a test, not loaded by the
## game). Boots main.tscn, travels to one area and freezes every enemy so a
## still frame shows the production spawn mix (Fishy vs Mustache Warriors).
## Pick the area after `--`: dungeon_a | dungeon_b | generated |
## camp_normal | camp_red | camp_generated | camp_beast | camp_boss.
## Usage:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x720 \
##     --write-movie /tmp/ci/shots/frame.png --fixed-fps 30 --quit-after 40 \
##     --script res://tools/showcase/record490_fish_spawns.gd -- dungeon_a

const GATES := {
	"dungeon_a": "GateNormal", "dungeon_b": "GateRed", "generated": "GateGenerated",
	"camp_normal": "GateNormal", "camp_red": "GateRed", "camp_generated": "GateGenerated",
	"camp_beast": "GateBeast", "camp_boss": "GateBoss",
}

var scene: Node

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "dungeon_a"
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var p: Player = scene.get_node("Player")
	p.set_process(false)
	var cam: Camera2D = scene.get_node("FollowCamera")
	var focus := Node2D.new()
	scene.add_child(focus)
	cam.target = focus
	await _frames(10)
	scene.enter_overworld()
	await _frames(3)
	var gate: Gate = scene.current_area.get_node(GATES[mode])
	if mode.begins_with("camp_"):
		_freeze()
		focus.global_position = gate.global_position + Vector2(0, -40)
		p.global_position = gate.global_position + Vector2(0, 2000)
	else:
		if mode == "dungeon_b":
			gate.gate_type = Gate.GateType.RED
		gate._on_body_entered(p)
		await _frames(4)
		_freeze()
		focus.global_position = Vector2(576, 350) if mode != "generated" else p.global_position
	cam.target = focus
	cam.zoom = Vector2(0.75, 0.75) if mode.begins_with("dungeon") or mode.begins_with("camp") else Vector2(0.5, 0.5)
	var fish := 0
	var warriors := 0
	for e in get_nodes_in_group("enemies"):
		if e.scene_file_path == "res://scenes/enemy_fishy.tscn":
			fish += 1
		elif e.scene_file_path == "res://scenes/enemy.tscn":
			warriors += 1
		if mode.begins_with("camp_") and (e as Node2D).global_position.distance_to(gate.global_position) > 420.0:
			continue
		if mode == "generated" and fish == 1 and e.scene_file_path == "res://scenes/enemy_fishy.tscn":
			focus.global_position = (e as Node2D).global_position
		var tag := Label.new()
		tag.text = "FISHY" if e.scene_file_path == "res://scenes/enemy_fishy.tscn" else ""
		tag.add_theme_font_size_override("font_size", 14)
		tag.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
		tag.z_index = 60
		scene.current_area.add_child(tag)
		tag.global_position = (e as Node2D).global_position + Vector2(-22, -58)
	var layer := CanvasLayer.new()
	layer.layer = 100
	scene.add_child(layer)
	var banner := Label.new()
	banner.text = "#490 %s (%s): %d Fishy / %d Mustache Warriors in the area (enemies frozen)" % [mode, scene.current_area.name, fish, warriors]
	banner.position = Vector2(8, 80)
	banner.add_theme_font_size_override("font_size", 18)
	layer.add_child(banner)

func _freeze() -> void:
	for e in get_nodes_in_group("enemies"):
		(e as Node).process_mode = Node.PROCESS_MODE_DISABLED

func _frames(n: int) -> void:
	for i in n:
		await physics_frame
