extends SceneTree
## #480 headless driver: Mustache Warrior state vocal cues.
## CI has no audio device: these check playback state and routing, not
## loudness; the cues are not listened to here.
##
## Legs:
##   unit     - mapping covers all 5 states for both voices; OGG, non-loop;
##              excitable laugh omitted; enemy.tscn carries the voice node;
##              per-warrior voice draw is stable and covers both voices.
##   idle     - unengaged warrior mutters on the idle timer ONLY while the
##              player is close (#495: within idle_hear_radius, default 300
##              = on-screen; the leg widens it to 650 to exercise the gate
##              because a plain warrior within ENGAGE_RADIUS 460 is engaged,
##              so by default its idle is silent); a far player pauses the
##              timer, approaching resumes it with no backlog burst; the
##              default gap is long (25-45 s).
##   engage   - player inside ENGAGE_RADIUS: exactly one spotted bark on the
##              rising edge, then combat chatter; re-engage barks again.
##   attack   - play_action("attack") starts an attacking cue.
##   hurt     - apply_damage (non-lethal) starts a hurt cue; the cooldown
##              swallows an immediate second tick.
##   death    - lethal damage: a DETACHED one-shot player groans from the
##              area after the enemy frees itself.
##   cap      - ambient cues respect MAX_SIMULTANEOUS.
##   warlord  - the Warlord boss scene carries no MustacheVoice (scope:
##              regular moustache warriors only).

var _fails := 0

func _check(label: String, ok: bool) -> void:
	if not ok:
		_fails += 1
	print("[480] ", label, " -> ", "PASS" if ok else "FAIL")

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _unit_leg() -> void:
	var scene: PackedScene = load("res://scenes/enemy.tscn")
	_check("unit: enemy.tscn loads", scene != null)
	var e: Enemy = scene.instantiate()
	var voice := e.get_node_or_null("MustacheVoice") as MustacheVoice
	_check("unit: MustacheVoice child present", voice != null)
	_check("unit: AudioStreamPlayer2D child present", voice != null and voice.get_node_or_null("Player") is AudioStreamPlayer2D)
	var states_ok := MustacheVoice.ALIASES.has(&"idle") and MustacheVoice.ALIASES.has(&"combat") \
		and MustacheVoice.ALIASES.has(&"attacking") and MustacheVoice.ALIASES.has(&"receiving_damage") \
		and MustacheVoice.ALIASES.has(&"dying")
	_check("unit: ALIASES covers all 5 states", states_ok)
	var streams: Dictionary = MustacheVoice._STREAMS
	var complete := true
	var ogg_noloop := true
	for v in MustacheVoice.VOICES:
		for state in MustacheVoice.ALIASES:
			for alias in MustacheVoice.ALIASES[state]:
				if v == &"excitable" and alias == &"combat_laugh":
					if streams[v].has(alias):
						complete = false # excitable laugh must stay omitted
					continue
				if not streams[v].has(alias):
					complete = false
					continue
				var s: AudioStream = streams[v][alias]
				if not (s is AudioStreamOggVorbis) or (s as AudioStreamOggVorbis).loop:
					ogg_noloop = false
	_check("unit: both voices have every cue (excitable laugh omitted)", complete)
	_check("unit: all cues are non-looping OGG Vorbis", ogg_noloop)
	# Per-warrior voice draw: stable per instance, both voices appear.
	var seen := {}
	var stable := true
	for i in 30:
		var inst: Enemy = scene.instantiate()
		root.add_child(inst)
		await _frames(2)
		var mv := inst.get_node("MustacheVoice") as MustacheVoice
		seen[mv.voice] = true
		stable = stable and MustacheVoice.VOICES.has(mv.voice) and mv._cue_voice() == mv.voice
		inst.queue_free()
	await _frames(2)
	_check("unit: per-warrior voice is a valid stable draw", stable)
	_check("unit: both approved voices appear across 30 warriors", seen.has(&"gravelly") and seen.has(&"excitable"))
	e.queue_free()

## #495: spot for idle fixtures: beyond ENGAGE_RADIUS 460 and inside the
## test-widened idle_hear_radius 650 = unengaged but "close" for the gate.
const TEST_HEAR := 650.0
const IDLE_BAND := Vector2(550, 0)

