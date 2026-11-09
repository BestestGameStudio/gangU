extends SceneTree
## #359 headless driver: RED dungeon bosses play a (dampened) boss theme.
## Legs:
##   unit   - BossMusic loads both tracks, loops them, trims volume, picks
##            either track across seeded starts, fade_out() stops playback
##   red    - every offering forced RED: GateRed -> DungeonB, clear mobs, the
##            Warlord spawns and a boss theme plays; killing it fades it out;
##            leaving the dungeon keeps it silent
##   normal - every offering forced NORMAL: same boss, no music
##   swap   - a theme playing when the area swaps is stopped immediately
## Gate/portal use follows the test350 direct _on_body_entered idiom; kills use
## the apply_damage shortcut, not natural combat.

const OFFERING_PATH := "res://resources/gate_offering.tres"
var _fails := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, ok: bool) -> void:
	if not ok:
		_fails += 1
	print("[359] ", label, " -> ", "PASS" if ok else "FAIL")

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _boot() -> Node:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(3)
	return main

func _shutdown(main: Node) -> void:
	main.queue_free()
	await _frames(3)

func _run() -> void:
	await _unit_leg()
	var offering := load(OFFERING_PATH) as GateOffering
	offering.red_chance = 1.0
	await _boss_leg(true)
	offering.red_chance = 0.0
	await _boss_leg(false)
	offering.red_chance = 1.0
	await _swap_leg()
	offering.red_chance = GateOffering.UNSET
	_finish()

func _unit_leg() -> void:
	_check("unit: two boss tracks", BossMusic.TRACKS.size() == 2 and BossMusic.TRACKS.all(func(s): return s is AudioStreamOggVorbis))
	_check("unit: runtime trim is an attenuation", BossMusic.MUSIC_VOLUME_DB < 0.0)
	var m := BossMusic.new()
	root.add_child(m)
	var rng := RandomNumberGenerator.new()
	rng.seed = 359
	var seen := {}
	for i in 20:
		m.stop_music()
		m.start(rng)
		seen[m.stream] = true
	_check("unit: both tracks get picked", seen.size() == 2)
	_check("unit: playing after start", m.playing)
	_check("unit: track loops", (m.stream as AudioStreamOggVorbis).loop)
	_check("unit: volume trimmed", is_equal_approx(m.volume_db, BossMusic.MUSIC_VOLUME_DB))
	var s := m.stream
	m.start(rng)
	_check("unit: start() while playing keeps the same track", m.stream == s and m.playing)
	m.fade_out()
	await _frames(int(BossMusic.FADE_OUT_SEC * 60) + 20)
	_check("unit: fade_out stops playback", not m.playing)
	_check("unit: volume restored after fade", is_equal_approx(m.volume_db, BossMusic.MUSIC_VOLUME_DB))
	m.free()

## Enter DungeonB through GateRed, clear mobs so the Warlord spawns.
func _to_boss(main: Node) -> Node:
	main.enter_overworld()
	await _frames(4)
	var p: Player = main.get_node("Player")
	var gate := main.current_area.get_node_or_null("GateRed") as Gate
	gate._on_body_entered(p)
	await _frames(6)
	for e in get_nodes_in_group("enemies"):
		e.apply_damage(999999)
	await _frames(10)
	return main.current_area

func _boss_leg(red: bool) -> void:
	var tag := "red" if red else "normal"
	var main := await _boot()
	var music := main.get_node_or_null("BossMusic") as BossMusic
	_check(tag + ": Main mounts BossMusic", music != null)
	_check(tag + ": silent before the boss", music != null and not music.playing)
	var area := await _to_boss(main)
	_check(tag + ": in DungeonB", area.name == &"DungeonB")
	var bosses := get_nodes_in_group("enemies")
	_check(tag + ": Warlord spawned", bosses.size() == 1)
	if red:
		_check("red: boss theme plays", music.playing and music.stream in BossMusic.TRACKS)
		for b in bosses:
			b.apply_damage(999999)
		await _frames(int(BossMusic.FADE_OUT_SEC * 60) + 30)
		var portal := area.get_node("ExitPortal") as ExitPortal
		_check("red: boss dead unlocks portal", not portal.locked)
		_check("red: theme faded out after the kill", not music.playing)
	else:
		_check("normal: no boss theme for a NORMAL dungeon boss", not music.playing)
	await _shutdown(main)

func _swap_leg() -> void:
	var main := await _boot()
	var music := main.get_node("BossMusic") as BossMusic
	await _to_boss(main)
	_check("swap: theme playing mid-fight", music.playing)
	main._load_hub()
	await _frames(3)
	_check("swap: leaving the dungeon stops the theme", not music.playing and main.current_area.name == &"Hub")
	await _shutdown(main)

func _finish() -> void:
	print("[359] RESULT: ", "ALL PASS" if _fails == 0 else "FAIL", " failures=", _fails)
	quit(0 if _fails == 0 else 1)
