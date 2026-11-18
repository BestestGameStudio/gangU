extends RefCounted
## Draw the terraces and record the visible cliff faces for movement.
const CAP := preload("res://assets/sprites/terrain/terrace_grass_cliff_16.png")
const FACE := preload("res://assets/sprites/terrain/terrace_front_tiles_flat.png")
const LIGHT := preload("res://game/world/terrain/terrace_tile_light.gdshader")
const Terraces := preload("res://game/world/overworld_terraces.gd")
const CELL := Terraces.CELL
const ART_SCALE := 2
const TILE := 16
const QUADRANT := TILE / 2
const CORNERS := [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.ONE, Vector2i.DOWN]

static func add_layers(parent: CanvasItem, terraces: Terraces) -> Image:
	var raster := Image.create(terraces.bounds.size.x * TILE, terraces.bounds.size.y * TILE,
		false, Image.FORMAT_R8)
	if terraces.tops.is_empty():
		return raster
	var origin := terraces.bounds.position * CELL
	var atlas := CAP.get_image()
	var face_atlas := FACE.get_image()
	for level in range(1, int(terraces.tops.values().max()) + 1):
		var layer := Node2D.new()
		layer.name = "TerraceLevel%d" % level
		layer.show_behind_parent = true
		var light := ShaderMaterial.new()
		light.shader = LIGHT
		light.set_shader_parameter("elevation", float(level))
		layer.material = light

		var masks := _build_masks(terraces, level)
		var caps: Array[Rect2i] = []
		var faces: Array[Rect2i] = []
		for cell in masks:
			var tile := _atlas_origin(masks[cell])
			var world := cell * CELL + Vector2i.ONE * (CELL / 2)
			_add_cap(caps, terraces, cell, tile, world)
			var below := _atlas_origin(masks.get(cell + Vector2i.DOWN, 0))
			_add_faces(faces, atlas, terraces, level, tile, below, world)

		layer.draw.connect(func() -> void:
			_draw_regions(layer, FACE, faces)
			_draw_regions(layer, CAP, caps)
		)
		parent.add_child(layer)
		# Trace the same draw order so a higher cap clears walls behind it.
		_stamp_mask(raster, origin, face_atlas, faces, Color.RED)
		_stamp_mask(raster, origin, atlas, caps, Color.BLACK)
	return raster

static func _build_masks(terraces: Terraces, level: int) -> Dictionary[Vector2i, int]:
	var masks: Dictionary[Vector2i, int] = {}
	for cell in terraces.tops:
		# Each higher shelf sits over a complete lower shelf.
		if terraces.tops[cell] >= level:
			for corner in range(CORNERS.size()):
				var tile: Vector2i = cell - CORNERS[corner]
				masks[tile] = masks.get(tile, 0) | (1 << corner)
	return masks

static func _atlas_origin(mask: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(mask % 4, mask / 4) * TILE

static func _add_cap(regions: Array[Rect2i], terraces: Terraces, cell: Vector2i,
		source: Vector2i, world: Vector2i) -> void:
	var size := Vector2i.ONE * QUADRANT
	for corner: Vector2i in CORNERS:
		if not terraces.paths.has(cell + corner):
			var offset := corner * QUADRANT
			_add_region(regions, world + offset * ART_SCALE, source + offset, size)

static func _add_faces(regions: Array[Rect2i], atlas: Image, terraces: Terraces,
		level: int, tile: Vector2i, below: Vector2i, world: Vector2i) -> void:
	for x in range(TILE):
		for y in range(TILE):
			if atlas.get_pixelv(tile + Vector2i(x, y)).a == 0.0:
				continue
			var next := tile + Vector2i(x, y + 1) if y + 1 < TILE else below + Vector2i(x, 0)
			if atlas.get_pixelv(next).a > 0.0:
				continue
			# Every south-facing exit gets a wall, even when the same column
			# crosses another shelf farther down. Match the visible cap pixel.
			var foot := world + Vector2i(x, y + 1) * ART_SCALE
			_add_face_column(regions, terraces, level, foot)

static func _add_face_column(regions: Array[Rect2i], terraces: Terraces,
		level: int, foot: Vector2i) -> void:
	@warning_ignore("integer_division")
	var src_x := posmod(foot.x / ART_SCALE, FACE.get_width())
	var depth := 0
	while depth < FACE.get_height():
		var at := foot + Vector2i(0, depth * ART_SCALE)
		var cell := terraces.cell_at(Vector2(at))
		@warning_ignore("integer_division")
		var length := mini(FACE.get_height() - depth, (CELL - posmod(at.y, CELL)) / ART_SCALE)
		if terraces.bases.get(cell, 0) >= level and not terraces.paths.has(cell):
			_add_region(regions, at, Vector2i(src_x, depth), Vector2i(1, length))
		depth += length

static func _add_region(regions: Array[Rect2i], world: Vector2i, source: Vector2i,
		size: Vector2i) -> void:
	regions.append(Rect2i(world, size * ART_SCALE))
	regions.append(Rect2i(source, size))

static func _draw_regions(canvas: CanvasItem, atlas: Texture2D, regions: Array[Rect2i]) -> void:
	for index in range(0, regions.size(), 2):
		canvas.draw_texture_rect_region(atlas, Rect2(regions[index]), Rect2(regions[index + 1]))

static func _stamp_mask(raster: Image, origin: Vector2i, atlas: Image,
		regions: Array[Rect2i], color: Color) -> void:
	for i in range(0, regions.size(), 2):
		@warning_ignore("integer_division")
		var destination := (regions[i].position - origin) / ART_SCALE
		var source := regions[i + 1]
		for y in range(source.size.y):
			for x in range(source.size.x):
				var offset := Vector2i(x, y)
				if atlas.get_pixelv(source.position + offset).a > 0.0:
					raster.set_pixelv(destination + offset, color)