func _make_fixture(with_short_timers: bool = true, player_offset: Vector2 = Vector2(6000, 6000)) -> Dictionary:
	# Bare-area fixture after the record463 idiom: real player.tscn and
	# enemy.tscn, collisions off, explicit player_path wiring.
	var area := Node2D.new()
	root.add_child(area)
	var p: Player = load("res://scenes/player.tscn").instantiate()
	p.name = "Player"
	p.collision_layer = 0
	p.collision_mask = 0
	area.add_child(p)
	p.global_position = Vector2(6000, 6000) # parked far away (re-placed below)
	p.set_physics_process(false)
	var e: Enemy = load("res://scenes/enemy.tscn").instantiate()
	e.collision_layer = 0
	e.collision_mask = 0
	e.player_path = NodePath("../Player")
	var mv := e.get_node("MustacheVoice") as MustacheVoice
	if with_short_timers:
		mv.idle_min = 0.05
		mv.idle_max = 0.08
		mv.chatter_min = 0.05
		mv.chatter_max = 0.08
	area.add_child(e)
	e.global_position = Vector2(500, 560)
	if player_offset != Vector2(6000, 6000):
		p.global_position = e.global_position + player_offset
	return {"area": area, "player": p, "enemy": e, "voice": mv}

func _teardown(fx: Dictionary) -> void:
	if is_instance_valid(fx.enemy):
		fx.enemy.queue_free()
	fx.area.queue_free()
	await _frames(3)

func _idle_leg() -> void:
	var fx := await _make_fixture(true, IDLE_BAND)
	fx.voice.idle_hear_radius = TEST_HEAR
	await _frames(12) # > 0.08s idle timer at process-frame pace
	_check("idle: unengaged warrior with the player close plays an idle cue", fx.voice.last_state == &"idle")
	_check("idle: cue is a mutter or hum", [&"idle_mutter", &"idle_hum"].has(fx.voice.last_alias))
	await _teardown(fx)
	# #495: far player = silence, and the timer does not run.
	var fx2 := await _make_fixture(true)
	var mv: MustacheVoice = fx2.voice
	mv.idle_hear_radius = TEST_HEAR
	mv._idle_timer = 0.5
	await _frames(30)
	_check("idle: player beyond the hear radius -> no idle cue", mv.cues_played == 0)
	_check("idle: the idle timer does not tick while the player is far", is_equal_approx(mv._idle_timer, 0.5))
	fx2.player.global_position = fx2.enemy.global_position + IDLE_BAND
	mv._idle_timer = 0.05
	await _frames(12)
	_check("idle: approaching resumes the timer and plays the cue", mv.last_state == &"idle")
	await _teardown(fx2)
	# Just outside the radius stays silent.
	var fx3 := await _make_fixture(true, Vector2(TEST_HEAR + 50.0, 0))
	fx3.voice.idle_hear_radius = TEST_HEAR
	await _frames(20)
	_check("idle: just beyond IDLE_HEAR_RADIUS -> silent", fx3.voice.cues_played == 0)
	await _teardown(fx3)
	# Defaults: rarer than #480's 8-16 s; "close" is on-screen (camera half
	# height 324 px at zoom 1, viewport 1152x648), so idle is silent at the
	# screen edge and beyond, and (below ENGAGE_RADIUS) silent when near too.
	var d := MustacheVoice.new()
	_check("idle: default gap is at least 25 s (was 8-16 s)", d.idle_min >= 25.0 and d.idle_max >= d.idle_min)
	_check("idle: default hear radius is on-screen (<= 324 px half-height)", d.idle_hear_radius <= 324.0)
	d.free()
	var fx4 := await _make_fixture(true, Vector2(350, 0)) # off the top/bottom edge scale, default radius
	await _frames(20)
	_check("idle: default radius, player at 350 px (about the screen edge) -> silent idle", fx4.voice.cues_played == 0 or fx4.voice.last_state != &"idle")
	await _teardown(fx4)
	var fx5 := await _make_fixture(true, Vector2(900, 0)) # off-screen
	await _frames(20)
	_check("idle: default radius, off-screen player (900 px) -> no cue at all", fx5.voice.cues_played == 0)
	await _teardown(fx5)

func _engage_leg() -> void:
	var fx := await _make_fixture()
	var e: Enemy = fx.enemy
	var mv: MustacheVoice = fx.voice
	await _frames(6)
	var idle_cues := mv.cues_played
	fx.player.global_position = e.global_position + Vector2(200, 0) # inside 460
	await _frames(6)
	_check("engage: player close plays the spotted bark once", mv.last_state == &"combat" and mv.last_alias == &"combat_spotted")
	var after_spot := mv.cues_played
	await _frames(4)
	_check("engage: no second bark while continuously engaged", mv.cues_played == after_spot or mv.last_alias != &"combat_spotted")
	await _frames(12) # chatter timer fires
	_check("engage: combat chatter follows", mv.cues_played > after_spot and MustacheVoice.ALIASES[&"combat"].has(mv.last_alias))
	# Disengage past the radius, then re-engage: fresh spotted bark.
	fx.player.global_position = e.global_position + Vector2(2000, 0)
	await _frames(6)
	fx.player.global_position = e.global_position + Vector2(200, 0)
	await _frames(6)
	_check("engage: re-engage barks again", mv.last_alias == &"combat_spotted")
	_check("engage: idle timer did not fire while engaged", mv.cues_played >= idle_cues)
	await _teardown(fx)

