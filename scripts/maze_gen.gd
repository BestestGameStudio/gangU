class_name MazeGen
## #367: seeded maze generator for defense missions. A pure function of
## (seed, room grid, entrance count, loop chance) written into a TerrainMap
## through the set_cells seam, like TerrainGen.
##
## Layout (terrain cells, x shown; y is the same):
##   0            sealing ring (OBSTACLE) so nothing walks off the map
##   1            maze border wall (OBSTACLE), cut open at the entrances
##   2+3i..3+3i   room column i: a corridor CORRIDOR (2) cells wide
##   4+3i         wall between room column i and i+1
## The maze is a recursive-backtracker spanning tree over the rooms, so every
## room reaches every other. `loop_chance` then knocks out a share of the
## remaining inner walls, so there are several routes rather than one. The
## rooms within CHAMBER_RADIUS of the centre room are merged into one open
## chamber that holds the objective, the player spawn and the exit.
## Entrances are gaps in the border wall, dealt round the sides W, E, N, S
## (then again), each at a seeded room along that side, picked among the
## rooms whose route to the chamber is at least the side's median. Painted
## GRASS so they read as openings. Walls are plain OBSTACLE: not destroyable.
##
## Every number here is an implementer default, not approved balance.

const DEFAULT_ROOMS := Vector2i(11, 9)
const DEFAULT_ENTRANCES := 4
const DEFAULT_LOOP_CHANCE := 0.08
const CORRIDOR := 2
const PITCH := CORRIDOR + 1
## Rooms within this Chebyshev distance of the centre room form the chamber.
const CHAMBER_RADIUS := 1

const WALL: StringName = TerrainTypes.OBSTACLE
const FLOOR: StringName = TerrainTypes.GROUND
const ENTRANCE_FLOOR: StringName = TerrainTypes.GRASS

enum Side { WEST, EAST, NORTH, SOUTH }
const SIDE_ORDER: Array[int] = [Side.WEST, Side.EAST, Side.NORTH, Side.SOUTH]
const ROOM_DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## Fills `map` and returns, all positions in the map's LOCAL pixels:
##   "size": Vector2i            terrain cells written, from (0, 0)
##   "bounds": Rect2i            the same rectangle (for FlowNav)
##   "rooms": Vector2i           room grid actually used
##   "objective": Vector2        centre of the chamber
##   "player_spawn": Vector2     chamber room below the objective
##   "exit": Vector2             chamber room above the objective
##   "entrances": Array[Vector2] centre of every entrance gap
##   "entrance_cells": Array     per entrance, its Array[Vector2i] gap cells
##   "entrance_sides": Array[int] Side of every entrance
## `rooms` is clamped to at least 2 * CHAMBER_RADIUS + 3 per axis (a chamber
## with a ring of maze round it) and forced odd so the chamber is centred.
static func generate(map: TerrainMap, map_seed: int, rooms: Vector2i = DEFAULT_ROOMS, entrance_count: int = DEFAULT_ENTRANCES, loop_chance: float = DEFAULT_LOOP_CHANCE) -> Dictionary:
	rooms = clamp_rooms(rooms)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("maze:%d" % map_seed)
	var size := Vector2i(PITCH * rooms.x + 3, PITCH * rooms.y + 3)
	var cells := {}
	for y in range(size.y):
		for x in range(size.x):
			cells[Vector2i(x, y)] = WALL
	for j in range(rooms.y):
		for i in range(rooms.x):
			for c in room_cells(Vector2i(i, j)):
				cells[c] = FLOOR
	# Spanning tree: iterative recursive backtracker from the centre room.
	var centre := Vector2i(rooms.x / 2, rooms.y / 2)
	var open := {} # "a|b" wall keys knocked out
	var visited := {centre: true}
	var stack: Array[Vector2i] = [centre]
	while not stack.is_empty():
		var room: Vector2i = stack.back()
		var options: Array[Vector2i] = []
		for d in ROOM_DIRS:
			var n := room + d
			if _in_rooms(n, rooms) and not visited.has(n):
				options.append(n)
		if options.is_empty():
			stack.pop_back()
			continue
		var next: Vector2i = options[rng.randi_range(0, options.size() - 1)]
		visited[next] = true
		open[_wall_key(room, next)] = true
		stack.append(next)
	# Braid: open a share of the walls the tree kept, for alternative routes.
	for j in range(rooms.y):
		for i in range(rooms.x):
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var a := Vector2i(i, j)
				var b := a + d
				if _in_rooms(b, rooms) and not open.has(_wall_key(a, b)) and rng.randf() < loop_chance:
					open[_wall_key(a, b)] = true
	for key: String in open:
		var pair := key.split("|")
		for c in wall_cells(_parse(pair[0]), _parse(pair[1])):
			cells[c] = FLOOR
	# Chamber: carve the whole block of centre rooms, pillars included.
	var lo := room_cells(centre - Vector2i.ONE * CHAMBER_RADIUS)[0]
	var hi := room_cells(centre + Vector2i.ONE * CHAMBER_RADIUS)[-1]
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			cells[Vector2i(x, y)] = FLOOR
	# Entrances: per side, a seeded pick among the edge rooms whose maze route
	# to the chamber is at least that side's median, so waves have to wind
	# through the maze instead of walking straight in.
	var depth := _room_depths(centre, rooms, open)
	var entrances: Array[Vector2] = []
	var entrance_cells: Array = []
	var entrance_sides: Array[int] = []
	var used := {}
	var total := clampi(entrance_count, 1, 2 * (rooms.x + rooms.y))
	var k := 0
	while entrances.size() < total:
		var side: int = SIDE_ORDER[k % SIDE_ORDER.size()]
		k += 1
		var along := rooms.y if side in [Side.WEST, Side.EAST] else rooms.x
		var free: Array[int] = []
		var depths: Array[int] = []
		for t in range(along):
			if not used.has(Vector2i(side, t)):
				free.append(t)
				depths.append(depth[edge_room(side, t, rooms)])
		if free.is_empty():
			continue
		var sorted := depths.duplicate()
		sorted.sort()
		var median: int = sorted[sorted.size() / 2]
		var deep: Array[int] = []
		for n in free.size():
			if depths[n] >= median:
				deep.append(free[n])
		var t: int = deep[rng.randi_range(0, deep.size() - 1)]
		used[Vector2i(side, t)] = true
		var gap := entrance_gap(side, t, rooms)
		for c in gap:
			cells[c] = ENTRANCE_FLOOR
		entrance_cells.append(gap)
		entrance_sides.append(side)
		entrances.append(_centre_px(gap, map.cell_size))
	map.set_cells(cells)
	var mid := room_cells(centre)
	var objective := (Vector2(mid[0]) + Vector2.ONE) * float(map.cell_size)
	var step := Vector2(0, PITCH * map.cell_size)
	return {
		"size": size,
		"bounds": Rect2i(Vector2i.ZERO, size),
		"rooms": rooms,
		"objective": objective,
		"player_spawn": objective + step,
		"exit": objective - step,
		"entrances": entrances,
		"entrance_cells": entrance_cells,
		"entrance_sides": entrance_sides,
	}

