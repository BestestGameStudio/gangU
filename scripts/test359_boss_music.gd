extends SceneTree
## #359 headless driver: boss fights play a (dampened) boss theme in RED-entered
## dungeons and in the Head / Beast boss arenas; NORMAL dungeon bosses are silent.
## Every boss leg boots the production main.tscn (Main composition, real
## overworld gates, real DungeonObjective boss spawn).
## Legs:
##   unit    - BossMusic loads both tracks, loops them, trims volume, picks
##             either track across seeded starts, fade_out() stops playback
##   red     - FORCED CHANCE (red_chance = 1.0): GateRed -> DungeonB, mobs
##             cleared, the Warlord spawns and a theme plays; SYNTHETIC KILL
##             (apply_damage) fades it out; leaving by the portal stays silent
##   normal  - FORCED CHANCE (red_chance = 0.0): same dungeon, same boss, silent
##   head    - GateBoss -> DungeonC: theme starts with the Head's spawn,
##             SYNTHETIC KILL fades it, portal exit to the hub stays silent
##   beast   - GateBeast -> DungeonD: same for the Beast
##   swap    - theme playing mid-fight (RED, Head) stops on an area swap
##   restart - theme playing in the Beast fight; the player dies through the
##             production RunManager path; the reload frees the old player
##             and the new run's BossMusic is silent in the hub
## Gate/portal use follows the test350 DIRECT _on_body_entered CALLBACK idiom.
## CI has no audio device: these check playback state, not loudness.

const OFFERING_PATH := "res://resources/gate_offering.tres"
const FADE_FRAMES := 120 # > BossMusic.FADE_OUT_SEC at 60 physics fps
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
	if is_instance_valid(main):
		main.queue_free()
	current_scene = null
	await _frames(3)

func _run() -> void:
	await _unit_leg()
	var offering := load(OFFERING_PATH) as GateOffering
	offering.red_chance = 1.0
	await _red_or_normal_leg(true)
	offering.red_chance = 0.0
	await _red_or_normal_leg(false)
	offering.red_chance = 1.0
	await _swap_leg(&"GateRed", &"DungeonB")
	offering.red_chance = GateOffering.UNSET
	await _arena_leg("head", &"GateBoss", &"DungeonC", EnemyBehaviorHead)
	await _arena_leg("beast", &"GateBeast", &"DungeonD", null)
	await _swap_leg(&"GateBoss", &"DungeonC")
	await _restart_leg()
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
	await _frames(FADE_FRAMES)
	_check("unit: fade_out stops playback", not m.playing)
	_check("unit: volume restored after fade", is_equal_approx(m.volume_db, BossMusic.MUSIC_VOLUME_DB))
	m.free()

## Overworld -> gate (direct callback) -> area. Returns the mounted area.
func _enter(main: Node, gate_name: StringName) -> Node:
	main.enter_overworld()
	await _frames(4)
	var p: Player = main.get_node("Player")
	var gate := main.current_area.get_node_or_null(NodePath(gate_name)) as Gate
	_check("%s: overworld has the gate" % gate_name, gate != null)
	if gate:
		gate._on_body_entered(p)
	await _frames(6)
	return main.current_area

func _bosses() -> Array[Node]:
	return get_nodes_in_group(&"boss")

func _theme_on(music: BossMusic) -> bool:
	return music != null and music.playing and music.stream in BossMusic.TRACKS \
		and is_equal_approx(music.volume_db, BossMusic.MUSIC_VOLUME_DB)

## Kill the boss (SYNTHETIC KILL), let the fade run, leave by the exit portal.
func _kill_and_leave(tag: String, main: Node, area: Node, music: BossMusic) -> void:
	for b in _bosses():
		(b as Enemy).apply_damage(999999)
	await _frames(4)
	_check(tag + ": theme still audible at the start of the fade", music.playing)
	await _frames(FADE_FRAMES)
	var portal := area.get_node("ExitPortal") as ExitPortal
	_check(tag + ": boss dead unlocks the portal", not portal.locked)
	_check(tag + ": theme faded out after the kill", not music.playing)
	portal._on_body_entered(main.get_node("Player"))
	await _frames(6)
	_check(tag + ": back at the overworld entrance (#378), still silent", main.current_area.name == &"Overworld" and not music.playing)

