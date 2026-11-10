extends SceneTree
## #474: original code-drawn Wolf sprite sheet (no external art, no traced
## or generated images). Writes assets/sprites/wolf.png: 32x32 cells, art
## faces RIGHT, feet on y=28 (same cell idiom as tools/sprites/draw_slime.gd).
## Rows (cells): 0 idle x4, 1 walk x6, 2 hurt x2, 3 attack x3 (crouch
## telegraph, lunge, snap), 4 death x5.
## Run: godot --headless --path . -s tools/sprites/draw_wolf.gd
## then: godot --headless --path . --import
## then: godot --headless --path . -s tools/sprites/build_wolf_frames.gd

const CELL := 32
const BASE := 28
const OUT := "res://assets/sprites/wolf.png"

const RIM := Color(0.14, 0.15, 0.19)
const BODY := Color(0.50, 0.53, 0.61)
const LIGHT := Color(0.71, 0.74, 0.81)
const SHADE := Color(0.36, 0.38, 0.46)
const BELLY := Color(0.62, 0.64, 0.71)
const EYE := Color(0.95, 0.72, 0.22)
const NOSE := Color(0.08, 0.08, 0.10)
const HURT_BODY := Color(0.98, 0.96, 0.94)
const MOUTH := Color(0.42, 0.16, 0.16)
const FANG := Color(0.96, 0.96, 0.92)

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

