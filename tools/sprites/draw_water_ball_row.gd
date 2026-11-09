extends SceneTree
## #331 Water Ball: code-drawn projectile art for the shared spell sheet.
## Draws sheet row 17 of assets/sprites/spell_upgrades.png (6 cells of 64x72):
## a blue water droplet pointing +X (same facing as every other row) with a
## tapering tail, dark rim and a white glint. Cols 0-2 emerge at 50/75/100%
## size (the one-shot `water_ball_start`), cols 3-5 are the wobbling flight
## loop (`water_ball`, played 3, 4, 5, 4). Re-running is idempotent: the sheet
## grows to 18 rows once, later runs only redraw row 17.
## Run: godot --headless --path . -s tools/sprites/draw_water_ball_row.gd
## then: godot --headless --path . --import

const SHEET := "res://assets/sprites/spell_upgrades.png"
const CELL_W := 64
const CELL_H := 72
const COLS := 6
const ROW := 17

const RIM := Color(0.07, 0.24, 0.62)
const BODY := Color(0.16, 0.5, 0.93)
const LIGHT := Color(0.45, 0.78, 1.0)
const GLINT := Color(0.92, 0.98, 1.0)
const TAIL := Color(0.3, 0.66, 1.0)

func _initialize() -> void:
	var src := Image.load_from_file(ProjectSettings.globalize_path(SHEET))
	if src == null:
		push_error("cannot read %s" % SHEET)
		quit(1)
		return
	src.convert(Image.FORMAT_RGBA8)
	var rows := maxi(src.get_height() / CELL_H, ROW + 1)
	var out := Image.create(COLS * CELL_W, rows * CELL_H, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var keep := mini(src.get_height(), ROW * CELL_H)
	out.blit_rect(src, Rect2i(0, 0, src.get_width(), keep), Vector2i.ZERO)
	# scale, vertical squash, tail length factor per column.
	var cells := [
		[0.5, 1.0, 0.4], [0.75, 1.0, 0.7], [1.0, 1.0, 1.0],
		[1.0, 1.0, 1.0], [1.0, 0.9, 1.15], [1.0, 1.08, 0.9],
	]
	for col in COLS:
		_draw_drop(out, Vector2i(col * CELL_W, ROW * CELL_H), cells[col][0], cells[col][1], cells[col][2])
	var err := out.save_png(ProjectSettings.globalize_path(SHEET))
	print("water_ball row %d drawn, sheet %dx%d, save err %d" % [ROW, out.get_width(), out.get_height(), err])
	quit(0 if err == OK else 1)

func _draw_drop(img: Image, origin: Vector2i, s: float, squash: float, tail_k: float) -> void:
	# The projectile shifts its sprite 12 px left (Projectile.SPRITE_HEAD_OFFSET),
	# so the ball centre sits 12 px right of the cell centre.
	var c := Vector2(44.0, 36.0)
	var r := 13.0 * s
	var tail_len := 26.0 * s * tail_k
	for y in CELL_H:
		for x in CELL_W:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := p - c
			var dn := Vector2(d.x, d.y / squash)
			var dist := dn.length()
			var col := Color(0, 0, 0, 0)
			if dist <= r:
				var edge := r - dist
				col = BODY
				if edge < 2.0:
					col = RIM
				elif dn.x > r * 0.15 and dn.y > -r * 0.2:
					col = BODY.darkened(0.12)
				var g := dn - Vector2(-r * 0.3, -r * 0.38)
				if g.length() <= r * 0.42:
					col = LIGHT
				if g.length() <= r * 0.2:
					col = GLINT
			elif d.x < 0.0 and d.x > -tail_len - r * 0.2 and tail_len > 0.0:
				# Tapering tail behind the ball.
				var t := clampf((d.x + tail_len + r * 0.2) / (tail_len + r * 0.2), 0.0, 1.0)
				var w := r * 0.85 * pow(t, 1.4) * squash
				if absf(d.y) <= w:
					col = TAIL if absf(d.y) < w - 1.5 else RIM.lightened(0.15)
					col.a = 0.85
			if col.a > 0.0:
				img.set_pixel(origin.x + x, origin.y + y, col)
