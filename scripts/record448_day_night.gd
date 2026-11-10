extends SceneTree
## #448 rendered fixture: one full day/night cycle over the hub area of the
## overworld, time SCRUBBED for the demo (a full cycle is 10 minutes of
## real time). The CanvasModulate tint follows the root-parked
## DayNightClock; gate PointLight2D lights keep glowing at night. Run under
## xvfb with --write-movie; quits itself.

var _cam: Camera2D
var _label: Label
var _clock: DayNightClock
var _frames := 0
const TOTAL_FRAMES := 480 # 8s at 60fps

func _initialize() -> void:
	var area: Node2D = load("res://scenes/overworld.tscn").instantiate()
	root.add_child(area)
	current_scene = area
	_clock = DayNightClock.ensure(self)
	await process_frame
	await process_frame
	_clock.time_of_day = 0.0 # start at midnight
	_cam = Camera2D.new()
	area.add_child(_cam)
	# Frame the hub gate (576, 640) and the normal/red gates to its sides.
	_cam.position = Vector2(576, 480)
	_cam.make_current()
	var hud := CanvasLayer.new()
	area.add_child(hud)
	_label = Label.new()
	_label.position = Vector2(24, 24)
	_label.add_theme_font_size_override("font_size", 34)
	hud.add_child(_label)

func _process(_delta: float) -> bool:
	_frames += 1
	# Scrub one full cycle across the recording instead of waiting 10 min.
	_clock.time_of_day = fmod(float(_frames) / TOTAL_FRAMES, 1.0)
	var t := _clock.time_of_day
	var phase := "night"
	if t >= 0.18 and t < 0.37:
		phase = "sunrise"
	elif t >= 0.37 and t < 0.64:
		phase = "day"
	elif t >= 0.64 and t < 0.82:
		phase = "sunset"
	_label.text = "#448 day/night - time scrubbed (real cycle = 10 min)\n%s  (t=%.2f)" % [phase, t]
	if _frames >= TOTAL_FRAMES:
		quit(0)
	return false
