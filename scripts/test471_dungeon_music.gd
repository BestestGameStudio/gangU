extends SceneTree
## #471 headless driver: the default dungeon music (original retro-synth loop).
## Plays in dungeon areas, silent in the hub and overworld, restarts per
## dungeon entry, yields to the #359 boss theme and resumes after it.
## Boss kills are SYNTHETIC (apply_damage), not natural combat. CI has no
## audio device: these check playback state, not loudness.
## Run: godot --headless --path . --script scripts/test471_dungeon_music.gd

const FADE_FRAMES := 120
var _fails := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, ok: bool) -> void:
	if not ok:
		_fails += 1
	print("[471] ", label, " -> ", "PASS" if ok else "FAIL")

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _enter(main: Node, gate_name: StringName) -> Node:
	main.area_loader.enter_overworld()
	await _frames(4)
	var gate := main.area_loader.current_area.get_node_or_null(NodePath(gate_name)) as Gate
	_check("%s: overworld has the gate" % gate_name, gate != null)
	if gate:
		gate._on_body_entered(main.get_node("Player"))
	await _frames(6)
	return main.area_loader.current_area

func _run() -> void:
	var s := load("res://assets/audio/music/dungeon_battle_loop.ogg")
	_check("unit: asset is an OGG Vorbis stream", s is AudioStreamOggVorbis)
	_check("unit: ~54.9 s long", absf(s.get_length() - 54.857) < 0.2)
	_check("unit: runtime trim is an attenuation", MusicDirector.DUNGEON_VOLUME_DB < 0.0)
	var a := Node2D.new(); a.name = &"DungeonA"
	var h := Node2D.new(); h.name = &"Hub"
	var o := Node2D.new(); o.name = &"Overworld"
	_check("unit: Dungeon* areas count", MusicDirector.is_dungeon_area(a))
	_check("unit: hub and overworld do not", not MusicDirector.is_dungeon_area(h) and not MusicDirector.is_dungeon_area(o))
	a.free(); h.free(); o.free()

	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(3)
	var dm: AudioStreamPlayer = main.music.dungeon
	var bm: AudioStreamPlayer = main.music.boss
	_check("boot: dungeon player mounted, silent", dm != null and not dm.playing)
	main.area_loader.enter_overworld()
	await _frames(4)
	_check("overworld: silent", not dm.playing)

	# DungeonA (normal gate): plays, looping, trimmed.
	var area := await _enter(main, &"GateNormal")
	_check("GateNormal mounted a dungeon", area != null and MusicDirector.is_dungeon_area(area))
	_check("dungeon: loop playing", dm.playing and dm.stream == s)
	_check("dungeon: loops", (dm.stream as AudioStreamOggVorbis).loop)
	_check("dungeon: volume trimmed", is_equal_approx(dm.volume_db, MusicDirector.DUNGEON_VOLUME_DB))
	_check("dungeon: no boss theme", not bm.playing)

	# Back to the overworld: silent. Re-enter: restarts from the top.
	main.area_loader.enter_overworld()
	await _frames(4)
	_check("back to overworld: silent", not dm.playing)
	area = await _enter(main, &"GateNormal")
	_check("re-entry: playing again", dm.playing)

	# Every other dungeon entry plays too (all dungeons, Colin 2026-11-09 yes).
	for g in [&"GateMaze", &"GateGenerated", &"GateRed"]:
		main.area_loader.enter_overworld()
		await _frames(4)
		area = await _enter(main, g)
		_check("%s: dungeon mounted and loop playing" % g, area != null and MusicDirector.is_dungeon_area(area) and dm.playing)

	# Boss dungeon (Beast den): boss theme takes over, dungeon loop yields.
	main.area_loader.enter_overworld()
	await _frames(4)
	area = await _enter(main, &"GateBeast")
	_check("Beast den mounted", area != null and area.name == &"DungeonD")
	await _frames(20)
	_check("Beast den: boss theme playing", bm.playing)
	_check("Beast den: dungeon loop yields (paused)", dm.stream_paused and not dm.playing)
	for b in get_nodes_in_group(&"boss"):
		b.apply_damage(9999) # synthetic kill
	await _frames(FADE_FRAMES)
	_check("boss down: boss theme stopped", not bm.playing)
	_check("boss down: dungeon loop resumed", dm.playing and not dm.stream_paused)
	_check("boss down: volume back to trim", is_equal_approx(dm.volume_db, MusicDirector.DUNGEON_VOLUME_DB))

	# Leaving the dungeon silences it.
	main.area_loader.enter_overworld()
	await _frames(4)
	_check("leaving: silent", not dm.playing and not dm.stream_paused)
	main.queue_free()
	await _frames(3)
	print("[471] DONE failures=", _fails)
	print("RESULT: ALL PASS" if _fails == 0 else "RESULT: FAIL")
	quit(_fails)
