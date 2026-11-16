extends Node2D
class_name HubFloor
## Shared 64px dual-grid layout, with hub-specific soft flagstone and thin wall art.
## Wall lives on lattice points. Each tile reads TL=1 TR=2 BR=4 BL=8.

const CENTER := Vector2(576, 410)
const HALF := Vector2(460, 310)
const CHAMFER := 140.0
const WALL_WIDTH := 32.0
## Tile transitions extend up to half a cell inside the nominal outline.
## Keep movement cells wholly within that inner floor, clear of the wall art.
const WALL_CLEARANCE := 48.0
const WALL_SHEET = preload("res://assets/sprites/terrain/dualgrid_flagstonewall.png")
const FLOOR_VARIANTS = preload("res://assets/sprites/terrain/dualgrid_variants_flagstone_hub.png")

var outline: PackedVector2Array
var _wall_outer: PackedVector2Array
var _walk_outline: PackedVector2Array
var _tiles: Array[Dictionary] = []
var _thin_wall: Texture2D

func _init() -> void:
	z_index = -80
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	outline = _octagon(0.0)
	_walk_outline = _octagon(-WALL_CLEARANCE)
	_wall_outer = _octagon(WALL_WIDTH)
	_prepare_thin_wall()
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
			var half_cell := Vector2.ONE * terrain.cell_size * 0.5
			var square := PackedVector2Array([at - half_cell,
				at + Vector2(half_cell.x, -half_cell.y), at + half_cell,
				at + Vector2(-half_cell.x, half_cell.y)])
			for outside: PackedVector2Array in Geometry2D.clip_polygons(square, _walk_outline):
				if not Geometry2D.intersect_polygons(outside, _wall_outer).is_empty():
					cells[Vector2i(cx, cy)] = TerrainTypes.OBSTACLE
					break
	terrain.set_cells(cells)

## Trim the unused outer cap instead of clipping it to an unrelated octagon.
## The sheet's square marching-corner layout divides each tile into quadrants.
func _prepare_thin_wall() -> void:
	var image := WALL_SHEET.get_image()
	for mask in range(1, 15):
		var origin := Vector2i(mask % 4, mask / 4) * 64
		for y in 64:
			for x in 64:
				var distance := INF
				for k in 4:
					if mask & (1 << k): continue
					var q := Vector2(32 if k == 1 or k == 2 else 0, 32 if k >= 2 else 0)
					var near := Vector2(x, y).clamp(q, q + Vector2(31, 31))
					distance = minf(distance, Vector2(x, y).distance_to(near))
				if distance > 22.0:
					image.set_pixelv(origin + Vector2i(x, y), Color.TRANSPARENT)
	_thin_wall = ImageTexture.create_from_image(image)

func _build_tiles() -> void:
	var cell := float(DualGrid.CELL)
	var lo := Vector2i(((CENTER - HALF - Vector2.ONE * WALL_WIDTH) / cell).floor())
	var hi := Vector2i(((CENTER + HALF + Vector2.ONE * WALL_WIDTH) / cell).ceil())
	for j in range(lo.y, hi.y):
		for i in range(lo.x, hi.x):
			var mask := 0
			var corners := [Vector2i(i, j), Vector2i(i + 1, j),
				Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]
			for k in 4:
				if not covers(Vector2(corners[k]) * cell): mask |= 1 << k
			var variant := int(DualGrid._hash01(i, j, 709) * 8.0) % 8
			if mask == 15: continue
			var tex: Texture2D = _thin_wall
			var src := Vector2(mask % 4, mask / 4) * cell
			if mask == 0:
				tex = FLOOR_VARIANTS
				src = Vector2(variant * cell, 0)
			var at := Vector2(i, j) * cell
			var rect := PackedVector2Array([at, at + Vector2(cell, 0),
				at + Vector2(cell, cell), at + Vector2(0, cell)])
			for piece: PackedVector2Array in [rect]:
				var uv := PackedVector2Array()
				for p in piece: uv.append((src + p - at) / tex.get_size())
				_tiles.append({"poly": piece, "uv": uv, "tex": tex})

func _draw() -> void:
	# Hide the neutral world grid while the enclosed hub is mounted.
	draw_rect(Rect2(-8192, -8192, 16384, 16384), Color(0.055, 0.065, 0.085))
	for tile in _tiles:
		draw_polygon(tile["poly"], PackedColorArray([Color.WHITE]), tile["uv"], tile["tex"])
