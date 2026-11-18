extends RefCounted
## Shelf outlines and stair landings in the overworld's 32 px collision grid.
## Each outline encloses the walkable top. The apron around it is rock.
const CELL := 32
var tops: Dictionary[Vector2i, int] = {}
var bases: Dictionary[Vector2i, int] = {}
var stairs: Dictionary[Vector2i, bool] = {}
var walls: Dictionary = {}
var clear_ground: Dictionary[Vector2i, bool] = {}
var bounds := Rect2i()

func _init() -> void:
	# Two flights north of the plains hub, with an eastward turn on the shelf.
	_add_shelf(PackedVector2Array([Vector2(26,20), Vector2(32,16), Vector2(46,16),
		Vector2(53,20), Vector2(54,27), Vector2(48,30), Vector2(44,30),
		Vector2(43,32), Vector2(33,32), Vector2(30,30), Vector2(25,29)]), 1, Rect2i(38,31,3,4))
	_add_shelf(PackedVector2Array([Vector2(35,20), Vector2(39,18), Vector2(46,18),
		Vector2(49,21), Vector2(48,24), Vector2(45,25), Vector2(38,25),
		Vector2(35,23)]), 2, Rect2i(42,24,3,4))
	# A separate bluff west of the village.
	_add_shelf(PackedVector2Array([Vector2(-30,14), Vector2(-27,10), Vector2(-20,9),
		Vector2(-17,12), Vector2(-17,15), Vector2(-19,18), Vector2(-24,18),
		Vector2(-25,16), Vector2(-29,17)]), 1, Rect2i(-22,17,3,4))
	for cell in bases:
		if bases[cell] > tops.get(cell, 0) and not stairs.has(cell):
			walls[cell] = TerrainTypes.OBSTACLE
		if walls.has(cell) or stairs.has(cell):
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					clear_ground[cell + Vector2i(dx, dy)] = true
		bounds = bounds.expand(cell)
	bounds = bounds.grow(2)

func _add_shelf(outline: PackedVector2Array, level: int, flight: Rect2i) -> void:
	var extent := Rect2(outline[0], Vector2.ZERO)
	for p in outline:
		extent = extent.expand(p)
	for x in range(int(extent.position.x), int(extent.end.x)):
		for y in range(int(extent.position.y), int(extent.end.y)):
			var cell := Vector2i(x, y)
			if not Geometry2D.is_point_in_polygon(Vector2(cell) + Vector2(0.5, 0.5), outline):
				continue
			tops[cell] = level
			# Front-facing walls expose twice as much rock as the back rim.
			for dx in range(-1, 2):
				for dy in range(-1, 3):
					bases[cell + Vector2i(dx, dy)] = level
	for x in range(flight.position.x, flight.end.x):
		for y in range(flight.position.y, flight.end.y):
			stairs[Vector2i(x, y)] = true

func cell_at(p: Vector2) -> Vector2i:
	return Vector2i((p / CELL).floor())

func bake(material: ShaderMaterial) -> void:
	var image := Image.create(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGB8)
	for cell in bases:
		image.set_pixelv(cell - bounds.position, Color(tops.get(cell, 0) * 0.5,
			bases[cell] * 0.5, float(stairs.has(cell))))
	for cell in stairs:
		if not bases.has(cell):
			image.set_pixelv(cell - bounds.position, Color.BLUE)
	material.set_shader_parameter("relief", ImageTexture.create_from_image(image))
	material.set_shader_parameter("relief_origin", Vector2(bounds.position) * CELL)
	material.set_shader_parameter("relief_cell", float(CELL))
