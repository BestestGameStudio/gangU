extends Node2D
class_name OverworldWater
## #811 (Mitra, 2026-11-16: "water terrain tileset with looping 4-5 frame
## animations ... the bottom becomes a beach so water is the barrier"):
## the ocean past the world edge. OverworldGround leaves every 64 px tile
## with at least one WATER lattice corner undrawn; this child draws exactly
## those tiles from the animated dual-grid water sheets (5 frames stacked
## vertically, see DualGrid.ANIMATED) and re-draws only when the loop frame
## changes (~4-5 fps, not every frame). Tiles are disjoint from the ground's
## own draw, so z only matters against the black backdrop: above it, level
## with the ground. Foam leading edges live inside the tile art, so no
## overlap ordering with the sand is needed.

## Frame durations from the SpriteU water-tile loop (uneven cadence reads
## more organic than a fixed step; foam peaks on frame 2).
const FRAME_MS: Array[int] = [220, 160, 220, 160, 140]

var ground: OverworldGround
var _ms := 0.0
var _frame := 0
var _cycle := 0

func _init() -> void:
	z_as_relative = false
	z_index = -79 ## above OverworldGround (-80), below characters
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for m in FRAME_MS:
		_cycle += m

func _process(delta: float) -> void:
	_ms += delta * 1000.0
	var f := _frame_at(int(_ms) % _cycle)
	_frame = f
	queue_redraw() ## the tide edge moves continuously

static func _frame_at(r: int) -> int:
	for i in FRAME_MS.size():
		if r < FRAME_MS[i]:
			return i
		r -= FRAME_MS[i]
	return 0

func _draw() -> void:
	if ground == null:
		return
	var view := ground._view
	var lo := Vector2i((view.position / 64.0).floor()) - Vector2i.ONE
	var hi := Vector2i((view.end / 64.0).ceil()) + Vector2i.ONE
	for j in range(lo.y, hi.y + 1):
		for i in range(lo.x, hi.x + 1):
			_draw_tide(i, j)
	for j in range(lo.y, hi.y + 1):
		for i in range(lo.x, hi.x + 1):
			var corners := [
				ground._lattice_type(i, j),
				ground._lattice_type(i + 1, j),
				ground._lattice_type(i + 1, j + 1),
				ground._lattice_type(i, j + 1),
			]
			var has_water := false
			for c in corners:
				if c == DualGrid.T.WATER:
					has_water = true
					break
			if not has_water:
				continue
			# Per-tile phase offset: the 64 px loop is the same everywhere, so
			# a shared frame reads as wallpaper in open water. A hashed offset
			# staggers the loop per tile (foam on neighbouring shore tiles can
			# be a beat apart - reads as waves rolling in, not a hard seam).
			var f := (_frame + _swell_phase(i, j)) % 5
			var t := DualGrid.tile(i, j, corners, f)
			if t.is_empty():
				continue
			# No per-tile value shift: open water is one flat tone everywhere
			# (Mitra: no visible tile blocks). Motion comes from the foam and
			# the phase-staggered loop alone.
			draw_texture_rect_region(_see_through(t["tex"]), Rect2(Vector2(i, j) * 64.0, Vector2(64, 64)), t["src"])
			_draw_depth(i, j)
			_draw_waves(i, j, corners)
			_draw_sparkle(i, j, corners, f)

## Zone field on water (Mitra: water stays flat with just specks near the
## shore; the zone noise starts a bit away from the shore and fades in as a
## gradient with distance). Shore tiles are drawn here, over the ground's
## overlay, so their LAND pixels get the field back via a cached land mask;
## their water pixels get none. Open-water tiles fade in by tile distance.
const WATER_ZONES := false
const FADE_START := 2.0 ## tiles of fully flat water next to the shore
const FADE_LEN := 7.0   ## tiles over which the field reaches full strength
var _dist_cache := {}
var _img_cache := {}

func _water_dist(i: int, j: int) -> float:
	var key := Vector2i(i, j)
	if _dist_cache.has(key):
		return _dist_cache[key]
	var best := FADE_START + FADE_LEN
	for d in 8:
		var dx: int = [1, 1, 0, -1, -1, -1, 0, 1][d]
		var dy: int = [0, 1, 1, 1, 0, -1, -1, -1][d]
		var step := 1
		while float(step) < best:
			if ground._lattice_type(i + dx * step, j + dy * step) != DualGrid.T.WATER:
				best = float(step)
				break
			step += 1
	_dist_cache[key] = best
	return best