func _quiet_ambient(mv: MustacheVoice) -> void:
	# Keep ambient timers out of the way of event-cue assertions.
	mv.idle_min = 600.0
	mv.idle_max = 600.0
	mv.chatter_min = 600.0
	mv.chatter_max = 600.0
	mv._idle_timer = 600.0
	mv._chatter_timer = 600.0

func _attack_leg() -> void:
	var fx := await _make_fixture()
	var e: Enemy = fx.enemy
	await _frames(4)
	_quiet_ambient(fx.voice)
	e.play_action(&"attack")
	await _frames(4)
	_check("attack: attack action starts an attacking cue", fx.voice.last_state == &"attacking")
	_check("attack: cue is a grunt or exertion", [&"attack_grunt", &"attack_exertion"].has(fx.voice.last_alias))
	await _teardown(fx)

func _hurt_leg() -> void:
	var fx := await _make_fixture()
	var e: Enemy = fx.enemy
	await _frames(4)
	_quiet_ambient(fx.voice)
	await _frames(2)
	e.apply_damage(5)
	await _frames(4)
	_check("hurt: non-lethal damage plays a hurt yelp", fx.voice.last_state == &"receiving_damage" and fx.voice.last_alias == &"hurt_yelp")
	var after_first: int = fx.voice.cues_played
	e.apply_damage(5) # inside HURT_COOLDOWN
	await _frames(2)
	_check("hurt: cooldown swallows the immediate second tick", fx.voice.cues_played == after_first)
	await _teardown(fx)

func _death_leg() -> void:
	var fx := await _make_fixture()
	var e: Enemy = fx.enemy
	await _frames(4)
	var mv: MustacheVoice = fx.voice
	e.apply_damage(999)
	# died() fires synchronously inside apply_damage; the enemy (and voice)
	# are freed at frame end, so read the cue record before awaiting.
	var death_recorded: bool = mv.last_state == &"dying" and mv.last_alias == &"death_groan"
	await _frames(6) # deferred add + play of the detached one-shot
	_check("death: dying state recorded", death_recorded)
	_check("death: enemy freed itself", not is_instance_valid(e) or e.is_queued_for_deletion())
	var detached := false
	for child in fx.area.get_children():
		if child is AudioStreamPlayer2D and (child as AudioStreamPlayer2D).stream != null:
			detached = true
	_check("death: detached one-shot groans from the area", detached)
	await _teardown(fx)

func _cap_leg() -> void:
	MustacheVoice.MAX_SIMULTANEOUS = 1
	MustacheVoice._active = 0
	var fx := await _make_fixture(true, IDLE_BAND)
	fx.voice.idle_hear_radius = TEST_HEAR
	var e2: Enemy = load("res://scenes/enemy.tscn").instantiate()
	e2.collision_layer = 0
	e2.collision_mask = 0
	e2.player_path = NodePath("../Player")
	var mv2 := e2.get_node("MustacheVoice") as MustacheVoice
	mv2.idle_hear_radius = TEST_HEAR
	mv2.idle_min = 0.05
	mv2.idle_max = 0.08
	fx.area.add_child(e2)
	e2.global_position = Vector2(560, 620)
	await _frames(14)
	var playing := 0
	for n in get_nodes_in_group(&"mustache_voices"):
		var p := (n as MustacheVoice).get_node("Player") as AudioStreamPlayer2D
		if p.playing:
			playing += 1
	_check("cap: at most MAX_SIMULTANEOUS ambient speakers", playing <= 1)
	MustacheVoice.MAX_SIMULTANEOUS = 4
	e2.queue_free()
	await _teardown(fx)

func _warlord_leg() -> void:
	var scene: PackedScene = load("res://scenes/mustache_warlord.tscn")
	_check("warlord: scene loads", scene != null)
	if scene != null:
		var w := scene.instantiate()
		_check("warlord: boss carries no MustacheVoice", w.get_node_or_null("MustacheVoice") == null)
		w.queue_free()

func _run() -> void:
	await _unit_leg()
	await _idle_leg()
	await _engage_leg()
	await _attack_leg()
	await _hurt_leg()
	await _death_leg()
	await _cap_leg()
	await _warlord_leg()
	print("[480] DONE failures=", _fails)
	quit(0 if _fails == 0 else 1)
