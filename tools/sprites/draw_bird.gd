extends SceneTree
## #478: original code-drawn Bird sprite sheet (no external art, no traced
## or generated images). Writes assets/sprites/bird.png: 32x32 cells, art
## faces RIGHT, feet on y=28 (same cell idiom as tools/sprites/draw_wolf.gd).
## Rows (cells): 0 idle x4 (perched, breathing), 1 walk x6 (flight flap
## cycle - "walk" is the locomotion row the EnemySprite driver picks from
## velocity), 2 hurt x2, 3 attack x3 (dive tuck, stoop, landing flare),
## 4 death x5.
## Run: godot --headless --path . -s tools/sprites/draw_bird.gd
## then: godot --headless --path . --import
## then: godot --headless --path . -s tools/sprites/build_bird_frames.gd

const CELL := 32
const BASE := 28
const OUT := "res://assets/sprites/bird.png"

const RIM := Color(0.09, 0.10, 0.15)
const BODY := Color(0.21, 0.24, 0.36)   # slate blue-black
const LIGHT := Color(0.39, 0.43, 0.58)  # wing highlight
const SHADE := Color(0.14, 0.16, 0.25)
const BELLY := Color(0.58, 0.60, 0.70)
const BEAK := Color(0.94, 0.62, 0.18)
const FEET := Color(0.85, 0.52, 0.14)
const EYE := Color(0.96, 0.90, 0.60)
const PUPIL := Color(0.06, 0.06, 0.08)
const HURT_BODY := Color(0.97, 0.95, 0.93)

func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
		img.set_pixel(x, y, c)

func _ellipse(img: Image, cx: float, cy: float, w: float, h: float, c: Color) -> void:
	var x0 := int(floor(cx - w / 2.0 - 1.0))
	var x1 := int(ceil(cx + w / 2.0 + 1.0))
	var y0 := int(floor(cy - h / 2.0 - 1.0))
	var y1 := int(ceil(cy + h / 2.0 + 1.0))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx := (x + 0.5 - cx) / (w / 2.0)
			var dy := (y + 0.5 - cy) / (h / 2.0)
			if dx * dx + dy * dy <= 1.0:
				_px(img, x, y, c)

## One-pixel rim on the outer band of an ellipse (only over drawn pixels).
func _rim_ellipse(img: Image, cx: float, cy: float, w: float, h: float, c: Color) -> void:
	var x0 := int(floor(cx - w / 2.0 - 1.0))
	var x1 := int(ceil(cx + w / 2.0 + 1.0))
	var y0 := int(floor(cy - h / 2.0 - 1.0))
	var y1 := int(ceil(cy + h / 2.0 + 1.0))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx := (x + 0.5 - cx) / (w / 2.0)
			var dy := (y + 0.5 - cy) / (h / 2.0)
			var d := dx * dx + dy * dy
			if d > 1.0:
				continue
			if d > 0.66 and img.get_pixel(x, y).a > 0.0:
				img.set_pixel(x, y, c)

func _rect(img: Image, x0: int, y0: int, w: int, h: int, c: Color) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			_px(img, x, y, c)

## Filled triangle: apex (ax,ay), base from (bx0,by) to (bx1,by).
func _tri(img: Image, ax: float, ay: float, bx0: float, bx1: float, by: float, c: Color) -> void:
	var y0 := int(minf(ay, by))
	var y1 := int(maxf(ay, by))
	for y in range(y0, y1 + 1):
		var t := 0.0 if is_equal_approx(by, ay) else (y + 0.5 - ay) / (by - ay)
		t = clampf(t, 0.0, 1.0)
		var lx := lerpf(ax, bx0, t)
		var rx := lerpf(ax, bx1, t)
		for x in range(int(floor(minf(lx, rx))), int(ceil(maxf(lx, rx))) + 1):
			_px(img, x, y, c)

func _cell(img: Image, col: int, row: int) -> Vector2i:
	return Vector2i(col * CELL, row * CELL)

## --- pose pieces (all art faces RIGHT, cx/cy relative to cell origin) ---

