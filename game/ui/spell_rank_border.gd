class_name SpellRankBorder
extends Control
## #255: code-drawn rank border around a SpellIcon. Color and shape follow the
## owned spell's upgrade tier (SpellProgress.get_tier): every tier keeps the
## tier below's shape and adds one element, so rank reads from shape alone.
##   0 Base           silver  plain frame
##   1 Specialization gold    + square corner studs
##   2 Mastery        red     double frame (darker inner line) + diamond studs
##   3 Signature      purple  + dark outer halo, L corner brackets, top gem
## The frame sits just OUTSIDE the icon rect so it never covers the art's own
## baked frame; studs/brackets reach a few px further (inside the row/grid
## gaps). tier = NONE hides it (empty slots, shop, directory).

const NONE := -1
const MAX_TIER := 3

var tier := NONE

func _init() -> void:
	name = "RankBorder"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false

func set_tier(value: int) -> void:
	var t := clampi(value, NONE, MAX_TIER)
	if t == tier:
		return
	tier = t
	visible = tier != NONE
	queue_redraw()

## Pixel unit: 1 px at the 22 px panel icons, 2 px at the 48 px HUD squares.
func unit() -> float:
	return maxf(1.0, roundf(minf(size.x, size.y) / 24.0))

func color() -> Color:
	return UiStyle.RANK_COLORS[tier] if tier != NONE else Color.TRANSPARENT

## Outermost extent of the drawing past the icon rect, per side, in px.
func overhang() -> float:
	var u := unit()
	match tier:
		0:
			return u
		1:
			return 1.5 * u
		2:
			return 2.5 * u
		3:
			return 3.0 * u
	return 0.0

func _draw() -> void:
	if tier == NONE:
		return
	var u := unit()
	var c := color()
	var r := Rect2(Vector2.ZERO, size)
	if tier >= 3:
		_frame(r.grow(2.0 * u), u, UiStyle.RANK_HALO)
	_frame(r.grow(u), u, c)
	if tier >= 2:
		_frame(r, u, c.darkened(0.45))
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	if tier == 1:
		for p: Vector2 in corners:
			draw_rect(Rect2(p - Vector2(1.5, 1.5) * u, Vector2(3, 3) * u), c)
	if tier >= 2:
		for p: Vector2 in corners:
			_diamond(p, 2.5 * u, c)
	if tier >= 3:
		var arm := roundf(minf(size.x, size.y) * 0.3)
		var out := r.grow(3.0 * u) # bracket line rides the halo's outer edge
		var dirs := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
		var outer := [out.position, Vector2(out.end.x, out.position.y), out.end, Vector2(out.position.x, out.end.y)]
		for i in 4:
			var p: Vector2 = outer[i]
			var d: Vector2 = dirs[i]
			# Horizontal and vertical arms, each u thick, pointing inward.
			draw_rect(Rect2(p, Vector2(d.x * arm, d.y * u)).abs(), c)
			draw_rect(Rect2(p, Vector2(d.x * u, d.y * arm)).abs(), c)
		var gem := Vector2(r.get_center().x, r.position.y - u)
		_diamond(gem, 2.0 * u, c.lightened(0.35))
		_diamond(gem, 1.0 * u, Color.WHITE)

## Square outline of thickness t whose OUTER edge is rect.
func _frame(rect: Rect2, t: float, col: Color) -> void:
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, t)), col)
	draw_rect(Rect2(Vector2(rect.position.x, rect.end.y - t), Vector2(rect.size.x, t)), col)
	draw_rect(Rect2(Vector2(rect.position.x, rect.position.y + t), Vector2(t, rect.size.y - 2.0 * t)), col)
	draw_rect(Rect2(Vector2(rect.end.x - t, rect.position.y + t), Vector2(t, rect.size.y - 2.0 * t)), col)

func _diamond(center: Vector2, radius: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -radius), center + Vector2(radius, 0),
		center + Vector2(0, radius), center + Vector2(-radius, 0)]), col)
