extends Node2D
class_name OverworldCliffRock
## #820 (Mitra, 2026-11-17: "the cliff should match, there shouldn't be a
## black", "simplify it like the other textures", "make it look vertical",
## "only put them where it would be visible from the front"): the ground
## shader leaves the inside of the cliff band void, so this node paints it.
## Every cell whose four lattice corners are CLIFF gets a flat rock colour
## with a few hashed hints (world-space, so nothing repeats or seams). Where
## the cell below touches water, the bottom of the cell is a vertical rock
## wall: long vertical streaks, darker toward the foot, a lit lip on top.
## Presentation only.

var ground: OverworldGround
var _last_view := Rect2()

const BASE := Color8(88, 82, 88)
const LIGHT := Color8(104, 98, 104)
const DARK := Color8(70, 65, 74)
const LIP := Color8(126, 118, 112)
const WALL_H := 60.0
const PX := 4.0 ## art pixel size in world px

func _init() -> void:
	z_as_relative = false
	z_index = -79 ## with the water layer: above the ground, below characters
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _process(_d: float) -> void:
	if ground != null and ground._view != _last_view:
		_last_view = ground._view
		queue_redraw()

func _is_rock(i: int, j: int) -> bool:
	return ground._lattice_type(i, j) == DualGrid.T.CLIFF \
		and ground._lattice_type(i + 1, j) == DualGrid.T.CLIFF \
		and ground._lattice_type(i + 1, j + 1) == DualGrid.T.CLIFF \
		and ground._lattice_type(i, j + 1) == DualGrid.T.CLIFF

## The wall shows only where the rock's whole foot faces the ocean: the two
## lattice points one row below the cell are both water.
func _faces_water(i: int, j: int) -> bool:
	return ground._lattice_type(i, j + 2) == DualGrid.T.WATER \
		and ground._lattice_type(i + 1, j + 2) == DualGrid.T.WATER

static func _h(a: int, b: int, c: int) -> float:
	return DualGrid._hash01(a, b, c)

func _draw() -> void:
	if ground == null:
		return
	var view := ground._view
	var lo := Vector2i((view.position / 64.0).floor()) - Vector2i.ONE
	var hi := Vector2i((view.end / 64.0).ceil()) + Vector2i.ONE
	for j in range(lo.y, hi.y + 1):
		for i in range(lo.x, hi.x + 1):
			if not _is_rock(i, j):
				continue
			var o := Vector2(i, j) * 64.0
			draw_rect(Rect2(o, Vector2(64, 64)), BASE)
			_hints(i, j, o)
			if _faces_water(i, j):
				_wall(i, j, o)

## A few single-pixel marks per cell, hashed from world pixel coordinates.
func _hints(i: int, j: int, o: Vector2) -> void:
	for k in 5:
		var gx := int(_h(i, j, 11 + k) * 16.0)
		var gy := int(_h(i, j, 31 + k) * 16.0)
		var dark := _h(i, j, 51 + k) < 0.55
		draw_rect(Rect2(o + Vector2(gx, gy) * PX, Vector2(PX, PX)), DARK if dark else LIGHT)

func _wall(i: int, j: int, o: Vector2) -> void:
	var y0 := o.y + 64.0 - WALL_H
	for c in 16:
		var gx := i * 16 + c
		var t := _h(gx, 0, 71)
		var col := BASE.lerp(LIGHT, 0.55) if t > 0.7 else (DARK if t < 0.28 else BASE.darkened(0.1))
		var top := y0 + floorf(_h(gx, 0, 72) * 3.0) * PX ## ragged top, per column
		var x := o.x + c * PX
		draw_rect(Rect2(x, top, PX, o.y + 64.0 - top), col)
		# darker toward the foot, in three steps
		draw_rect(Rect2(x, o.y + 64.0 - 3.0 * PX, PX, PX), Color(0, 0, 0, 0.12))
		draw_rect(Rect2(x, o.y + 64.0 - 2.0 * PX, PX, PX), Color(0, 0, 0, 0.2))
		draw_rect(Rect2(x, o.y + 64.0 - PX, PX, PX), Color(0, 0, 0, 0.3))
		draw_rect(Rect2(x, top, PX, PX), LIP)
		# a long crack on some columns
		if _h(gx, 0, 73) < 0.2:
			draw_rect(Rect2(x, top + PX * 3.0, PX, PX * (2.0 + floorf(_h(gx, 0, 74) * 5.0))), DARK)
