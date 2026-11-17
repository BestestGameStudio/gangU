class_name LandscapeSample
extends Node2D
## A painted, layered piece of overworld (raised meadow with cliff and stairs,
## path through a ruined slab court, pond, mixed forest, basalt pillars).
## Baked by tools/sprites/draw_landscape_sample.py into three images:
##   ground - under characters; its alpha feathers into the overworld grass
##   over   - tree crowns, bushes and pillars, above characters like the canopy
##   mask   - collision: R obstacle, B water, G one marker per trunk base
## The node's position is the centre of the art. OverworldGround asks it to
## clear decor/tall grass in its footprint and to plant its collision.

const ART_SCALE := 2.0
const GROUND: Texture2D = preload("res://assets/sprites/terrain/landscape_sample_ground.png")
const OVER: Texture2D = preload("res://assets/sprites/terrain/landscape_sample_over.png")
const MASK: Image = preload("res://assets/sprites/terrain/landscape_sample_mask.png")
## Trunk hit box (world px), the same narrow-base rule as overworld trees (#771).
const TRUNK_SIZE := Vector2(8, 6)
## Mask samples per terrain cell edge: any obstacle/water sample marks the cell,
## so thin cliff rims never fall between cell centres.
const SUBSAMPLES := 4

var _over: Node2D

func _init() -> void:
	z_as_relative = false
	z_index = -79 ## above the dual-grid field (-80), below characters
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_over = Node2D.new()
	_over.name = "Over"
	_over.z_as_relative = false
	_over.z_index = OverworldGround.CANOPY_Z
	_over.draw.connect(func() -> void: _over.draw_texture_rect(OVER, _local_rect(), false))
	add_child(_over)

func _draw() -> void:
	draw_texture_rect(GROUND, _local_rect(), false)

func _local_rect() -> Rect2:
	var size := Vector2(MASK.get_size()) * ART_SCALE
	return Rect2(-size * 0.5, size)

## Footprint in the parent area's space (where decor and terrain cells live).
func area_rect() -> Rect2:
	var r := _local_rect()
	r.position += position
	return r

func contains_footprint(at: Vector2, radius: float) -> bool:
	return area_rect().grow(radius).has_point(at)

## Overworld decor (trees, rocks) never grows inside the painted landscape.
func shape_decor(ground: OverworldGround) -> void:
	ground.decor = ground.decor.filter(func(d: Dictionary) -> bool:
		return not contains_footprint(d["at"], float(d["r"]) + 24.0))

## Writes the baked collision into `cells` (OBSTACLE / WATER, GROUND for the
## rest of the footprint so dual-grid leftovers never block) and appends one
## trunk rect per painted tree.
func plant(map: TerrainMap, cells: Dictionary, trunks: Array[Rect2]) -> void:
	var rect := area_rect()
	var lo := map.world_to_cell(rect.position)
	var hi := map.world_to_cell(rect.end - Vector2.ONE)
	var cs := float(map.cell_size)
	for cx in range(lo.x, hi.x + 1):
		for cy in range(lo.y, hi.y + 1):
			var cell := Vector2i(cx, cy)
			var corner := map.cell_to_world(cell) - Vector2(cs, cs) * 0.5
			var type := TerrainTypes.GROUND
			for sx in SUBSAMPLES:
				for sy in SUBSAMPLES:
					var p := _art_px(corner + (Vector2(sx, sy) + Vector2(0.5, 0.5)) * cs / SUBSAMPLES)
					if p.x < 0:
						continue
					var c := MASK.get_pixelv(p)
					if c.r > 0.5:
						type = TerrainTypes.OBSTACLE
					elif c.b > 0.5 and type != TerrainTypes.OBSTACLE:
						type = TerrainTypes.WATER
			cells[cell] = type
	var w := MASK.get_width()
	var data := MASK.get_data()
	var stride := 4 if MASK.get_format() == Image.FORMAT_RGBA8 else 3
	for i in range(1, data.size(), stride):
		if data[i] < 128:
			continue
		var px := (i - 1) / stride
		var foot := rect.position + (Vector2(px % w, px / w) + Vector2(0.5, 1.0)) * ART_SCALE
		trunks.append(Rect2(foot - Vector2(TRUNK_SIZE.x * 0.5, TRUNK_SIZE.y), TRUNK_SIZE))

## Area position -> mask pixel, or (-1, -1) outside the art.
func _art_px(at: Vector2) -> Vector2i:
	var p := Vector2i(((at - area_rect().position) / ART_SCALE).floor())
	if p.x < 0 or p.y < 0 or p.x >= MASK.get_width() or p.y >= MASK.get_height():
		return Vector2i(-1, -1)
	return p
