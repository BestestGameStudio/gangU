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
	if f != _frame:
		_frame = f
		queue_redraw()

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
			var f := (_frame + int(DualGrid._hash01(i, j, 83) * 5.0)) % 5
			var t := DualGrid.tile(i, j, corners, f)
			if t.is_empty():
				continue
			# The loop drifts only a few px per frame, so the stagger alone
			# leaves the large-scale structure aligned; a faint per-tile value
			# shift breaks the remaining wallpaper without new art.
			var v := 0.94 + DualGrid._hash01(i, j, 87) * 0.12
			draw_texture_rect_region(t["tex"], Rect2(Vector2(i, j) * 64.0, Vector2(64, 64)), t["src"], Color(v, v, v))
