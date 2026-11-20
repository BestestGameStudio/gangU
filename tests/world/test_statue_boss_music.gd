extends SceneTree
## #896: the Sunbound Sanctum statue-circle boss (stone spear men) plays
## Colin's supplied theme: it starts when the encounter starts, loops, the
## overworld piano yields to it, and on the win the theme fades out and the
## piano fades back in.

var failures := 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[statue boss music] ", label, " -> ", "PASS" if ok else "FAIL")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# Reward plumbing, as in test_statue_reward_survives_exit: the win path
	# pays out after the death animation.
	var wallet := CurrencyWallet.new()
	root.add_child(wallet)
	Run.register(wallet)
	var progress := SpellProgress.new()
	progress.add_to_group("spell_progress")
	root.add_child(progress)

	var md := MusicDirector.new()
	root.add_child(md)
	md.start_overworld()
	_check(md.overworld.playing, "overworld piano playing before the fight")
	_check(not md.boss.playing, "no boss theme before the fight")

	var area := Node2D.new()
	root.add_child(area)
	var player: Player = load("res://game/player/player.tscn").instantiate()
	player.name = "Player"
	area.add_child(player)
	player.set_physics_process(false)
	var region := Node2D.new()
	area.add_child(region)
	var arena := DesertStatueArena.new()
	region.add_child(arena)
	arena.set_physics_process(false)

	# Wired the way AreaLoader._connect_statue_arena_music does it.
	arena.encounter_started.connect(md.start_statue_boss)
	arena.encounter_won.connect(md.on_statue_fight_won)

	arena.start_encounter()
	_check(arena.state != DesertStatueArena.State.DORMANT, "encounter started")
	_check(md.boss.playing, "supplied theme playing on encounter start")
	_check(md.boss.stream == MusicDirector.STATUE_TRACK, "the theme is Colin's supplied track")
	_check((md.boss.stream as AudioStreamOggVorbis).loop, "the theme loops")
	_check(md.boss.volume_db == MusicDirector.BOSS_VOLUME_DB, "theme uses the boss volume trim")
	_check(md.overworld.stream_paused, "overworld piano yields to the theme")

	# A second start in the same fight must not restart the music.
	md.start_statue_boss()
	_check(md.boss.playing and md.boss.stream == MusicDirector.STATUE_TRACK, "repeat start keeps the theme")

	# Win the fight: the theme fades out and the piano comes back.
	arena.apply_damage(arena.hp)
	_check(arena._won, "fight is won")
	await create_timer(MusicDirector.BOSS_FADE_OUT_SEC + 0.5, false).timeout
	_check(not md.boss.playing, "theme stopped after the win fade")
	_check(not md.overworld.stream_paused, "overworld piano resumed")
	_check(absf(md.overworld.volume_db) < 0.01, "piano back at its approved gain")

	area.queue_free()
	await process_frame
	print("[statue boss music] DONE failures=", failures)
	quit(1 if failures else 0)
