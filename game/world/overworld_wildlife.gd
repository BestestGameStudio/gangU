extends Node2D
class_name OverworldWildlife
## #811 (Mitra, 2026-11-16: "add some seagulls and fish ... footprints and
## seashells on the beach"): small life on the south beach. Sprites come from
## the SpriteU package (seagull, fish, fish-splash, seashell, footprint).
## Everything is hashed or time-driven, never random, so it is the same for
## every player and costs a handful of draws per frame. Presentation only: no
## collision, no gameplay. Shells and footprints sit on the sand and the tide
## (OverworldWater) washes the footprints away near the waterline.

var ground: OverworldGround
var water: OverworldWater

const GULLS := 5
const FISH := 7
const CELL := 32          ## sprite cell size (px)
const SHELL_CELL := 224.0 ## hashed shell cells
const TRAIL_CELL := 768.0 ## hashed footprint trails

static var _tex: Dictionary = {}

func _init() -> void:
	z_as_relative = false
	z_index = 40 ## gulls fly above characters; fish, shells and prints are drawn under them by order below
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

static func _t(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = load("res://assets/sprites/terrain/%s.png" % name) as Texture2D
	return _tex[name]

func _process(_d: float) -> void:
	queue_redraw()

func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

func _h(a: int, b: int, c: int) -> float:
	return DualGrid._hash01(a, b, c)

## First water y below the beach at world x (south shoreline), cached by 64 px column.
var _shore_cache := {}
func _shore_y(x: float) -> float:
	var col := int(floor(x / 64.0))
	if _shore_cache.has(col):
		return _shore_cache[col]
	var y0 := int(floor((OverworldGround.CENTER.y + OverworldGround.RADII.y) / 64.0))
	var y := y0
	for k in 80:
		if ground._lattice_type(col, y0 + k) == DualGrid.T.WATER:
			y = y0 + k
			break
	_shore_cache[col] = float(y) * 64.0
	return _shore_cache[col]

func _draw() -> void:
	if ground == null or water == null:
		return
	var view := ground._view.grow(160.0)
	var t := _now()
	_draw_footprints(view)
	_draw_shells(view)
	_draw_fish(view, t)
	_draw_gulls(view, t)

# ---------------------------------------------------------------- shells
func _draw_shells(view: Rect2) -> void:
	var tex := _t("seashell")
	var lo := Vector2i((view.position / SHELL_CELL).floor())
	var hi := Vector2i((view.end / SHELL_CELL).ceil())
	for cy in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			if _h(cx, cy, 501) > 0.34:
				continue
			var n := 1 + int(_h(cx, cy, 502) * 3.0)  ## clump of 1-3
			var base := Vector2(cx, cy) * SHELL_CELL + Vector2(_h(cx, cy, 503), _h(cx, cy, 504)) * SHELL_CELL
			for k in n:
				var at := base + Vector2((_h(cx, cy, 510 + k) - 0.5) * 70.0, (_h(cx, cy, 520 + k) - 0.5) * 40.0)
				if not _on_beach(at):
					continue
				var d := water.land_dist_at(at)
				if d > 5.0 or d < 0.5:
					continue
				var v := int(_h(cx, cy, 530 + k) * 3.0) % 3
				draw_texture_rect_region(tex, Rect2(at - Vector2(16, 16), Vector2(32, 32)), Rect2(v * 32, 0, 32, 32))

func _on_beach(p: Vector2) -> bool:
	return ground._lattice_type(roundi(p.x / 64.0), roundi(p.y / 64.0)) == DualGrid.T.SAND \
		and ground._lattice_type(floori(p.x / 64.0), floori(p.y / 64.0)) == DualGrid.T.SAND

# ----------------------------------------------------------- footprints
## A trail is 6-9 alternating left/right prints along a hashed heading, in a
## hashed 768 px cell. Prints fade out where the tide has reached (the wash
## line is d < tide level), so they are wiped near the water and come back
## into view as it recedes.
func _draw_footprints(view: Rect2) -> void:
	var tex := _t("footprint")
	var lvl := OverworldWater.tide_level()
	var lo := Vector2i((view.grow(300.0).position / TRAIL_CELL).floor())
	var hi := Vector2i((view.grow(300.0).end / TRAIL_CELL).ceil())
	for cy in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			if _h(cx, cy, 601) > 0.55:
				continue
			var start := Vector2(cx, cy) * TRAIL_CELL + Vector2(_h(cx, cy, 602), _h(cx, cy, 603)) * TRAIL_CELL
			var ang := _h(cx, cy, 604) * TAU
			var dir := Vector2(cos(ang), sin(ang))
			var side := Vector2(-dir.y, dir.x)
			var n := 6 + int(_h(cx, cy, 605) * 4.0)
			for k in n:
				var at := start + dir * (float(k) * 38.0) + side * (7.0 if k % 2 == 0 else -7.0) \
					+ Vector2(_h(cx, cy, 610 + k) - 0.5, _h(cx, cy, 630 + k) - 0.5) * 4.0
				if not view.has_point(at) or not _on_beach(at):
					continue
				var d := water.land_dist_at(at)
				var a := smoothstep(lvl - 0.2, lvl + 0.7, d) * 0.9
				if d > 5.0:
					a *= 0.0
				if a <= 0.02:
					continue
				var frame := 0 if k % 2 == 0 else 1
				draw_set_transform(at, ang + PI * 0.5, Vector2.ONE)
				draw_texture_rect_region(tex, Rect2(Vector2(-16, -16), Vector2(32, 32)), Rect2(frame * 32, 0, 32, 32), Color(1, 1, 1, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ------------------------------------------------------------------ fish
## Fish cruise slow loops in open water 4-11 tiles off the beach, drawn
## semi-transparent so they read as under the surface. Now and then one leaps:
## it rises on an arc (brighter, bigger), with a splash at takeoff and landing.
func _draw_fish(view: Rect2, t: float) -> void:
	var tex := _t("fish")
	var spl := _t("fish_splash")
	for f in FISH:
		var ax := OverworldGround.CENTER.x + (_h(f, 0, 701) - 0.5) * OverworldGround.RADII.x * 1.5
		var depth := (5.0 + _h(f, 0, 702) * 7.0) * 64.0
		var ay := _shore_y(ax) + depth
		var w := 0.12 + _h(f, 0, 703) * 0.08
		var ph := _h(f, 0, 704) * TAU
		var rx := 150.0 + _h(f, 0, 705) * 120.0
		var ry := 60.0 + _h(f, 0, 706) * 60.0
		var pos := Vector2(ax + cos(t * w + ph) * rx, ay + sin(t * w * 1.3 + ph) * ry)
		var vel := Vector2(-sin(t * w + ph) * rx * w, cos(t * w * 1.3 + ph) * ry * w * 1.3)
		if not view.grow(100.0).has_point(pos):
			continue
		var heading := vel.angle()
		var fr := int(t * 7.0 + f) % 4
		# Leap cycle: ~11 s period, leap lasts 0.9 s.
		var period := 9.0 + _h(f, 0, 707) * 6.0
		var lt := fposmod(t + _h(f, 0, 708) * period, period)
		if lt < 0.9:
			var u := lt / 0.9
			var rise := sin(u * PI)
			var scale := 1.0 + 0.45 * rise
			draw_set_transform(pos + Vector2(0, -rise * 26.0), heading, Vector2(scale, scale))
			draw_texture_rect_region(tex, Rect2(Vector2(-16, -16), Vector2(32, 32)), Rect2(fr * 32, 0, 32, 32), Color(1, 1, 1, 0.95))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_set_transform(pos, heading, Vector2.ONE)
			draw_texture_rect_region(tex, Rect2(Vector2(-16, -16), Vector2(32, 32)), Rect2(fr * 32, 0, 32, 32), Color(1, 1, 1, 0.55))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# splash: takeoff (just before lt=0 .. 0.5 s) and landing (lt 0.9 .. 1.4)
		var sf := -1
		if lt < 0.5:
			sf = int(lt / 0.5 * 5.0)
		elif lt >= 0.9 and lt < 1.5:
			sf = int((lt - 0.9) / 0.6 * 5.0)
		if sf >= 0 and sf < 5:
			draw_texture_rect_region(spl, Rect2(pos - Vector2(16, 16), Vector2(32, 32)), Rect2(sf * 32, 0, 32, 32), Color(1, 1, 1, 0.8))

# ----------------------------------------------------------------- gulls
## Gulls glide in wide, slow loops over the beach and the shallows (one hashed
## loop each, shifted along the south shore), flapping in short bursts between
## glides. Heading follows the path; each casts a soft shadow on the ground.
func _draw_gulls(view: Rect2, t: float) -> void:
	var tex := _t("seagull")
	for g in GULLS:
		var cx := OverworldGround.CENTER.x + (_h(g, 0, 801) - 0.5) * OverworldGround.RADII.x * 1.6
		var cy := _shore_y(cx) - 40.0 + (_h(g, 0, 802) - 0.3) * 260.0
		var w := 0.10 + _h(g, 0, 803) * 0.06
		var ph := _h(g, 0, 804) * TAU
		var rx := 380.0 + _h(g, 0, 805) * 260.0
		var ry := 130.0 + _h(g, 0, 806) * 110.0
		var pos := Vector2(cx + cos(t * w + ph) * rx, cy + sin(t * w + ph) * ry)
		var vel := Vector2(-sin(t * w + ph) * rx, cos(t * w + ph) * ry)
		if not view.grow(160.0).has_point(pos):
			continue
		var heading := vel.angle()
		var flap := fposmod(t * 0.5 + _h(g, 0, 807), 1.0) < 0.55   ## flapping vs gliding
		var fr := int(t * 9.0 + g) % 4 if flap else 0
		# Soft shadow on the ground, offset away from the light.
		draw_set_transform(pos + Vector2(14, 34), heading, Vector2(1.0, 0.55))
		draw_texture_rect_region(tex, Rect2(Vector2(-16, -16), Vector2(32, 32)), Rect2(fr * 32, 0, 32, 32), Color(0, 0, 0, 0.16))
		draw_set_transform(pos, heading, Vector2(1.25, 1.25))
		draw_texture_rect_region(tex, Rect2(Vector2(-16, -16), Vector2(32, 32)), Rect2(fr * 32, 0, 32, 32))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