## Mitra: white specks in small clumps (like the firefly decor), not single
## dots. A hashed clump per tile (presence, position, size and every speck's
## twinkle phase are hashed, so no grid pattern). Each speck is on ~2 of 5
## loop frames, offset from its neighbours, so a clump shimmers.
func _draw_sparkle(i: int, j: int, corners: Array, f: int) -> void:
	var water := 0
	for c in corners:
		if c == DualGrid.T.WATER:
			water += 1
	var chance := 0.05 if water == 4 else 0.10
	if DualGrid._hash01(i, j, 201) > chance:
		return
	var base := Vector2(i, j) * 64.0 + Vector2(
		12.0 + floorf(DualGrid._hash01(i, j, 203) * 40.0),
		12.0 + floorf(DualGrid._hash01(i, j, 204) * 40.0))
	var n := 3 + int(DualGrid._hash01(i, j, 206) * 3.0)
	for s in n:
		var off := Vector2(
			floorf((DualGrid._hash01(i, j, 210 + s) - 0.5) * 14.0) * 2.0,
			floorf((DualGrid._hash01(i, j, 220 + s) - 0.5) * 9.0) * 2.0)
		var k := (_frame + int(DualGrid._hash01(i, j, 230 + s) * 5.0)) % 5
		var a := 0.0
		if k == 1:
			a = 0.8
		elif k == 0 or k == 2:
			a = 0.35
		if a <= 0.0:
			continue
		var at := base + off
		draw_rect(Rect2(at, Vector2(2, 2)), Color(1.0, 1.0, 1.0, a))
		if k == 1 and DualGrid._hash01(i, j, 240 + s) < 0.4:
			var halo := Color(1.0, 1.0, 1.0, 0.3)
			draw_rect(Rect2(at + Vector2(-2, 0), Vector2(2, 2)), halo)
			draw_rect(Rect2(at + Vector2(2, 0), Vector2(2, 2)), halo)
			draw_rect(Rect2(at + Vector2(0, -2), Vector2(2, 2)), halo)
			draw_rect(Rect2(at + Vector2(0, 2), Vector2(2, 2)), halo)

## Mitra: wave decorations on open water for movement. A sparse hashed crest
## per open-water tile: a short pixel arc that fades in, drifts 2 px sideways
## per loop frame and fades out. Never on shore tiles (the sheet foam owns
## those), nothing aligned to a grid.
const WAVE_COLOR := Color(0.62, 0.82, 0.88)
const WAVE_ALPHA: Array[float] = [0.18, 0.45, 0.55, 0.38, 0.14]

func _draw_waves(i: int, j: int, corners: Array) -> void:
	for c in corners:
		if c != DualGrid.T.WATER:
			return
	if DualGrid._hash01(i, j, 301) > 0.09:
		return
	var k := (_frame + int(DualGrid._hash01(i, j, 302) * 5.0)) % 5
	var half := 3 + int(DualGrid._hash01(i, j, 303) * 3.0)   ## crest half width in 2 px units
	var at := Vector2(i, j) * 64.0 + Vector2(
		12.0 + floorf(DualGrid._hash01(i, j, 304) * 28.0) * 1.0,
		14.0 + floorf(DualGrid._hash01(i, j, 305) * 30.0) * 1.0)
	at = (at / 2.0).floor() * 2.0 + Vector2(float(k) * 2.0, 0.0)
	var col := Color(WAVE_COLOR.r, WAVE_COLOR.g, WAVE_COLOR.b, WAVE_ALPHA[k])
	for u in range(-half, half + 1):
		var drop := 0.0
		if absi(u) >= half - 1:
			drop = 2.0
		elif absi(u) >= half - 2:
			drop = 0.0
		draw_rect(Rect2(at + Vector2(float(u) * 2.0, drop), Vector2(2, 2)), col)
	# thin shadow line under the crest
	var sh := Color(0.05, 0.2, 0.32, WAVE_ALPHA[k] * 0.8)
	for u in range(-half + 1, half):
		draw_rect(Rect2(at + Vector2(float(u) * 2.0, 4.0), Vector2(2, 2)), sh)