## Perched/grounded body: side profile, folded wing, tail back-left.
func _body_perched(img: Image, o: Vector2i, bob: float, main: Color, light: Color) -> void:
	var cx: float = o.x + 15.0
	var cy: float = o.y + 21.0 + bob
	# tail: two stacked triangles sweeping left
	_tri(img, cx - 4, cy - 3, cx - 13, cx - 13, cy + 3, SHADE)
	_tri(img, cx - 4, cy - 1, cx - 12, cx - 12, cy + 5, RIM)
	# body
	_ellipse(img, cx, cy, 13.0, 9.0, main)
	_rim_ellipse(img, cx, cy, 13.0, 9.0, RIM)
	# belly
	_ellipse(img, cx + 1.5, cy + 2.5, 8.0, 4.5, BELLY)
	# folded wing
	_ellipse(img, cx - 1.0, cy - 0.5, 9.0, 5.5, light)
	_rim_ellipse(img, cx - 1.0, cy - 0.5, 9.0, 5.5, RIM)
	_tri(img, cx - 2, cy + 1, cx - 9, cx - 9, cy + 5, light)
	# head
	_ellipse(img, cx + 7.0, cy - 6.5 + bob * 0.5, 6.5, 6.0, main)
	_rim_ellipse(img, cx + 7.0, cy - 6.5 + bob * 0.5, 6.5, 6.0, RIM)
	# beak
	_tri(img, cx + 13.5, cy - 6.0 + bob * 0.5, cx + 9.5, cx + 9.5, cy - 3.5 + bob * 0.5, BEAK)
	# eye
	_px(img, int(cx + 8), int(cy - 7.5 + bob * 0.5), EYE)
	_px(img, int(cx + 8.6), int(cy - 7.2 + bob * 0.5), PUPIL)

## Feet down to BASE.
func _feet(img: Image, o: Vector2i, spread: float) -> void:
	var y := o.y + BASE - 3
	_rect(img, o.x + 12, y, 2, 3, FEET)
	_rect(img, o.x + 17, y, 2, 3, FEET)
	_rect(img, o.x + 11 - int(spread), y + 3, 4, 1, FEET)
	_rect(img, o.x + 16 + int(spread), y + 3, 4, 1, FEET)

## Flying body: streamlined, wings posed by `flap` in [-1, 1]
## (-1 wings high, +1 wings low).
func _body_flying(img: Image, o: Vector2i, flap: float, main: Color, light: Color) -> void:
	var cx: float = o.x + 15.0
	var cy: float = o.y + 16.0
	# tail
	_tri(img, cx - 5, cy - 1, cx - 14, cx - 14, cy + 3, SHADE)
	# far wing (behind body): shorter, darker
	var fwy := cy - 4 - flap * 7.0
	_tri(img, cx - 1, cy - 1, cx - 6, cx + 4, fwy, SHADE)
	# body
	_ellipse(img, cx, cy, 13.0, 7.0, main)
	_rim_ellipse(img, cx, cy, 13.0, 7.0, RIM)
	_ellipse(img, cx + 1.0, cy + 2.0, 8.0, 3.5, BELLY)
	# head
	_ellipse(img, cx + 7.5, cy - 3.0, 6.0, 5.5, main)
	_rim_ellipse(img, cx + 7.5, cy - 3.0, 6.0, 5.5, RIM)
	_tri(img, cx + 14.0, cy - 2.5, cx + 10.0, cx + 10.0, cy - 0.5, BEAK)
	_px(img, int(cx + 8.5), int(cy - 4.2), EYE)
	_px(img, int(cx + 9.1), int(cy - 3.9), PUPIL)
	# near wing: big triangle whose tip sweeps with the flap
	var tip_y := cy - 3 - flap * 9.0
	_tri(img, cx + 1, cy - 2, cx - 8, cx + 3, tip_y, light)
	_rim_edge(img, o)

