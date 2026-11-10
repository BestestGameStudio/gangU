extends SceneTree
## RECORDING-ONLY showcase driver for #474 (not a test, not loaded by the
## game). Boots main.tscn, jumps into the overworld and stages the branch
## behavior with PRODUCTION scenes/scripts:
##   beat1 day:   the wolf den by daylight - quiet, decor only.
##   beat2 night: night falls, the cave spawns its pack of 6; the pack
##                prowls, then hunts the hero together (pack alert).
##   beat3 pounce: a wolf crouches (0.5s telegraph), lunges, heavy damage.
##   beat4 dawn:  daybreak mid-fight - engaged wolves fight on; once the
##                hero leaves, the pack retreats into the cave and despawns.
## The recorder only teleports the hero, holds an HP floor, and scrubs the
## DayNightClock between beats (all disclosed on the banner); wolves, the
## cave and the clock run untouched production code.
## Usage:
##   xvfb-run -a godot --path . --write-movie out.avi --fixed-fps 60 \
##         --rendering-driver opengl3 --script res://tools/showcase/record474_wolves.gd

const FPS := 60.0

var scene: Node
var p: Player
var cam: Camera2D
var focus: Node2D
var frame := 0
var _beat_label: Label
var _beat := "setup"
var _beat_started := 0.0
var _cave: WolfCave

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

func _tick() -> void:
	frame += 1
	# RECORDING-ONLY: keep the hero alive (a death would reload the run).
	if p.hp < 50:
		p.heal(60)
	var target := p.global_position
	if _cave != null and is_instance_valid(_cave):
		target = p.global_position.lerp(_cave.global_position, 0.25)
	focus.global_position = target
	if _beat_label != null:
		_beat_label.text = "%s | beat t=%4.2fs" % [_beat, frame / FPS - _beat_started]

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
	banner.text = "STAGED #474 SHOWCASE - clock scrubbed between beats, hero teleports, HP floor on - production wolves/caves"
	banner.position = Vector2(8, 32)
	banner.add_theme_font_size_override("font_size", 13)
	banner.add_theme_color_override("font_color", Color(1, 1, 1))
	layer.add_child(banner)
	_beat_label = Label.new()
	_beat_label.position = Vector2(8, 56)
	_beat_label.add_theme_font_size_override("font_size", 14)
	_beat_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
	layer.add_child(_beat_label)

	# Pick the first production cave.
	var caves: Array = scene.current_area.find_children("WolfCave*", "WolfCave", true, false)
	if caves.is_empty():
		say("NO CAVE FOUND - aborting")
		quit(1)
		return
	_cave = caves[0]
	var clock := DayNightClock.ensure(self)
	clock.time_of_day = 0.55 # afternoon

	# --- Beat 1: the den by day ------------------------------------------
	_set_beat("beat1: daylight - the den is quiet (decor, cannot be entered)")
	_hop(_cave.global_position + Vector2(180, 120), "hero walks up to the den")
	await _wait(3.0)

	# --- Beat 2: nightfall - the pack spawns and hunts --------------------
	_set_beat("beat2: night falls - the cave spawns its pack of 6; the pack hunts together")
	clock.time_of_day = 0.76 # nightfall (recorder staging)
	await _wait(1.5)
	_hop(_cave.global_position + Vector2(420, 160), "hero steps into the pack's hunt range")
	await _wait(4.0)

	# --- Beat 3: telegraphed pounce ---------------------------------------
	_set_beat("beat3: 0.5s crouch telegraph -> pounce -> HEAVY damage")
	await _wait(5.0)

	# --- Beat 4: daybreak mid-fight, then retreat --------------------------
	_set_beat("beat4: daybreak mid-fight - engaged wolves fight back, no retreat")
	clock.time_of_day = 0.4 # daybreak (recorder staging)
	await _wait(4.0)
	_set_beat("beat4b: the fight ends - the pack retreats into the cave and despawns")
	_hop(_cave.global_position + Vector2(1500, 700), "hero leaves far away")
	focus.global_position = _cave.global_position # keep the camera on the den
	for i in int(6.0 * FPS):
		await physics_frame
		frame += 1
		focus.global_position = focus.global_position.lerp(_cave.global_position, 0.05)
		if _beat_label != null:
			_beat_label.text = "%s | beat t=%4.2fs" % [_beat, frame / FPS - _beat_started]
	say("pack alive at end: %d" % (_cave.alive_count() if is_instance_valid(_cave) else -1))
	say("done")
	quit()