func _red_or_normal_leg(red: bool) -> void:
	var tag := "red" if red else "normal"
	var main := await _boot()
	var music := main.get_node_or_null("BossMusic") as BossMusic
	_check(tag + ": Main mounts BossMusic", music != null)
	_check(tag + ": silent before the boss", music != null and not music.playing)
	var area := await _enter(main, &"GateRed")
	_check(tag + ": in DungeonB", area.name == &"DungeonB")
	_check(tag + ": entry type is " + ("RED" if red else "NORMAL"), main._area_is_red(area) == red)
	_check(tag + ": silent while only mobs are up", not music.playing)
	for e in get_nodes_in_group(&"enemies"):
		e.apply_damage(999999) # SYNTHETIC KILL of the mobs so the Warlord spawns
	await _frames(10)
	_check(tag + ": Warlord spawned", _bosses().size() == 1)
	if red:
		_check("red: boss theme plays at runtime trim", _theme_on(music))
		await _kill_and_leave("red", main, area, music)
	else:
		_check("normal: no boss theme for a NORMAL dungeon boss", not music.playing)
		await _frames(30)
		_check("normal: still silent a moment later", not music.playing)
	await _shutdown(main)

func _arena_leg(tag: String, gate_name: StringName, area_name: StringName, behavior: Variant) -> void:
	var main := await _boot()
	var music := main.get_node("BossMusic") as BossMusic
	_check(tag + ": silent before the arena", not music.playing)
	var area := await _enter(main, gate_name)
	_check(tag + ": in " + area_name, area.name == area_name)
	_check(tag + ": entered through a BOSS gate, not RED", not main._area_is_red(area))
	var bosses := _bosses()
	_check(tag + ": boss spawned by the production objective", bosses.size() == 1 and bosses[0].get_parent() == area)
	if behavior != null and bosses.size() == 1:
		_check(tag + ": it is the Head", (bosses[0] as Enemy)._behavior is EnemyBehaviorHead)
	_check(tag + ": boss theme plays at runtime trim", _theme_on(music))
	await _kill_and_leave(tag, main, area, music)
	await _shutdown(main)

func _swap_leg(gate_name: StringName, area_name: StringName) -> void:
	var tag := "swap(%s)" % area_name
	var main := await _boot()
	var music := main.get_node("BossMusic") as BossMusic
	await _enter(main, gate_name)
	if main.current_area.name == &"DungeonB":
		for e in get_nodes_in_group(&"enemies"):
			e.apply_damage(999999)
		await _frames(10)
	_check(tag + ": theme playing mid-fight", music.playing)
	main._load_hub()
	await _frames(3)
	_check(tag + ": leaving the dungeon stops the theme", not music.playing and main.current_area.name == &"Hub")
	await _shutdown(main)

func _restart_leg() -> void:
	var main := await _boot()
	var music := main.get_node("BossMusic") as BossMusic
	await _enter(main, &"GateBeast")
	_check("restart: Beast theme playing before death", music.playing)
	(main.get_node("Player") as Player).apply_damage(100000) # production death -> RunManager
	var waited := 0
	while waited < 900 and (current_scene == main or current_scene == null or not is_instance_valid(current_scene) or current_scene.get("current_area") == null):
		await physics_frame
		waited += 1
	var fresh := current_scene
	_check("restart: run reloaded through RunManager", fresh != main and is_instance_valid(fresh))
	await _frames(5)
	_check("restart: the old run's player is gone", not is_instance_valid(music))
	var fresh_music := fresh.get_node_or_null("BossMusic") as BossMusic
	_check("restart: exactly one BossMusic in the new run", fresh_music != null and _count_players(root) == 1)
	_check("restart: new run starts silent in the hub", fresh.current_area.name == &"Hub" and not fresh_music.playing)
	await _shutdown(fresh)

func _count_players(n: Node) -> int:
	var c := 1 if n is BossMusic else 0
	for k in n.get_children():
		c += _count_players(k)
	return c

func _finish() -> void:
	print("[359] RESULT: ", "ALL PASS" if _fails == 0 else "FAIL", " failures=", _fails)
	quit(0 if _fails == 0 else 1)
