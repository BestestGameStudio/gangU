extends SceneTree
## #474: builds resources/sprites/wolf_frames.tres from assets/sprites/wolf.png
## (drawn by draw_wolf.gd). Run after `godot --headless --path . --import`.

const CELL := 32
const SHEET := "res://assets/sprites/wolf.png"
const OUT := "res://resources/sprites/wolf_frames.tres"

func _initialize() -> void:
	var tex: Texture2D = load(SHEET)
	var sf := SpriteFrames.new()
	sf.remove_animation(&"default")
	# name, row, frame count, fps, loop
	var rows := [[&"idle", 0, 4, 5.0, true], [&"walk", 1, 6, 12.0, true], [&"hurt", 2, 2, 12.0, false],
		[&"attack", 3, 3, 10.0, false], [&"death", 4, 5, 9.0, false]]
	for r in rows:
		sf.add_animation(r[0])
		sf.set_animation_speed(r[0], r[3])
		sf.set_animation_loop(r[0], r[4])
		for i in r[2]:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(i * CELL, r[1] * CELL, CELL, CELL)
			sf.add_frame(r[0], at)
	# #474 pounce split: the 0.5s telegraph holds the crouch (attack frame 0);
	# the lunge plays the stretch + snap (frames 1-2) once.
	for spec in [[&"telegraph", [0], true], [&"pounce", [1, 2], false]]:
		sf.add_animation(spec[0])
		sf.set_animation_speed(spec[0], 12.0)
		sf.set_animation_loop(spec[0], spec[2])
		for i in spec[1]:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(i * CELL, 3 * CELL, CELL, CELL)
			sf.add_frame(spec[0], at)
	var err := ResourceSaver.save(sf, OUT)
	print("saved ", OUT, " err=", err)
	quit(err)