static func clamp_rooms(rooms: Vector2i) -> Vector2i:
	var min_rooms := 2 * CHAMBER_RADIUS + 3
	var out := rooms.max(Vector2i(min_rooms, min_rooms))
	if out.x % 2 == 0:
		out.x += 1
	if out.y % 2 == 0:
		out.y += 1
	return out

## Terrain cells of room `r`, row-major (first = top-left, last = bottom-right).
static func room_cells(r: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(CORRIDOR):
		for x in range(CORRIDOR):
			out.append(Vector2i(2 + PITCH * r.x + x, 2 + PITCH * r.y + y))
	return out

## Terrain cells of the wall between neighbouring rooms `a` and `b`.
static func wall_cells(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var lo := a.min(b)
	var out: Array[Vector2i] = []
	for s in range(CORRIDOR):
		if a.y == b.y:
			out.append(Vector2i(2 + PITCH * lo.x + CORRIDOR, 2 + PITCH * lo.y + s))
		else:
			out.append(Vector2i(2 + PITCH * lo.x + s, 2 + PITCH * lo.y + CORRIDOR))
	return out

## Border-wall cells opened for an entrance on `side` at room index `t`.
static func entrance_gap(side: int, t: int, rooms: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for s in range(CORRIDOR):
		match side:
			Side.WEST:
				out.append(Vector2i(1, 2 + PITCH * t + s))
			Side.EAST:
				out.append(Vector2i(PITCH * rooms.x + 1, 2 + PITCH * t + s))
			Side.NORTH:
				out.append(Vector2i(2 + PITCH * t + s, 1))
			Side.SOUTH:
				out.append(Vector2i(2 + PITCH * t + s, PITCH * rooms.y + 1))
	return out

## The room an entrance on `side` at index `t` opens into.
static func edge_room(side: int, t: int, rooms: Vector2i) -> Vector2i:
	match side:
		Side.WEST:
			return Vector2i(0, t)
		Side.EAST:
			return Vector2i(rooms.x - 1, t)
		Side.NORTH:
			return Vector2i(t, 0)
	return Vector2i(t, rooms.y - 1)

## Rooms-graph BFS from `centre` through the opened walls: room -> steps.
static func _room_depths(centre: Vector2i, rooms: Vector2i, open: Dictionary) -> Dictionary:
	var depth := {centre: 0}
	var queue: Array[Vector2i] = [centre]
	var head := 0
	while head < queue.size():
		var r: Vector2i = queue[head]
		head += 1
		for d in ROOM_DIRS:
			var n := r + d
			if _in_rooms(n, rooms) and not depth.has(n) and open.has(_wall_key(r, n)):
				depth[n] = depth[r] + 1
				queue.append(n)
	return depth

static func _in_rooms(r: Vector2i, rooms: Vector2i) -> bool:
	return r.x >= 0 and r.y >= 0 and r.x < rooms.x and r.y < rooms.y

static func _wall_key(a: Vector2i, b: Vector2i) -> String:
	var lo := a.min(b)
	var hi := a.max(b)
	return "%d,%d|%d,%d" % [lo.x, lo.y, hi.x, hi.y]

static func _parse(s: String) -> Vector2i:
	var p := s.split(",")
	return Vector2i(int(p[0]), int(p[1]))

static func _centre_px(gap: Array[Vector2i], cell_size: int) -> Vector2:
	var sum := Vector2.ZERO
	for c in gap:
		sum += Vector2(c) + Vector2(0.5, 0.5)
	return sum / float(gap.size()) * float(cell_size)
