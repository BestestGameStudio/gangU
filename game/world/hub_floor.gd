extends Node2D
class_name HubFloor
## The hub uses the same 64 px dual-grid terrain and stone-brick sheets as
## the overworld. Ground blends at lattice points; hub props stay in the scene.

const CENTER := Vector2(576, 410)
const HALF := Vector2(460, 310)
const CHAMFER := 140.0

var outline: PackedVector2Array

func _init() -> void:
	z_index = -80
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	outline = _octagon()

func covers(p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p, outline)

func _octagon() -> PackedVector2Array:
	var pts := PackedVector2Array()
	for v: Vector2 in [
		Vector2(-HALF.x + CHAMFER, -HALF.y), Vector2(HALF.x - CHAMFER, -HALF.y),
		Vector2(HALF.x, -HALF.y + CHAMFER), Vector2(HALF.x, HALF.y - CHAMFER),
		Vector2(HALF.x - CHAMFER, HALF.y), Vector2(-HALF.x + CHAMFER, HALF.y),
		Vector2(-HALF.x, HALF.y - CHAMFER), Vector2(-HALF.x, -HALF.y + CHAMFER),
	]:
		pts.append(CENTER + v)
	return pts

func _lattice_type(i: int, j: int) -> int:
	return DualGrid.T.STONE if covers(Vector2(i, j) * DualGrid.CELL) else DualGrid.T.GRASS

func _draw() -> void:
	var lo := Vector2i(((CENTER - HALF) / float(DualGrid.CELL)).floor()) - Vector2i.ONE
	var hi := Vector2i(((CENTER + HALF) / float(DualGrid.CELL)).ceil()) + Vector2i.ONE
	for j in range(lo.y, hi.y):
		for i in range(lo.x, hi.x):
			var corners := [_lattice_type(i, j), _lattice_type(i + 1, j),
				_lattice_type(i + 1, j + 1), _lattice_type(i, j + 1)]
			var tile := DualGrid.tile(i, j, corners)
			if not tile.is_empty():
				draw_texture_rect_region(tile["tex"], Rect2(Vector2(i, j) * DualGrid.CELL,
					Vector2.ONE * DualGrid.CELL), tile["src"])