func _initialize() -> void:
	var img := Image.create(CELL * 6, CELL * 5, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# idle x4: gentle breathing bob + tail wag
	for i in 4:
		_draw_cell(img, i, 0, {"bob": sin(TAU * i / 4.0) * 0.7, "tail": sin(TAU * i / 4.0 + 1.0) * 1.6})
	# walk x6: leg cycle, slight bounce
	for i in 6:
		_draw_cell(img, i, 1, {"leg_phase": i, "bob": (0.6 if i % 2 == 0 else -0.4), "tail": sin(TAU * i / 6.0) * 1.2})
	# hurt x2: flash, head knocked back
	for i in 2:
		_draw_cell(img, i, 2, {"hurt": true, "head_dx": -1.5 - i, "bob": -0.5})
	# attack x3: 0 crouch telegraph, 1 lunge stretch (mouth open), 2 snap
	_draw_cell(img, 0, 3, {"crouch": 1.0, "tail": -1.5})
	_draw_cell(img, 1, 3, {"stretch": 1.0, "open_mouth": true, "leg_phase": 4, "tail": 1.0})
	_draw_cell(img, 2, 3, {"stretch": 0.35, "open_mouth": true, "head_dx": 1.5})
	# death x5: keel over and fade
	for i in 5:
		_draw_cell(img, i, 4, {"flat": true, "fade": 1.0 - 0.18 * i, "head_dx": -1.0, "tail": -1.0})
	img.save_png(OUT)
	print("wrote ", OUT, " ", img.get_width(), "x", img.get_height())
	quit(0)

## Cell-local wolf renderer (all coordinates relative to the cell origin).
func _draw_cell(img: Image, col: int, row: int, opts: Dictionary) -> void:
	var ox := col * CELL
	var oy := row * CELL
	var crouch: float = opts.get("crouch", 0.0)
	var stretch: float = opts.get("stretch", 0.0)
	var bob: float = opts.get("bob", 0.0)
	var tail_wag: float = opts.get("tail", 0.0)
	var leg_phase: int = opts.get("leg_phase", 0)
	var open_mouth: bool = opts.get("open_mouth", false)
	var hurt: bool = opts.get("hurt", false)
	var fade: float = opts.get("fade", 1.0)
	var flat: bool = opts.get("flat", false)
	var head_dx: float = opts.get("head_dx", 0.0)

	var body_c: Color = HURT_BODY if hurt else BODY
	var light_c: Color = HURT_BODY if hurt else LIGHT
	var shade_c: Color = HURT_BODY if hurt else SHADE
	var belly_c: Color = HURT_BODY if hurt else BELLY
	body_c.a *= fade
	light_c.a *= fade
	shade_c.a *= fade
	belly_c.a *= fade
	var rim := RIM
	rim.a *= fade
	var eye := EYE
	eye.a *= fade

	# Body geometry.
	var bw := 19.0 + stretch * 6.0 - crouch * 2.0
	var bh := (9.5 if not flat else 6.0) - crouch * 2.5
	var bcx := 14.5 + stretch * 1.0
	var bcy := (19.0 if not flat else 24.0) + crouch * 2.5 + bob

	# Tail (behind body): tapered, lifts with wag.
	var tx := ox + bcx - bw / 2.0
	var ty := oy + bcy - 1.5 - tail_wag
	_tri(img, tx - 6.0, ty - 2.0 - tail_wag * 0.5, tx + 1.5, tx + 1.5, ty + 3.5, shade_c)

	# Far-side legs (darker), drawn before the body.
	var leg_top := bcy + bh * 0.2
	var leg_h := BASE - (bcy - bh / 2.0) - 3.0
	if flat:
		leg_h = 3.0
	var far_dx: float = [-1.0, 0.0, 1.0, 0.0, 3.0, -2.0][leg_phase % 6]
	for lx in [bcx - bw * 0.28, bcx + bw * 0.28]:
		var fx: float = ox + lx + far_dx * 0.6
		_rect(img, int(fx), int(oy + leg_top), 2, int(leg_h), shade_c)

	# Body: base, belly patch, back ridge, rim.
	_ellipse(img, ox + bcx, oy + bcy, bw, bh, body_c)
	_ellipse(img, ox + bcx + 0.5, oy + bcy + bh * 0.22, bw * 0.72, bh * 0.5, belly_c)
	_ellipse(img, ox + bcx - 0.5, oy + bcy - bh * 0.30, bw * 0.8, bh * 0.45, shade_c)
	_rim_ellipse(img, ox + bcx, oy + bcy, bw, bh, rim)

	# Head: ears, circle, cheek, snout, eye.
	var hx := bcx + bw / 2.0 - 1.0 + head_dx + stretch * 2.0
	var hy := bcy - 6.0 + crouch * 1.0 + (1.0 if flat else 0.0)
	_tri(img, ox + hx - 3.4, oy + hy - 7.0, ox + hx - 4.6, ox + hx - 1.6, oy + hy - 2.5, body_c)
	_tri(img, ox + hx + 0.6, oy + hy - 7.4, ox + hx - 0.6, ox + hx + 2.8, oy + hy - 2.5, body_c)
	_ellipse(img, ox + hx, oy + hy, 9.0, 8.0, body_c)
	_rim_ellipse(img, ox + hx, oy + hy, 9.0, 8.0, rim)
	_ellipse(img, ox + hx - 1.0, oy + hy + 1.2, 5.0, 3.5, light_c)
	var sn_x := ox + hx + 3.0
	var sn_y := oy + hy + 0.5
	if open_mouth:
		_rect(img, int(sn_x), int(sn_y - 1.0), 5, 2, body_c)
		_px(img, int(sn_x) + 4, int(sn_y) - 1, rim)
		_px(img, int(sn_x) + 5, int(sn_y) - 1, NOSE)
		_rect(img, int(sn_x) + 1, int(sn_y) + 1.0, 4, 2, MOUTH)
		_px(img, int(sn_x) + 1, int(sn_y) + 1, FANG)
		_rect(img, int(sn_x) + 2, int(sn_y) + 3.0, 3, 1, shade_c)
	else:
		_rect(img, int(sn_x), int(sn_y), 4, 3, body_c)
		_px(img, int(sn_x) + 3, int(sn_y), NOSE)
		_px(img, int(sn_x) + 3, int(sn_y) + 1, NOSE)
		_px(img, int(sn_x), int(sn_y) + 2, rim)
	var ex := int(ox + hx + 0.5)
	var ey := int(oy + hy - 1.5)
	_px(img, ex, ey, eye)
	if crouch > 0.5:
		_px(img, ex, ey - 1, rim) # brow pressed down

	# Near-side legs (body colour, on top) with dark paws.
	var near_dx: float = [1.0, 0.0, -1.0, 0.0, -3.0, 4.0][leg_phase % 6]
	for lx in [bcx - bw * 0.30, bcx + bw * 0.30]:
		var fx: float = ox + lx + near_dx
		_rect(img, int(fx), int(oy + leg_top), 2, int(leg_h), body_c)
		_rect(img, int(fx), int(oy + leg_top + leg_h) - 1, 2, 1, rim)
