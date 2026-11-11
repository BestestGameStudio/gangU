class_name StatIcon
extends Control
## #376 code-drawn stat glyph for the Tab menu stat grid (TFT-style: icon +
## value, details on hover). Code-drawn like UiStyle, so it renders the same
## under the compatibility renderer and needs no new art assets. Unknown ids
## draw a neutral dot so a new stat never shows an empty cell.

var stat_id: StringName = &""

const C_HP := Color(0.9, 0.25, 0.3)
const C_AMP := Color(0.95, 0.55, 0.2)
const C_ARMOR := Color(0.55, 0.7, 0.95)
const C_SPEED := Color(0.45, 0.9, 0.5)
const C_CDR := Color(0.4, 0.85, 0.95)
const C_CRIT := Color(1.0, 0.85, 0.25)
const C_RANGE := Color(0.85, 0.85, 0.9)
const C_COUNT := Color(0.7, 0.6, 1.0)
const C_AREA := Color(0.8, 0.6, 0.4)
const C_DIM := Color(0.7, 0.72, 0.78)

func _init(p_id: StringName = &"", p_size: float = 26.0) -> void:
	stat_id = p_id
	custom_minimum_size = Vector2(p_size, p_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE # hover goes to the cell

func set_stat(p_id: StringName) -> void:
	if p_id == stat_id:
		return
	stat_id = p_id
	queue_redraw()

func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	match stat_id:
		&"hp":
			_heart(c, s, C_HP)
		&"damage_amp":
			_sword(c, s, C_AMP)
			_plus(c + Vector2(s * 0.28, -s * 0.28), s * 0.16, C_AMP)
		&"damage":
			_sword(c, s, C_AMP)
		&"armor":
			_shield(c, s, C_ARMOR)
		&"move_speed":
			_speed(c, s, C_SPEED)
		&"cooldown_reduction":
			_hourglass(c, s, C_CDR)
		&"cooldown":
			_clock(c, s, C_CDR)
		&"crit":
			_star(c, s, C_CRIT)
		&"range":
			_target(c, s, C_RANGE)
		&"projectiles":
			for i in 3:
				draw_circle(c + Vector2((i - 1) * s * 0.3, 0.0), s * 0.12, C_COUNT)
		&"pierce":
			draw_line(c + Vector2(s * 0.1, -s * 0.38), c + Vector2(s * 0.1, s * 0.38), C_DIM, 2.0)
			_arrow(c, s, C_COUNT)
		&"area":
			draw_arc(c, s * 0.4, 0.0, TAU, 24, C_AREA, 2.0)
			draw_arc(c, s * 0.22, 0.0, TAU, 18, C_AREA, 2.0)
			draw_circle(c, s * 0.07, C_AREA)
		&"combo":
			var bolt := PackedVector2Array([
				c + Vector2(s * 0.08, -s * 0.42), c + Vector2(-s * 0.22, s * 0.04),
				c + Vector2(-s * 0.02, s * 0.04), c + Vector2(-s * 0.1, s * 0.42),
				c + Vector2(s * 0.24, -s * 0.06), c + Vector2(s * 0.03, -s * 0.06)])
			draw_colored_polygon(bolt, C_CRIT)
		_:
			draw_circle(c, s * 0.2, C_DIM)

func _heart(c: Vector2, s: float, col: Color) -> void:
	var r := s * 0.2
	draw_circle(c + Vector2(-r * 0.95, -s * 0.1), r, col)
	draw_circle(c + Vector2(r * 0.95, -s * 0.1), r, col)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-s * 0.39, -s * 0.03), c + Vector2(s * 0.39, -s * 0.03), c + Vector2(0.0, s * 0.4)]), col)

func _sword(c: Vector2, s: float, col: Color) -> void:
	# Diagonal blade from bottom-left hilt to top-right tip.
	var d := Vector2(1.0, -1.0).normalized()
	var n := Vector2(d.y, -d.x)
	var hilt := c - d * s * 0.22
	var tip := c + d * s * 0.42
	var w := s * 0.08
	draw_colored_polygon(PackedVector2Array([hilt + n * w, tip, hilt - n * w]), col.lightened(0.35))
	draw_line(hilt + n * s * 0.18, hilt - n * s * 0.18, col, 3.0)
	draw_line(hilt, hilt - d * s * 0.2, col.darkened(0.2), 3.0)

func _plus(p: Vector2, r: float, col: Color) -> void:
	draw_line(p - Vector2(r, 0), p + Vector2(r, 0), col, 2.0)
	draw_line(p - Vector2(0, r), p + Vector2(0, r), col, 2.0)

func _shield(c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array([
		c + Vector2(-s * 0.36, -s * 0.38), c + Vector2(s * 0.36, -s * 0.38),
		c + Vector2(s * 0.34, s * 0.02), c + Vector2(0.0, s * 0.42), c + Vector2(-s * 0.34, s * 0.02)])
	draw_colored_polygon(pts, col)
	draw_line(c + Vector2(0, -s * 0.3), c + Vector2(0, s * 0.3), col.darkened(0.35), 2.0)

func _speed(c: Vector2, s: float, col: Color) -> void:
	for i in 2:
		var x := c.x - s * 0.22 + i * s * 0.28
		draw_polyline(PackedVector2Array([
			Vector2(x - s * 0.12, c.y - s * 0.32), Vector2(x + s * 0.14, c.y), Vector2(x - s * 0.12, c.y + s * 0.32)]), col, 3.0)

func _hourglass(c: Vector2, s: float, col: Color) -> void:
	var t := s * 0.38
	var w := s * 0.3
	draw_colored_polygon(PackedVector2Array([c + Vector2(-w, -t), c + Vector2(w, -t), c]), col)
	draw_colored_polygon(PackedVector2Array([c, c + Vector2(w, t), c + Vector2(-w, t)]), col.darkened(0.25))
	draw_line(c + Vector2(-w - 2, -t), c + Vector2(w + 2, -t), C_DIM, 2.0)
	draw_line(c + Vector2(-w - 2, t), c + Vector2(w + 2, t), C_DIM, 2.0)

func _clock(c: Vector2, s: float, col: Color) -> void:
	draw_arc(c, s * 0.38, 0.0, TAU, 24, col, 2.5)
	draw_line(c, c + Vector2(0, -s * 0.26), col, 2.0)
	draw_line(c, c + Vector2(s * 0.18, 0), col, 2.0)

func _star(c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var a := -PI * 0.5 + i * PI / 4.0
		var r := s * (0.44 if i % 2 == 0 else 0.16)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, col)

func _target(c: Vector2, s: float, col: Color) -> void:
	draw_arc(c, s * 0.3, 0.0, TAU, 24, col, 2.0)
	draw_line(c + Vector2(-s * 0.44, 0), c + Vector2(s * 0.44, 0), col, 1.5)
	draw_line(c + Vector2(0, -s * 0.44), c + Vector2(0, s * 0.44), col, 1.5)
	draw_circle(c, s * 0.07, col)

func _arrow(c: Vector2, s: float, col: Color) -> void:
	draw_line(c + Vector2(-s * 0.4, 0), c + Vector2(s * 0.3, 0), col, 2.5)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(s * 0.44, 0), c + Vector2(s * 0.22, -s * 0.14), c + Vector2(s * 0.22, s * 0.14)]), col)