## The ground is a shader now, so the flat base colour of a shore tile's land
## would paint over it as a tile-shaped rectangle. Turn those exact flat land
## colours transparent (cached per sheet) so only the water, foam and wet-sand
## rim draw here and the shader's own sand/grass/dirt shows through.
const LAND_KEYS := [Color8(216, 188, 132), Color8(66, 118, 58), Color8(114, 82, 58)]
var _keyed := {}

func _see_through(tex: Texture2D) -> Texture2D:
	if _keyed.has(tex):
		return _keyed[tex]
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			for k in LAND_KEYS:
				if c.is_equal_approx(k):
					img.set_pixel(x, y, Color(0, 0, 0, 0))
					break
	var out := ImageTexture.create_from_image(img)
	_keyed[tex] = out
	return out

## Depth: deeper water further from the shore. One smooth tint, interpolated
## across each tile from per-corner values (so neighbouring tiles agree on
## every shared edge and nothing reads as a block). Alpha is 0 within
## DEPTH_START tiles of land, so the shallows and the shore tiles keep the
## sheet colours exactly, and it eases in to DEPTH_ALPHA out at sea.
const DEPTH_START := 1.5   ## tiles of untouched shallow water
const DEPTH_LEN := 9.0     ## tiles to reach full depth
const DEPTH_ALPHA := 0.42
const DEPTH_COLOR := Color(0.03, 0.14, 0.26)
const DEPTH_REACH := 11
var _depth_cache := {}

func _corner_depth(i: int, j: int) -> float:
	var key := Vector2i(i, j)
	if _depth_cache.has(key):
		return _depth_cache[key]
	var best := float(DEPTH_REACH)
	if ground._lattice_type(i, j) != DualGrid.T.WATER:
		best = 0.0
	else:
		for dy in range(-DEPTH_REACH, DEPTH_REACH + 1):
			for dx in range(-DEPTH_REACH, DEPTH_REACH + 1):
				var d := sqrt(float(dx * dx + dy * dy))
				if d >= best:
					continue
				if ground._lattice_type(i + dx, j + dy) != DualGrid.T.WATER:
					best = d
	var a := DEPTH_ALPHA * smoothstep(DEPTH_START, DEPTH_START + DEPTH_LEN, best)
	_depth_cache[key] = a
	return a

func _draw_depth(i: int, j: int) -> void:
	var a00 := _corner_depth(i, j)
	var a10 := _corner_depth(i + 1, j)
	var a11 := _corner_depth(i + 1, j + 1)
	var a01 := _corner_depth(i, j + 1)
	if a00 + a10 + a11 + a01 <= 0.0:
		return
	var at := Vector2(i, j) * 64.0
	var pts := PackedVector2Array([at, at + Vector2(64, 0), at + Vector2(64, 64), at + Vector2(0, 64)])
	var cols := PackedColorArray()
	for a in [a00, a10, a11, a01]:
		cols.append(Color(DEPTH_COLOR.r, DEPTH_COLOR.g, DEPTH_COLOR.b, a))
	draw_polygon(pts, cols)

## Shoreline swell: the foam loop is phased by position, not hashed per tile,
## so the wash rolls along the beach as one slow diagonal wave (neighbouring
## tiles are at most one frame apart) instead of flickering tile by tile.
## A little hashed wobble keeps long straight stretches from looking ruled.
func _swell_phase(i: int, j: int) -> int:
	var w := float(i) * 0.55 + float(j) * 0.3 + (DualGrid._hash01(i >> 1, j >> 1, 84) - 0.5) * 0.9
	return posmod(int(floor(w)), 5)

## Tide: a slow swell that washes up the sand and pulls back (period TIDE_S).
## Sand the water has reached is darkened (wet); when it recedes it leaves a
## damp band at the high-water line that dries out until the next wave. All
## per-corner values interpolated across each tile, so it is smooth and
## continuous between tiles. Drawn under the shore tile art, which hides
## the part over water.
const TIDE_S := 14.0
const TIDE_MIN := 0.55   ## tiles of beach the water reaches at low tide
const TIDE_MAX := 2.1    ## ... at high tide
const WET_COLOR := Color(0.38, 0.28, 0.17)
const WET_ALPHA := 0.42
const MARK_ALPHA := 0.2
const LAND_REACH := 4
var _land_cache := {}

