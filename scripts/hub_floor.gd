extends Node2D
class_name HubFloor
## Code-drawn stone plaza under the hub. It lives in hub.tscn rather than on
## the global BackgroundGrid so it is freed with the hub and dungeons keep the
## plain grid. Geometry is built once in _init and drawn once.

const CENTER := Vector2(576, 410)
const HALF := Vector2(460, 310)
const CHAMFER := 140.0
const SPAWN := Vector2(576, 480)
const LANDINGS: Array[Vector2] = [Vector2(300, 380), Vector2(852, 380), Vector2(852, 600)]

const HEIGHTS: Array[float] = [40.0, 52.0, 64.0]
const WIDTHS: Array[float] = [52.0, 72.0, 96.0]
const MORTAR := 3.0
const OUTER_FADE := 120.0
const INNER_FADE := 70.0
const EMBLEM_R := 86.0
const LANDING_R := 58.0
const PATH_W := 40.0

const MORTAR_COLOR := Color(0.145, 0.16, 0.195)
const TILE_BASE := Color(0.205, 0.225, 0.27)
const PATH_COLOR := Color(0.24, 0.265, 0.315)
const INLAY := Color(0.31, 0.35, 0.42)
const DARK_INLAY := Color(0.15, 0.165, 0.205)
const SHADOW := Color(0.06, 0.07, 0.09)

var outline: PackedVector2Array
var tiles: Array[PackedVector2Array] = []
var tile_colors := PackedColorArray()

func _init() -> void:
	z_index = -80
	outline = _octagon(0.0)
	_build_tiles()

func covers(p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p, outline)

## Offsetting an octagon outward by d keeps its 45-degree edges parallel only
## if the chamfer grows by d * (2 - sqrt 2); same vertex order at every offset
## lets the fade bands be drawn as quads between two rings.
func _octagon(d: float) -> PackedVector2Array:
	var h := HALF + Vector2(d, d)
	var c := CHAMFER + d * (2.0 - sqrt(2.0))
	var pts := PackedVector2Array()
	for v: Vector2 in [
		Vector2(-h.x + c, -h.y), Vector2(h.x - c, -h.y), Vector2(h.x, -h.y + c), Vector2(h.x, h.y - c),
		Vector2(h.x - c, h.y), Vector2(-h.x + c, h.y), Vector2(-h.x, h.y - c), Vector2(-h.x, -h.y + c),
	]:
		pts.append(CENTER + v)
	return pts

static func _hash01(x: int, y: int, salt: int) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0

static func _tile_color(c: int, r: int) -> Color:
	var v := (_hash01(c, r, 3) - 0.5) * 0.035
	var tint := (_hash01(c, r, 4) - 0.5) * 0.016
	return Color(TILE_BASE.r + v - tint, TILE_BASE.g + v, TILE_BASE.b + v + tint)

## Ashlar courses: hashed course heights, start offsets and stone widths, so
## joints never line up into the uniform grid the plaza replaces.
func _build_tiles() -> void:
	var y := CENTER.y - HALF.y
	var right := CENTER.x + HALF.x
	var m := MORTAR * 0.5
	var r := 0
	while y < CENTER.y + HALF.y:
		var row_h := _pick(HEIGHTS, _hash01(0, r, 5))
		var x := CENTER.x - HALF.x - _hash01(0, r, 1) * WIDTHS[1]
		var c := 0
		while x < right:
			var w := _pick(WIDTHS, _hash01(c, r, 2))
			var rect := PackedVector2Array([
				Vector2(x + m, y + m), Vector2(x + w - m, y + m),
				Vector2(x + w - m, y + row_h - m), Vector2(x + m, y + row_h - m),
			])
			for piece: PackedVector2Array in Geometry2D.intersect_polygons(rect, outline):
				tiles.append(piece)
				tile_colors.append(_tile_color(c, r))
			x += w
			c += 1
		y += row_h
		r += 1

static func _pick(options: Array[float], t: float) -> float:
	return options[mini(int(t * options.size()), options.size() - 1)]

func _draw_band(inner: PackedVector2Array, outer: PackedVector2Array, ci: Color, co: Color) -> void:
	var n := inner.size()
	for i in n:
		var j := (i + 1) % n
		draw_polygon(PackedVector2Array([inner[i], inner[j], outer[j], outer[i]]), PackedColorArray([ci, ci, co, co]))

func _draw_path(to: Vector2) -> void:
	var dir := (to - SPAWN).normalized()
	var a := SPAWN + dir * EMBLEM_R
	var b := to - dir * LANDING_R
	var n := dir.orthogonal() * (PATH_W * 0.5)
	draw_colored_polygon(PackedVector2Array([a + n, b + n, b - n, a - n]), PATH_COLOR)
	draw_line(a + n, b + n, INLAY, 2.0, true)
	draw_line(a - n, b - n, INLAY, 2.0, true)

func _draw_ring(at: Vector2, r: float, color: Color, width: float) -> void:
	draw_arc(at, r, 0.0, TAU, 72, color, width, true)

func _draw() -> void:
	var clear := Color(SHADOW, 0.0)
	_draw_band(outline, _octagon(OUTER_FADE), Color(SHADOW, 0.75), clear)
	draw_colored_polygon(outline, MORTAR_COLOR)
	for i in tiles.size():
		draw_colored_polygon(tiles[i], tile_colors[i])
	_draw_band(_octagon(-INNER_FADE), outline, clear, Color(SHADOW, 0.35))

	for to in LANDINGS:
		_draw_path(to)
	for to in LANDINGS:
		draw_circle(to, LANDING_R, DARK_INLAY)
		_draw_ring(to, LANDING_R, INLAY, 3.0)
		_draw_ring(to, LANDING_R - 10.0, MORTAR_COLOR, 2.0)

	draw_circle(SPAWN, EMBLEM_R, DARK_INLAY)
	_draw_ring(SPAWN, EMBLEM_R, INLAY, 4.0)
	_draw_ring(SPAWN, EMBLEM_R - 18.0, INLAY, 2.0)
	for k in 8:
		var d := Vector2.from_angle(TAU * k / 8.0 + TAU / 16.0)
		draw_line(SPAWN + d * (EMBLEM_R - 18.0), SPAWN + d * EMBLEM_R, INLAY, 2.0, true)

	draw_polyline(_closed(outline), INLAY, 6.0, true)
	draw_polyline(_closed(_octagon(-8.0)), MORTAR_COLOR, 2.0, true)

func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out
