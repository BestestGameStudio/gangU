extends SceneTree
## Headless production-composition regression for NORMAL gate transport.
## Real Input actions move the production Player into the production Area2D.
## No direct signal emission, gate callback, _swap call, or position injection.
## This is new coverage, not browser evidence or a diagnosed bug/fix claim.

const MAX_ENTRY_FRAMES := 120
const SETTLE_FRAMES := 12
var _fails := 0
var _main: Node
var _player: Player

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, ok: bool) -> void:
	if not ok:
		_fails += 1
	print("[306] ", label, " -> ", "PASS" if ok else "FAIL")

func _release_movement() -> void:
	Input.action_release(&"move_up")
	Input.action_release(&"move_left")

func _finish() -> void:
	_release_movement()
	if is_instance_valid(_main):
		_main.queue_free()
		await process_frame
	print("[306] RESULT: ", "ALL PASS" if _fails == 0 else "FAIL", " failures=", _fails)
	quit(0 if _fails == 0 else 1)

func _run() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	for i in 3:
		await physics_frame
	_player = _main.get_node_or_null("Player") as Player
	_check("production main boots into Hub", _main.current_area != null and _main.current_area.name == &"Hub")
	_check("production Player exists", _player != null)
	if _player == null or _main.current_area == null or _main.current_area.name != &"Hub":
		await _finish()
		return
	# #346: the NORMAL gate lives in the overworld. Walk up from the hub
	# spawn (576,480) into the hub's TRAVEL gate (576,240) with real input.
	var hub_area: Node = _main.current_area
	var travel := hub_area.get_node_or_null("GateOverworld") as Gate
	_check("Hub has the TRAVEL gate to the overworld", travel != null and travel.gate_type == Gate.GateType.TRAVEL)
	Input.action_press(&"move_up")
	var travel_frames := 0
	while _main.current_area == hub_area and travel_frames < MAX_ENTRY_FRAMES:
		await physics_frame
		travel_frames += 1
	_release_movement()
	_check("walking up through the hub passage reaches the Overworld", _main.current_area != null and _main.current_area.name == &"Overworld")
	if _main.current_area == null or _main.current_area.name != &"Overworld":
		await _finish()
		return
	var ow_spawn := _main.current_area.get_node("PlayerSpawn") as Node2D
	_check("travel lands exactly on the overworld PlayerSpawn", _player.global_position == ow_spawn.global_position)
	var hub: Node = _main.current_area
	var gate := hub.get_node_or_null("GateNormal") as Gate
	_check("Overworld has production NORMAL gate with a target", gate != null and gate.gate_type == Gate.GateType.NORMAL and gate.target_dungeon != null)
	if gate == null or gate.target_dungeon == null:
		await _finish()
		return
	var player_id := _player.get_instance_id()
	var entries := [0]
	gate.entered.connect(func(body_gate: Gate):
		if body_gate == gate:
			entries[0] += 1
	)
	# Overworld spawn (576,480) to gate row (y380), then left into GateNormal.
	# Sample at physics_frame, before Player's next movement step. On the
	# first frame after deferred transport, release input before it can move
	# away from the destination spawn, then assert the exact spawn position.
	Input.action_press(&"move_up")
	for i in 19:
		await physics_frame
	Input.action_release(&"move_up")
	Input.action_press(&"move_left")
	var entry_frames := 0
	while _main.current_area == hub and entry_frames < MAX_ENTRY_FRAMES:
		await physics_frame
		entry_frames += 1
	_release_movement()
	_check("real collider emits Gate.entered exactly once", entries[0] == 1)
	_check("area changes within bounded input frames", _main.current_area != hub and entry_frames < MAX_ENTRY_FRAMES)
	var area: Node = _main.current_area
	_check("NORMAL gate enters DungeonA", area != null and area.name == &"DungeonA")
	_check("same persistent Player instance after transport", is_instance_valid(_player) and _main.get_node_or_null("Player") == _player and _player.get_instance_id() == player_id)
	var spawn := area.get_node_or_null("PlayerSpawn") as Node2D if area != null else null
	_check("target area supplies PlayerSpawn", spawn != null)
	if spawn != null and is_instance_valid(_player):
		_check("Player exactly at target PlayerSpawn on first post-swap physics frame", _player.global_position == spawn.global_position)
	print("[306] entry_frames=", entry_frames, " area=", area.name if area != null else "null", " position=", _player.global_position)
	for i in SETTLE_FRAMES:
		await physics_frame
	_check("DungeonA remains active after bounded settling", _main.current_area == area and area != hub)
	_check("Player remains the original instance after settling", is_instance_valid(_player) and _main.get_node_or_null("Player") == _player and _player.get_instance_id() == player_id)
	await _finish()
