extends SceneTree
## #474: original code-drawn wolf cave decor sprite (no external art).
## Writes assets/sprites/wolf_cave.png: one 64x64 sprite, a rocky mound
## with a dark den opening facing down-right. Caves are decor only
## (Daniel: "Decor" - not enterable), drawn under characters.
## Run: godot --headless --path . -s tools/sprites/draw_wolf_cave.gd
## then: godot --headless --path . --import

const CELL := 64
const OUT := "res://assets/sprites/wolf_cave.png"

const ROCK := Color(0.38, 0.36, 0.34)
const ROCK_DARK := Color(0.24, 0.23, 0.22)
const ROCK_LIGHT := Color(0.52, 0.50, 0.46)
const RIM := Color(0.14, 0.13, 0.12)
const MOUTH := Color(0.05, 0.04, 0.06)
const MOSS := Color(0.22, 0.30, 0.18)

func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and x < CELL and y >= 0 and y < CELL:
		img.set_pixel(x, y, c)

func _ellipse(img: Image, cx: float, cy: float, w: float, h: float, c: Color) -> void:
	for y in range(int(cy - h / 2.0 - 1.0), int(cy + h / 2.0 + 2.0)):
		for x in range(int(cx - w / 2.0 - 1.0), int(cx + w / 2.0 + 2.0)):
			var dx := (x + 0.5 - cx) / (w / 2.0)
			var dy := (y + 0.5 - cy) / (h / 2.0)
			if dx * dx + dy * dy <= 1.0:
				_px(img, x, y, c)

func _rim_ellipse(img: Image, cx: float, cy: float, w: float, h: float, c: Color) -> void:
	for y in range(int(cy - h / 2.0 - 1.0), int(cy + h / 2.0 + 2.0)):
		for x in range(int(cx - w / 2.0 - 1.0), int(cx + w / 2.0 + 2.0)):
			var dx := (x + 0.5 - cx) / (w / 2.0)
			var dy := (y + 0.5 - cy) / (h / 2.0)
			var d := dx * dx + dy * dy
			if d <= 1.0 and d > 0.60 and img.get_pixel(x, y).a > 0.0:
				img.set_pixel(x, y, c)

func _initialize() -> void:
	var img := Image.create(CELL, CELL, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# Ground shadow.
	_ellipse(img, 33, 50, 52, 14, Color(0.0, 0.0, 0.0, 0.30))
	# Stacked rocks: big base mound, two shoulder rocks, cap stone.
	_ellipse(img, 32, 38, 46, 30, ROCK)
	_ellipse(img, 14, 44, 20, 16, ROCK_DARK)
	_ellipse(img, 50, 43, 18, 15, ROCK_DARK)
	_ellipse(img, 30, 24, 26, 16, ROCK)
	# Highlights on the lit (upper-left) faces.
	_ellipse(img, 24, 30, 18, 10, ROCK_LIGHT)
	_ellipse(img, 20, 40, 8, 5, ROCK_LIGHT)
	# Mossy patches.
	_ellipse(img, 40, 22, 8, 4, MOSS)
	_ellipse(img, 12, 38, 6, 3, MOSS)
	# Rims on the mound.
	_rim_ellipse(img, 32, 38, 46, 30, RIM)
	_rim_ellipse(img, 30, 24, 26, 16, RIM)
	# Den opening: dark oval low on the front face, rimmed by a lip stone.
	_ellipse(img, 36, 46, 20, 14, RIM)
	_ellipse(img, 36, 47, 15, 10, MOUTH)
	# A couple of scattered pebbles.
	_ellipse(img, 8, 52, 5, 4, ROCK_DARK)
	_ellipse(img, 56, 52, 4, 3, ROCK)
	img.save_png(OUT)
	print("wrote ", OUT)
	quit(0)
