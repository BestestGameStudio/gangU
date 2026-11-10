extends SceneTree
## #478: builds resources/sprites/bird_frames.tres from assets/sprites/bird.png
## (drawn by draw_bird.gd). Run after `godot --headless --path . --import`.

const CELL := 32
const SHEET := "res://assets/sprites/bird.png"
const OUT := "res://resources/sprites/bird_frames.tres"

func _initialize() -> void:
	var tex: Texture2D = load(SHEET)
	var sf := SpriteFrames.new()
	sf.remove_animation(&"default")
	# name, row, frame count, fps, loop
	var rows := [[&"idle", 0, 4, 5.0, true], [&"walk", 1, 6, 12.0, true], [&"hurt", 2, 2, 12.0, false],
		[&"attack", 3, 3, 14.0, false], [&"death", 4, 5, 9.0, false]]
	for r in rows:
		sf.add_animation(r[0])
		sf.set_animation_speed(r[0], r[3])
		sf.set_animation_loop(r[0], r[4])
		for i in r[2]:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(i * CELL, r[1] * CELL, CELL, CELL)
			sf.add_frame(r[0], at)
	# #478 dive split: the stoop (attack frames 0-1) plays during the dive;
	# the landing flare (frame 2) holds while the bird is stunned.
	for spec in [[&"dive", [0, 1], false], [&"landed", [2], true]]:
		sf.add_animation(spec[0])
		sf.set_animation_speed(spec[0], 14.0)
		sf.set_animation_loop(spec[0], spec[2])
		for i in spec[1]:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(i * CELL, 3 * CELL, CELL, CELL)
			sf.add_frame(spec[0], at)
	var err := ResourceSaver.save(sf, OUT)
	print("saved ", OUT, " err=", err)
	quit(err)
