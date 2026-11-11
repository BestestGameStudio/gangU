class_name TerrainGen
## Seedable biome map generator: a pure function of (seed, size) written
## into a TerrainMap through the set_cells seam. Deterministic: the only
## randomness is the two FastNoiseLite fields seeded from `map_seed`.

const DEFAULT_SIZE := Vector2i(40, 24)
const BIOME_FREQUENCY := 0.06
const DETAIL_FREQUENCY := 0.18
## Detail noise above this becomes the biome's feature tile (TREE / ICE).
const DETAIL_THRESHOLD := 0.22
const PATCH_RADIUS := 1

## biome -> [open tile, feature tile]. Index 0 is always walkable, so it is
## also what the path guarantee carves blocked cells into. A map with a
## TerrainPalette (#266) uses the palette's biomes and border instead.
const BIOMES: Array = [
	[TerrainTypes.GRASS, TerrainTypes.TREE],
	[TerrainTypes.SNOW, TerrainTypes.ICE],
]

const CORRIDOR_WIDTH := 2
const MIN_ROOM_RADIUS := 1
const MAX_ROOM_RADIUS := 2
## A forked route splits at a hub this many columns inside spawn and rejoins
## at one this many columns inside exit.
const HUB_INSET := 5

## Vertical band a route branch draws its waypoint rows from.
enum Band { FULL, TOP, BOTTOM }

## route -> one [band, min waypoints, max waypoints] per branch. Several
## branches share the fork and join hubs, so each one is a distinct route.
const ROUTE_SHAPES: Dictionary = {
	TerrainLayout.Route.LINEAR: [[Band.FULL, 2, 4]],
	TerrainLayout.Route.FORKED: [[Band.TOP, 2, 2], [Band.BOTTOM, 2, 2]],
}

## Fills `map` and returns {"spawn": Vector2i, "exit": Vector2i,
## "carved": bool, "waypoints": Array[Vector2i], "routes": Array}.
## `carved` reports whether the path guarantee had to cut a corridor.
## Without a `layout` the map is pure noise and the skeleton is empty; with
## one, `routes` holds each spawn -> exit waypoint chain and `waypoints`
## their distinct cells in route order.
static func generate(map: TerrainMap, map_seed: int, size: Vector2i = DEFAULT_SIZE, layout: TerrainLayout = null) -> Dictionary:
	var biome_noise := _noise(map_seed, BIOME_FREQUENCY)
	var detail_noise := _noise(map_seed + 1, DETAIL_FREQUENCY)
	var spawn := Vector2i(1, size.y / 2)
	var exit := Vector2i(size.x - 2, size.y / 2)
	var enclosed := layout != null and layout.enclosure == TerrainLayout.Enclosure.ENCLOSED
	var biomes := biomes_for(map)
	var border := TerrainTypes.OBSTACLE if map.palette == null else map.palette.border()
	var cells := {}
	for y in range(size.y):
		for x in range(size.x):
			var cell := Vector2i(x, y)
			if enclosed or x == 0 or y == 0 or x == size.x - 1 or y == size.y - 1:
				cells[cell] = border
				continue
			var tiles: Array = biomes[_biome_index(biome_noise, cell, biomes.size())]
			var feature := detail_noise.get_noise_2d(x, y) > DETAIL_THRESHOLD
			var near_endpoint := _chebyshev(cell, spawn) <= PATCH_RADIUS or _chebyshev(cell, exit) <= PATCH_RADIUS
			cells[cell] = tiles[0] if near_endpoint or not feature else tiles[1]
	var routes: Array[Array] = []
	var waypoints: Array[Vector2i] = []
	if layout != null:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("terrain_layout:%d" % map_seed)
		routes = _route_skeleton(rng, ROUTE_SHAPES[layout.route], size, spawn, exit)
		for route in routes:
			for wp: Vector2i in route:
				if not waypoints.has(wp):
					waypoints.append(wp)
		_carve_skeleton(cells, rng, routes, waypoints, enclosed, biomes, biome_noise, detail_noise, size, spawn, exit)
	map.set_cells(cells)
	var carved := ensure_path(map, map_seed, spawn, exit)
	return {"spawn": spawn, "exit": exit, "carved": carved, "waypoints": waypoints, "routes": routes}

static func _route_skeleton(rng: RandomNumberGenerator, branches: Array, size: Vector2i, spawn: Vector2i, exit: Vector2i) -> Array[Array]:
	var mid := size.y / 2
	var band_rows: Array[Vector2i] = [Vector2i(3, size.y - 4), Vector2i(3, mid - 4), Vector2i(mid + 2, size.y - 4)]
	var hubs: Array[Vector2i] = []
	if branches.size() > 1:
		hubs = [spawn + Vector2i(HUB_INSET, 0), exit - Vector2i(HUB_INSET, 0)]
	var start: Vector2i = spawn if hubs.is_empty() else hubs[0]
	var end: Vector2i = exit if hubs.is_empty() else hubs[1]
	var routes: Array[Array] = []
	for branch: Array in branches:
		var rows: Vector2i = band_rows[branch[0]]
		var count := rng.randi_range(branch[1], branch[2])
		var route: Array[Vector2i] = [spawn]
		if not hubs.is_empty():
			route.append(start)
		for i in range(count):
			var x := start.x + (end.x - start.x) * (i + 1) / (count + 1) + rng.randi_range(-1, 1)
			route.append(Vector2i(x, rng.randi_range(rows.x, rows.y)))
		if not hubs.is_empty():
			route.append(end)
		route.append(exit)
		routes.append(route)
	return routes

