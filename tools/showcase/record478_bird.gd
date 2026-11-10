extends SceneTree
## RECORDING-ONLY showcase driver for #478 (not a test, not loaded by the
## game). Boots main.tscn, jumps into the overworld and stages the branch
## behavior with PRODUCTION scenes/scripts:
##   beat1 circle:    day - the bird circles off screen, its ground shadow
##                    orbits the hero.
##   beat2 dive:      the telegraph ring locks ON the hero (0.7s to run),
##                    the dive lands: moderate damage + 0.5s hero stun;
##                    the bird is stunned 1s on the ground.
##   beat3 punish:    hits during the landing stun extend it to 4s
##                    (synthetic hits, disclosed) - the kill window.
##   beat4 redive:    takeoff, then the next dive comes on its 3-10s draw.
##   beat5 nightfall: the bird flies off and despawns (day only).
## The recorder only teleports the hero, holds an HP floor, scrubs the
## DayNightClock between beats and lands the two disclosed punish hits;
## the bird, telegraph, stuns and the clock run untouched production code.
## Usage:
##   xvfb-run -a godot --path . --write-movie out.avi --fixed-fps 60 \
##         --rendering-driver opengl3 --script res://tools/showcase/record478_bird.gd

const FPS := 60.0

var scene: Node
var p: Player
var cam: Camera2D
var focus: Node2D
var frame := 0
var _beat_label: Label
var _beat := "setup"
var _beat_started := 0.0
var _mgr: OverworldBird
var _clock: DayNightClock

func say(s: String) -> void:
	print("[rec %5.2fs] %s" % [frame / FPS, s])

func _wait(sec: float) -> void:
	for i in int(sec * FPS):
		await physics_frame
		_tick()

func _set_beat(beat: String) -> void:
	_beat = beat
	_beat_started = frame / FPS
	say(beat)

func _hop(pos: Vector2, note: String) -> void:
	p.global_position = pos # RECORDING-ONLY staging, disclosed
	focus.global_position = pos
	cam.global_position = pos
	say(note)

func _bird() -> Enemy:
	if _mgr != null and is_instance_valid(_mgr) and _mgr.bird != null and is_instance_valid(_mgr.bird):
		return _mgr.bird
	return null

func _state() -> String:
	var b := _bird()
	if b == null:
		return "-"
	var beh: RefCounted = b.get("_behavior")
	return beh.state_name() if beh != null and beh.has_method("state_name") else "?"

func _tick() -> void:
	frame += 1
	# RECORDING-ONLY: keep the hero alive (a death would reload the run).
	if p.hp < 50:
		p.heal(60)
	var target := p.global_position
	var b := _bird()
	if b != null:
		target = p.global_position.lerp(b.global_position, 0.35)
	focus.global_position = target
	if _beat_label != null:
		_beat_label.text = "%s [bird: %s] | beat t=%4.2fs" % [_beat, _state(), frame / FPS - _beat_started]

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	p = scene.get_node("Player")
	p.set_process(false) # no OS mouse in the recorder
	cam = scene.get_node("FollowCamera")
	focus = Node2D.new()
	scene.add_child(focus)
	cam.target = focus
	cam.follow_speed = 3.5
	await _wait(0.5)
	scene.enter_overworld()
	await _wait(1.0)

	# Staging banner (recording-only disclosures).
	var layer := CanvasLayer.new()
	layer.layer = 100
	scene.add_child(layer)
	var banner := Label.new()
	banner.text = "STAGED #478 SHOWCASE - clock scrubbed between beats, hero teleports, HP floor on, 2 disclosed punish hits - production bird/driver/stuns"
	banner.position = Vector2(8, 32)
	banner.add_theme_font_size_override("font_size", 13)
	banner.add_theme_color_override("font_color", Color(1, 1, 1))
	layer.add_child(banner)
	_beat_label = Label.new()
	_beat_label.position = Vector2(8, 56)
	_beat_label.add_theme_font_size_override("font_size", 14)
	_beat_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
	layer.add_child(_beat_label)

	_mgr = scene.current_area.get_node_or_null("OverworldBird") as OverworldBird
	if _mgr == null:
		say("NO OverworldBird FOUND - aborting")
		quit(1)
		return
	_clock = DayNightClock.ensure(self)
	_clock.time_of_day = 0.35 # morning (recorder staging)

	# --- Beat 1: circling, off screen, shadow on the ground ----------------
	_set_beat("beat1: day - the bird circles off screen; its shadow orbits the hero")
	await _wait(2.0)

	# --- Beat 2: telegraph -> dive -> hero stun + landing stun -------------
	_set_beat("beat2: telegraph ring locks ON the hero -> dive -> hero stunned 0.5s, bird grounded 1s")
	var dove := false
	for i in int(8.0 * FPS):
		await physics_frame
		_tick()
		if _state() == "STUNNED":
			dove = true
			break
	say("dive completed: %s" % dove)
	await _wait(0.6)

	# --- Beat 3: punish window - hits extend the landing stun to 4s -------
	_set_beat("beat3: hits during the landing stun extend it to 4s (synthetic hits, disclosed) - the kill window")
	var b := _bird()
	if b != null and _state() == "STUNNED":
		b.apply_damage(8) # RECORDING-ONLY disclosed punish hit 1
		await _wait(1.0)
		if is_instance_valid(b):
			b.apply_damage(8) # RECORDING-ONLY disclosed punish hit 2
		await _wait(2.2)

	# --- Beat 4: takeoff -> re-dive on the 3-10s draw ----------------------
	_set_beat("beat4: takeoff - the next dive comes on its random 3-10s draw")
	for i in int(12.0 * FPS):
		await physics_frame
		_tick()
		if _state() == "STUNNED":
			break
	await _wait(1.2)

	# --- Beat 5: nightfall - the bird leaves (day only) --------------------
	_set_beat("beat5: nightfall - the bird flies off and despawns (day only)")
	_clock.time_of_day = 0.8 # night (recorder staging)
	await _wait(3.2)
	say("bird alive at end: %s" % (_mgr.alive() if is_instance_valid(_mgr) else "?"))
	say("done")
	quit()
