extends SceneTree
## #244 HP bar sheet -> assets/sprites/hp_bar_{frame,track,fill}.png.
## Runs on Godot's Image class, so it needs no Python imaging packages:
##   godot --headless --path . --script res://tools/sprites/pack_hp_bar.gd -- SHEET.webp assets/sprites
## Rects are measured sheet pixels. Everything is composited at sheet scale,
## then box-downsampled 3:1 with a hard alpha cut.

const SCALE := 3
const CANVAS_H := 180
const OPAQUE_MIN := 128
const FILL_H := 72
const FILL_PAD := 90 # sheet px of transparent padding: the fill starts inside the frame's end ornaments.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("usage: -- SHEET.webp OUT_DIR")
		quit(2)
		return
	var board := Image.load_from_file(args[0])
	board.convert(Image.FORMAT_RGBA8)
	_save(_frame(board), args[1], "hp_bar_frame.png")
	_save(_track(board), args[1], "hp_bar_track.png")
	var fill := _fill(board)
	_to_value(fill)
	_save(fill, args[1], "hp_bar_fill.png")
	quit()

## Cap crops stop short of each part's drawn end outline, which would show as seams.
func _frame(board: Image) -> Image:
	var c := _canvas(135 + 30 + 135)
	_put(c, board, Rect2i(198, 92, 135, CANVAS_H), Vector2i(0, 0))
	# The sheet's middle top rail sits 7 px below the caps' rail: move it up to meet them.
	_put(c, board, Rect2i(600, 128, 30, 32), Vector2i(135, 121 - 92))
	_put(c, board, Rect2i(600, 221, 30, 32), Vector2i(135, 221 - 92))
	_put(c, board, Rect2i(950, 92, 135, CANVAS_H), Vector2i(165, 0))
	return c

func _track(board: Image) -> Image:
	var c := _canvas(126 + 201 + 126)
	var y := 33 # centres the 123 px track on the frame's rails
	_put(c, board, Rect2i(199, 306, 126, 123), Vector2i(0, y))
	_put(c, board, Rect2i(539, 306, 201, 123), Vector2i(126, y)) # two star periods
	_put(c, board, Rect2i(956, 306, 126, 123), Vector2i(327, y))
	return c

func _fill(board: Image) -> Image:
	var c := _canvas(FILL_PAD + 42 + 207 + 42 + FILL_PAD)
	var y := 59 # the sheet's fill is taller than the frame opening: squeezed to fit
	_put(c, _squeezed(board, Rect2i(209, 485, 42, 105)), Rect2i(0, 0, 42, FILL_H), Vector2i(FILL_PAD, y))
	_put(c, _squeezed(board, Rect2i(450, 485, 207, 105)), Rect2i(0, 0, 207, FILL_H), Vector2i(FILL_PAD + 42, y)) # two stripe periods
	_put(c, _squeezed(board, Rect2i(1022, 485, 42, 105)), Rect2i(0, 0, 42, FILL_H), Vector2i(FILL_PAD + 249, y))
	return c

func _canvas(w: int) -> Image:
	return Image.create_empty(w, CANVAS_H, false, Image.FORMAT_RGBA8)

func _put(canvas: Image, src: Image, rect: Rect2i, at: Vector2i) -> void:
	canvas.blit_rect(src, rect, at)

func _squeezed(board: Image, rect: Rect2i) -> Image:
	var part := board.get_region(rect)
	part.resize(rect.size.x, FILL_H, Image.INTERPOLATE_NEAREST)
	return part

## Stores brightness only: HUD tints it, so one texture serves green, amber and red.
func _to_value(img: Image) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var v := maxf(c.r, maxf(c.g, c.b))
			img.set_pixel(x, y, Color(v, v, v, c.a))

func _save(canvas: Image, dir: String, file: String) -> void:
	var out := _downsample(canvas)
	var path := dir.path_join(file)
	var err := out.save_png(path)
	print("%s %dx%d err=%d" % [path, out.get_width(), out.get_height(), err])

func _downsample(src: Image) -> Image:
	var w := src.get_width() / SCALE
	var h := src.get_height() / SCALE
	var out := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var sum := Color(0, 0, 0, 0)
			var n := 0
			for j in SCALE:
				for i in SCALE:
					var c := src.get_pixel(x * SCALE + i, y * SCALE + j)
					if c.a8 >= OPAQUE_MIN:
						sum += Color(c.r, c.g, c.b, 0)
						n += 1
			if n * 2 > SCALE * SCALE:
				out.set_pixel(x, y, Color(sum.r / n, sum.g / n, sum.b / n, 1.0))
	return out
