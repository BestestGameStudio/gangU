extends SceneTree
## #392: builds resources/sprites/slime_frames.tres from assets/sprites/slime.png
## (drawn by draw_slime.gd). Run after `godot --headless --path . --import`.

const CELL := 32
const SHEET := "res://assets/sprites/slime.png"
const OUT := "res://resources/sprites/slime_frames.tres"

func _initialize() -> void:
	var tex: Texture2D = load(SHEET)
	var sf := SpriteFrames.new()
	sf.remove_animation(&"default")
	# name, row, frame count, fps, loop
	var rows := [[&"idle", 0, 4, 5.0, true], [&"walk", 1, 6, 10.0, true], [&"hurt", 2, 2, 12.0, false],
		[&"attack", 3, 3, 12.0, false], [&"death", 4, 5, 9.0, false]]
	for r in rows:
		sf.add_animation(r[0])
		sf.set_animation_speed(r[0], r[3])
		sf.set_animation_loop(r[0], r[4])
		for i in r[2]:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(i * CELL, r[1] * CELL, CELL, CELL)
			sf.add_frame(r[0], at)
	var err := ResourceSaver.save(sf, OUT)
	print("saved ", OUT, " err=", err)
	quit(err)
