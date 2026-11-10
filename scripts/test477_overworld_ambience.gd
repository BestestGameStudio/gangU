extends SceneTree
## #477 headless driver (updated for the #487 soft piano track): the overworld music loop. Plays in the overworld,
## is absent from the hub and dungeons (it lives in overworld.tscn and goes
## with it), loops, and keeps the approved level (no gain trim).
## CI has no audio device: these check playback state, not loudness.
## Run: godot --headless --path . --script scripts/test477_overworld_ambience.gd

var _fails := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, ok: bool) -> void:
	if not ok:
		_fails += 1
	print("[477] ", label, " -> ", "PASS" if ok else "FAIL")

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _run() -> void:
	var s := load("res://assets/audio/music/overworld_soft_piano_loop.ogg")
	_check("unit: asset is an OGG Vorbis stream", s is AudioStreamOggVorbis)
	_check("unit: ~81.8 s long", absf(s.get_length() - 81.778) < 0.2)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(4)
	main.area_loader.enter_overworld()
	await _frames(4)
	# #512: the run's MusicDirector (Main/music) plays the piano while the
	# overworld is the current area; it replaces the scene-mounted player.
	var amb: AudioStreamPlayer = main.music.overworld
	_check("the director has an overworld player", amb != null)
	if amb:
		_check("overworld: playing", amb.playing)
		_check("overworld: loops", (amb.stream as AudioStreamOggVorbis).loop)
		_check("overworld: level untouched (0 dB, no trim)", is_equal_approx(amb.volume_db, 0.0))
		_check("overworld: plays the committed asset", amb.stream == s)
	var gate := main.area_loader.current_area.get_node_or_null("GateNormal") as Gate
	_check("overworld has the normal gate", gate != null)
	if gate:
		gate._on_body_entered(main.get_node("Player"))
	await _frames(6)
	_check("dungeon: area is a dungeon", String(main.area_loader.current_area.name).begins_with("Dungeon"))
	_check("dungeon: no scene-mounted ambience player", main.area_loader.current_area.get_node_or_null("Ambience") == null)
	_check("dungeon: overworld piano stopped", not amb.playing)
	var found := 0
	for n in main.find_children("*", "OverworldAmbience", true, false):
		if not n.is_queued_for_deletion():
			found += 1
	_check("dungeon: no live OverworldAmbience anywhere", found == 0)
	main.area_loader.enter_overworld()
	await _frames(4)
	var amb2: AudioStreamPlayer = main.music.overworld
	_check("back in the overworld: playing again from the top", amb2 != null and amb2.playing and amb2.get_playback_position() < 1.0)
	var hub := (load("res://scenes/hub.tscn") as PackedScene).instantiate()
	_check("hub scene has no ambience player", hub.get_node_or_null("Ambience") == null)
	hub.free()
	print("[477] ", "ALL PASS" if _fails == 0 else "%d FAILURES" % _fails)
	quit(0 if _fails == 0 else 1)