static func tide_phase() -> float:
	return fposmod(float(Time.get_ticks_msec()) / 1000.0 / TIDE_S, 1.0)

## Tide level in tiles of beach reached (high at phase 0.5).
static func tide_level() -> float:
	return TIDE_MIN + (TIDE_MAX - TIDE_MIN) * (0.5 - 0.5 * cos(tide_phase() * TAU))

## Distance (tiles) from a lattice corner to the nearest water corner;
## 0 on water, LAND_REACH at most. Cached.
func _land_dist(i: int, j: int) -> float:
	var key := Vector2i(i, j)
	if _land_cache.has(key):
		return _land_cache[key]
	var best := float(LAND_REACH)
	if ground._lattice_type(i, j) == DualGrid.T.WATER:
		best = 0.0
	else:
		for dy in range(-LAND_REACH, LAND_REACH + 1):
			for dx in range(-LAND_REACH, LAND_REACH + 1):
				var d := sqrt(float(dx * dx + dy * dy))
				if d >= best:
					continue
				if ground._lattice_type(i + dx, j + dy) == DualGrid.T.WATER:
					best = d
	_land_cache[key] = best
	return best

## Distance in tiles from a world point to the water (bilinear of corners).
func land_dist_at(p: Vector2) -> float:
	var g := p / 64.0
	var i := int(floor(g.x))
	var j := int(floor(g.y))
	var f := g - Vector2(i, j)
	var a := lerpf(_land_dist(i, j), _land_dist(i + 1, j), f.x)
	var b := lerpf(_land_dist(i, j + 1), _land_dist(i + 1, j + 1), f.x)
	return lerpf(a, b, f.y)

func _wet_alpha(d: float, i: int, j: int, lvl: float, fade: float) -> float:
	# Hashed per-corner wobble so the wash line is not a clean contour.
	var w := (DualGrid._hash01(i, j, 401) - 0.5) * 0.18
	var fresh := WET_ALPHA * (1.0 - smoothstep(lvl - 1.3, lvl + 0.35, d + w))
	var mark := MARK_ALPHA * fade * (1.0 - smoothstep(TIDE_MAX - 1.4, TIDE_MAX + 0.3, d + w))
	return clampf(maxf(fresh, mark), 0.0, 0.7)

func _draw_tide(i: int, j: int) -> void:
	var t00 := ground._lattice_type(i, j)
	var t10 := ground._lattice_type(i + 1, j)
	var t11 := ground._lattice_type(i + 1, j + 1)
	var t01 := ground._lattice_type(i, j + 1)
	var sand := false
	var water := false
	for t in [t00, t10, t11, t01]:
		if t == DualGrid.T.SAND:
			sand = true
		elif t == DualGrid.T.WATER:
			water = true
		else:
			return    ## grass/cliff/other: the beach only
	if not sand:
		return
	var d00 := _land_dist(i, j)
	var d10 := _land_dist(i + 1, j)
	var d11 := _land_dist(i + 1, j + 1)
	var d01 := _land_dist(i, j + 1)
	if minf(minf(d00, d10), minf(d11, d01)) > TIDE_MAX + 0.3:
		return
	var lvl := tide_level()
	var since_peak := fposmod(tide_phase() - 0.5, 1.0)
	var fade := 1.0 - 0.8 * since_peak
	var at := Vector2(i, j) * 64.0
	var pts := PackedVector2Array([at, at + Vector2(64, 0), at + Vector2(64, 64), at + Vector2(0, 64)])
	var cols := PackedColorArray()
	var ds := [d00, d10, d11, d01]
	var is_ := [i, i + 1, i + 1, i]
	var js := [j, j, j + 1, j + 1]
	for k in 4:
		cols.append(Color(WET_COLOR.r, WET_COLOR.g, WET_COLOR.b, _wet_alpha(ds[k], is_[k], js[k], lvl, fade)))
	draw_polygon(pts, cols)
