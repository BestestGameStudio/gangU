extends SceneTree
## #392: original code-drawn Slime sprite sheet (no external art).
## Writes assets/sprites/slime.png: 32x32 cells, art faces RIGHT, feet on y=28.
## Rows (cells): 0 idle x4, 1 walk x6, 2 hurt x2, 3 attack x3, 4 death x5.
## Run: godot --headless --path . -s tools/sprites/draw_slime.gd
## then: godot --headless --path . --import
## then: godot --headless --path . -s tools/sprites/build_slime_frames.gd

const CELL := 32
const BASE := 28
const COLS := 6
const ROWS := 5
const OUT := "res://assets/sprites/slime.png"

const RIM := Color(0.10, 0.36, 0.16)
const BODY := Color(0.30, 0.78, 0.34)
const LIGHT := Color(0.60, 0.95, 0.55)
const SHADE := Color(0.20, 0.60, 0.26)
const EYE := Color(0.06, 0.12, 0.08)
const WHITE := Color(1, 1, 1)
const HURT_BODY := Color(0.95, 1.0, 0.90)

## One frame: blob of width w, height h, lifted by `lift` px, leaning by
## `lean` px toward +x (facing right), optional hurt flash / eye state.
func _frame(img: Image, col: int, row: int, w: float, h: float, lift: float, lean: float, hurt: bool = false, eyes: bool = true, fade: float = 1.0) -> void:
	var ox := col * CELL
	var oy := row * CELL
	var cx := CELL / 2.0
	var cy := BASE - lift - h / 2.0
	for y in CELL:
		for x in CELL:
			var dy := (y + 0.5 - cy) / (h / 2.0)
			# the blob leans: top shifts toward +x, base stays planted
			var shift := lean * clampf(-dy, -1.0, 1.0) * 0.5 + lean * 0.5
			var dx := (x + 0.5 - cx - shift) / (w / 2.0)
			# flat-bottomed dome: squash the lower half so it sits on the ground
			var d := dx * dx + dy * dy
			if dy > 0.0:
				d = dx * dx + dy * dy * 1.6
			if d > 1.0:
				continue
			var c := BODY
			if hurt:
				c = HURT_BODY
			elif d > 0.72:
				c = RIM
			elif dy > 0.35:
				c = SHADE
			elif dx < -0.1 and dy < -0.2 and d < 0.55:
				c = LIGHT
			if d > 0.80 and not hurt:
				c = RIM
			c.a = fade
			img.set_pixel(ox + x, oy + y, c)
	if eyes and h > 7.0:
		var ey := int(round(cy - h * 0.12))
		var ex := int(round(cx + lean * 0.8 + w * 0.12))
		for dxe in [-3, 3]:
			for dye in [0, 1]:
				img.set_pixel(ox + ex + dxe, oy + ey + dye, EYE)
		img.set_pixel(ox + ex - 3, oy + ey - 1, WHITE)
		img.set_pixel(ox + ex + 3, oy + ey - 1, WHITE)
	elif eyes == false and h > 4.0:
		pass

func _initialize() -> void:
	var img := Image.create(CELL * COLS, CELL * ROWS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var idle := [[22, 15], [21, 16], [20, 17], [21, 16]]
	for i in 4:
		_frame(img, i, 0, idle[i][0], idle[i][1], 0, 0)
	var walk := [[22, 14, 0, 0], [20, 17, 3, 1], [19, 18, 5, 1.5], [20, 17, 3, 1], [22, 14, 0, 0], [24, 12, 0, -1]]
	for i in 6:
		_frame(img, i, 1, walk[i][0], walk[i][1], walk[i][2], walk[i][3])
	_frame(img, 0, 2, 25, 12, 0, -2, true)
	_frame(img, 1, 2, 23, 14, 0, -1, true)
	_frame(img, 0, 3, 24, 12, 0, 0)
	_frame(img, 1, 3, 18, 20, 4, 4)
	_frame(img, 2, 3, 26, 11, 0, 2)
	var death := [[24, 12, 0.0, 1.0], [26, 9, 0.0, 1.0], [27, 6, 0.0, 0.9], [27, 4, 0.0, 0.6], [26, 3, 0.0, 0.3]]
	for i in 5:
		_frame(img, i, 4, death[i][0], death[i][1], death[i][2], 0, false, i < 2, death[i][3])
	img.save_png(ProjectSettings.globalize_path(OUT))
	print("wrote ", OUT)
	quit(0)
