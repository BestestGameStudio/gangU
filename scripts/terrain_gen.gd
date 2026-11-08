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
## also what the path guarantee carves blocked cells into.
const BIOMES: Array = [
	[TerrainTypes.GRASS, TerrainTypes.TREE],
	[TerrainTypes.SNOW, TerrainTypes.ICE],
]

## Fills `map` and returns {"spawn": Vector2i, "exit": Vector2i,
## "carved": bool}. `carved` reports whether the path guarantee had to cut
## a corridor because the noise alone left the exit unreachable.
static func generate(map: TerrainMap, map_seed: int, size: Vector2i = DEFAULT_SIZE) -> Dictionary:
	var biome_noise := _noise(map_seed, BIOME_FREQUENCY)
	var detail_noise := _noise(map_seed + 1, DETAIL_FREQUENCY)
	var spawn := Vector2i(1, size.y / 2)
	var exit := Vector2i(size.x - 2, size.y / 2)
	var cells := {}
	for y in range(size.y):
		for x in range(size.x):
			var cell := Vector2i(x, y)
			if x == 0 or y == 0 or x == size.x - 1 or y == size.y - 1:
				cells[cell] = TerrainTypes.OBSTACLE
				continue
			var tiles: Array = BIOMES[_biome_index(biome_noise, cell)]
			var feature := detail_noise.get_noise_2d(x, y) > DETAIL_THRESHOLD
			var near_endpoint := _chebyshev(cell, spawn) <= PATCH_RADIUS or _chebyshev(cell, exit) <= PATCH_RADIUS
			cells[cell] = tiles[0] if near_endpoint or not feature else tiles[1]
	map.set_cells(cells)
	var carved := ensure_path(map, map_seed, spawn, exit)
	return {"spawn": spawn, "exit": exit, "carved": carved}

## If `exit` is unreachable from `spawn`, carves an L-shaped corridor
## (along spawn's row, then exit's column) turning every unwalkable cell on
## it into the open tile of its `map_seed` biome. Returns true iff it carved.
static func ensure_path(map: TerrainMap, map_seed: int, spawn: Vector2i, exit: Vector2i) -> bool:
	if TerrainNav.reachable_from_cell(map, spawn).has(exit):
		return false
	var biome_noise := _noise(map_seed, BIOME_FREQUENCY)
	var corridor := {}
	var step_x := signi(exit.x - spawn.x)
	var step_y := signi(exit.y - spawn.y)
	var c := spawn
	while true:
		if not map.is_walkable_at_cell(c):
			corridor[c] = BIOMES[_biome_index(biome_noise, c)][0]
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

static func _biome_index(biome_noise: FastNoiseLite, cell: Vector2i) -> int:
	return 0 if biome_noise.get_noise_2d(cell.x, cell.y) < 0.0 else 1

static func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
