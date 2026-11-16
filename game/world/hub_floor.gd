extends Node2D
class_name HubFloor
## The hub uses the same 64 px dual-grid terrain and stone-brick sheets as
## the overworld. Ground blends at lattice points; hub props stay in the scene.

const CENTER := Vector2(576, 410)
const HALF := Vector2(460, 310)
const CHAMFER := 140.0
const WALL_WIDTH := 64.0
const WALL_HEIGHT := Vector2(0, -24)

var outline: PackedVector2Array
var _wall_outer: PackedVector2Array
var _floor_tiles: Array[Dictionary] = []
var _wall_tiles: Array[Dictionary] = []

func _init() -> void:
	z_index = -80
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	outline = _octagon(0.0)
	_wall_outer = _octagon(WALL_WIDTH)
	_build_tiles()

func covers(p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p, outline)

func _octagon(expand: float) -> PackedVector2Array:
	var half := HALF + Vector2.ONE * expand
	var chamfer := CHAMFER + expand * (2.0 - sqrt(2.0))
	var pts := PackedVector2Array()
	for v: Vector2 in [
		Vector2(-half.x + chamfer, -half.y), Vector2(half.x - chamfer, -half.y),
		Vector2(half.x, -half.y + chamfer), Vector2(half.x, half.y - chamfer),
		Vector2(half.x - chamfer, half.y), Vector2(-half.x + chamfer, half.y),
		Vector2(-half.x, half.y - chamfer), Vector2(-half.x, -half.y + chamfer),
	]:
		pts.append(CENTER + v)
	return pts

func _ready() -> void:
	var terrain := get_parent().get_node("Terrain") as TerrainMap
	var cells := {}
	var lo := terrain.world_to_cell(CENTER - HALF - Vector2.ONE * WALL_WIDTH)
	var hi := terrain.world_to_cell(CENTER + HALF + Vector2.ONE * WALL_WIDTH)
	for cy in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			var at := terrain.cell_to_world(Vector2i(cx, cy))
			if Geometry2D.is_point_in_polygon(at, _wall_outer) and not covers(at):
				cells[Vector2i(cx, cy)] = TerrainTypes.OBSTACLE
	terrain.set_cells(cells)

## Full stone tiles use the shared deterministic variant selection. Clip
## them to the plaza and wall cap once; the wall has no grass in its joints.
func _build_tiles() -> void:
	var lo := Vector2i(((CENTER - HALF - Vector2.ONE * WALL_WIDTH) / 64.0).floor())
	var hi := Vector2i(((CENTER + HALF + Vector2.ONE * WALL_WIDTH) / 64.0).ceil())
	for j in range(lo.y, hi.y):
		for i in range(lo.x, hi.x):
			var tile := DualGrid.tile(i, j, [DualGrid.T.STONE, DualGrid.T.STONE,
				DualGrid.T.STONE, DualGrid.T.STONE])
			if tile.is_empty():
				continue
			var at := Vector2(i, j) * 64.0
			var rect := PackedVector2Array([at, at + Vector2(64, 0),
				at + Vector2(64, 64), at + Vector2(0, 64)])
			for piece: PackedVector2Array in Geometry2D.intersect_polygons(rect, outline):
				_floor_tiles.append(_tile_piece(piece, at, tile))
			for piece: PackedVector2Array in Geometry2D.intersect_polygons(rect, _wall_outer):
				for ring: PackedVector2Array in Geometry2D.clip_polygons(piece, outline):
					_wall_tiles.append(_tile_piece(ring, at, tile))

func _tile_piece(poly: PackedVector2Array, at: Vector2, tile: Dictionary) -> Dictionary:
	var uv := PackedVector2Array()
	var size: Vector2 = tile["tex"].get_size()
	for p in poly:
		uv.append((tile["src"].position + p - at) / size)
	return {"poly": poly, "uv": uv, "tex": tile["tex"]}

func _draw_faces(poly: PackedVector2Array, inner: bool) -> void:
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		# South-facing edges: exterior south and the inside of the north wall.
		if (b.x < a.x) != inner and not is_equal_approx(a.x, b.x):
			draw_colored_polygon(PackedVector2Array([a, b, b + WALL_HEIGHT, a + WALL_HEIGHT]),
				Color(0.13, 0.145, 0.19))
			draw_line(a, b, Color(0.07, 0.08, 0.11), 2.0)

func _draw() -> void:
	# Hide the neutral global reference grid while this scene is mounted.
	draw_rect(Rect2(-8192, -8192, 16384, 16384), Color(0.055, 0.065, 0.085))
	for tile in _floor_tiles:
		draw_polygon(tile["poly"], PackedColorArray([Color.WHITE]), tile["uv"], tile["tex"])
	# A raised, darker cap made from the existing brick tiles. Dedicated wall
	# art can replace this first pass without changing the collision footprint.
	draw_set_transform(WALL_HEIGHT)
	for tile in _wall_tiles:
		draw_polygon(tile["poly"], PackedColorArray([Color(0.60, 0.64, 0.73)]), tile["uv"], tile["tex"])
	draw_set_transform(Vector2.ZERO)
	_draw_faces(_wall_outer, false)
	_draw_faces(outline, true)
	var outer_top := _wall_outer.duplicate()
	var inner_top := outline.duplicate()
	for i in outer_top.size():
		outer_top[i] += WALL_HEIGHT
		inner_top[i] += WALL_HEIGHT
	outer_top.append(outer_top[0])
	inner_top.append(inner_top[0])
	draw_polyline(outer_top, Color(0.25, 0.28, 0.35), 2.0)
	draw_polyline(inner_top, Color(0.09, 0.105, 0.14), 3.0)