## Dive pose: wings swept back, body angled into the stoop.
func _body_dive(img: Image, o: Vector2i, phase: int, main: Color, light: Color) -> void:
	var cx: float = o.x + 15.0
	var cy: float = o.y + 15.0
	match phase:
		0: # tuck: wings half-swept, body compact
			_tri(img, cx - 4, cy - 2, cx - 13, cx - 13, cy + 2, SHADE)
			_ellipse(img, cx, cy, 11.0, 8.0, main)
			_rim_ellipse(img, cx, cy, 11.0, 8.0, RIM)
			_tri(img, cx - 1, cy - 2, cx - 8, cx + 2, cy - 8, light)
			_head(img, cx + 6.5, cy - 3.0, main)
		1: # stoop: fully streamlined bullet, wings tight to body
			_tri(img, cx - 5, cy - 1, cx - 15, cx - 15, cy + 2, SHADE)
			_ellipse(img, cx + 1, cy, 14.0, 6.0, main)
			_rim_ellipse(img, cx + 1, cy, 14.0, 6.0, RIM)
			_ellipse(img, cx, cy - 1.5, 9.0, 3.0, light)
			_head(img, cx + 8.0, cy - 1.0, main)
		2: # landing flare: wings spread wide, talons thrown forward
			_tri(img, cx - 4, cy, cx - 15, cx - 15, cy + 3, SHADE)
			_ellipse(img, cx, cy, 11.0, 8.5, main)
			_rim_ellipse(img, cx, cy, 11.0, 8.5, RIM)
			_ellipse(img, cx + 1, cy + 2.5, 7.0, 4.0, BELLY)
			_tri(img, cx - 2, cy - 2, cx - 13, cx - 5, cy - 10, light) # wing up-back
			_tri(img, cx + 1, cy - 1, cx - 3, cx + 9, cy - 12, light) # wing up-front
			_head(img, cx + 6.0, cy - 4.0, main)
			_rect(img, int(cx + 7), int(cy + 4), 5, 2, FEET) # talons
			_rect(img, int(cx + 9), int(cy + 6), 4, 1, FEET)

func _head(img: Image, hx: float, hy: float, main: Color) -> void:
	_ellipse(img, hx, hy, 6.0, 5.5, main)
	_rim_ellipse(img, hx, hy, 6.0, 5.5, RIM)
	_tri(img, hx + 6.5, hy + 0.5, hx + 2.5, hx + 2.5, hy + 2.0, BEAK)
	_px(img, int(hx + 1.5), int(hy - 1.2), EYE)
	_px(img, int(hx + 2.1), int(hy - 0.9), PUPIL)

func _rim_edge(_img: Image, _o: Vector2i) -> void:
	pass

func _initialize() -> void:
	var img := Image.create(CELL * 6, CELL * 5, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# idle x4: perched, gentle breathing bob
	for i in 4:
		var o := _cell(img, i, 0)
		var bob := sin(TAU * i / 4.0) * 0.7
		_body_perched(img, o, bob, BODY, LIGHT)
		_feet(img, o, 0.0)
	# walk x6: flight flap cycle (wings high -> low -> high)
	var flaps := [-1.0, -0.4, 0.3, 1.0, 0.3, -0.4]
	for i in 6:
		var o := _cell(img, i, 1)
		_body_flying(img, o, flaps[i], BODY, LIGHT)
	# hurt x2: flashed white, wings askew
	for i in 2:
		var o := _cell(img, i, 2)
		_body_perched(img, o, -1.0 + i * 1.5, HURT_BODY, HURT_BODY)
		_feet(img, o, 1.0)
	# attack x3: dive tuck, stoop, landing flare
	for i in 3:
		var o := _cell(img, i, 3)
		_body_dive(img, o, i, BODY, LIGHT)
	# death x5: crumple - flare, keel over, on side, still, final
	for i in 5:
		var o := _cell(img, i, 4)
		match i:
			0:
				_body_dive(img, o, 2, BODY, LIGHT)
			1:
				_body_perched(img, o, 2.0, BODY, LIGHT)
				_feet(img, o, 2.0)
			2, 3, 4:
				# on its side: low body heap, wing up, feet in the air
				var cx: float = o.x + 15.0
				var cy: float = o.y + 24.0
				_tri(img, cx - 6, cy - 2, cx - 14, cx - 14, cy + 2, SHADE)
				_ellipse(img, cx, cy, 12.0, 6.0 - i * 0.4, BODY if i < 4 else SHADE)
				_rim_ellipse(img, cx, cy, 12.0, 6.0 - i * 0.4, RIM)
				_tri(img, cx + 1, cy - 2, cx - 3, cx + 4, cy - 9 + i, LIGHT)
				_head(img, cx + 7.0, cy - 2.0 + i * 0.7, BODY)
				_rect(img, int(cx - 2), int(cy - 7 + i), 2, 3, FEET)
				_rect(img, int(cx + 2), int(cy - 8 + i), 2, 3, FEET)
	img.save_png(OUT)
	print("saved ", OUT)
	quit(0)