## Corridors take the cell's biome open tile. Room cells off the corridors
## may take the biome feature tile in an enclosed map: the corridor already
## crosses each room, so a TREE there can only wall off a pocket.
static func _carve_skeleton(cells: Dictionary, rng: RandomNumberGenerator, routes: Array[Array], waypoints: Array[Vector2i], enclosed: bool, biomes: Array, biome_noise: FastNoiseLite, detail_noise: FastNoiseLite, size: Vector2i, spawn: Vector2i, exit: Vector2i) -> void:
	var corridor := {}
	for route in routes:
		for i in range(route.size() - 1):
			for c in _corridor(route[i], route[i + 1], size):
				corridor[c] = true
	for wp in waypoints:
		var r := rng.randi_range(MIN_ROOM_RADIUS, MAX_ROOM_RADIUS)
		for y in range(maxi(wp.y - r, 1), mini(wp.y + r, size.y - 2) + 1):
			for x in range(maxi(wp.x - r, 1), mini(wp.x + r, size.x - 2) + 1):
				var cell := Vector2i(x, y)
				if corridor.has(cell):
					continue
				var tiles: Array = biomes[_biome_index(biome_noise, cell, biomes.size())]
				var near_endpoint := _chebyshev(cell, spawn) <= PATCH_RADIUS or _chebyshev(cell, exit) <= PATCH_RADIUS
				var feature := enclosed and not near_endpoint and detail_noise.get_noise_2d(x, y) > DETAIL_THRESHOLD
				cells[cell] = tiles[1] if feature else tiles[0]
	for cell: Vector2i in corridor:
		cells[cell] = biomes[_biome_index(biome_noise, cell, biomes.size())][0]

## L-shaped corridor from `a` to `b`. It leaves a waypoint on the middle row
## vertically, so the branches of a fork split up and down instead of
## sharing the spawn row.
static func _corridor(a: Vector2i, b: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var corner := Vector2i(a.x, b.y) if a.y == size.y / 2 else Vector2i(b.x, a.y)
	return _segment(a, corner, size) + _segment(corner, b, size)

## Straight run `CORRIDOR_WIDTH` cells wide, shifted back inside the border
## where it would touch it so it keeps its full width.
static func _segment(a: Vector2i, b: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var lo := a.min(b)
	var hi := a.max(b) + Vector2i.ONE * (CORRIDOR_WIDTH - 1)
	var overflow := (hi - (size - Vector2i(2, 2))).max(Vector2i.ZERO)
	lo -= overflow
	hi -= overflow
	var out: Array[Vector2i] = []
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			out.append(Vector2i(x, y))
	return out

## If `exit` is unreachable from `spawn`, carves an L-shaped corridor
## (along spawn's row, then exit's column) turning every unwalkable cell on
## it into the open tile of its `map_seed` biome. Returns true iff it carved.
static func ensure_path(map: TerrainMap, map_seed: int, spawn: Vector2i, exit: Vector2i) -> bool:
	if TerrainNav.reachable_from_cell(map, spawn).has(exit):
		return false
	var biome_noise := _noise(map_seed, BIOME_FREQUENCY)
	var biomes := biomes_for(map)
	var corridor := {}
	var step_x := signi(exit.x - spawn.x)
	var step_y := signi(exit.y - spawn.y)
	var c := spawn
	while true:
		if not map.is_walkable_at_cell(c):
			corridor[c] = biomes[_biome_index(biome_noise, c, biomes.size())][0]
		if c == exit:
			break
		c += Vector2i(step_x, 0) if c.x != exit.x else Vector2i(0, step_y)
	map.set_cells(corridor)
	return true

static func _noise(noise_seed: int, frequency: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.seed = noise_seed
	n.frequency = frequency
	return n

## #266: [[open, feature], ...] the map's palette asks for, else BIOMES.
static func biomes_for(map: TerrainMap) -> Array:
	return BIOMES if map.palette == null else map.palette.biomes()

## Splits the biome noise range [-1, 1] into `count` equal bands. With two
## biomes this is the original sign test (negative -> 0).
static func _biome_index(biome_noise: FastNoiseLite, cell: Vector2i, count: int = 2) -> int:
	var v := biome_noise.get_noise_2d(cell.x, cell.y)
	return clampi(floori((v + 1.0) * 0.5 * count), 0, count - 1)

static func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
