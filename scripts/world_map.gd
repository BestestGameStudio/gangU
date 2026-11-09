class_name WorldMap
extends Node
## (#347) Player map record: what terrain the player has explored, plus the
## marks they drew themselves. Pure data + one reveal hook; MapPanel (M) is
## the only view. Mounted by main.gd as ONE persistent child (Shop idiom), so
## per-run reset comes free from RunManager's full scene reload.
##
## SETTLED (Colin, 2026-11-08, #347):
##   - Explored terrain shows automatically, fog-of-war style.
##   - Details (dungeons, points of interest) are NEVER shown automatically;
##     nothing here records gates, portals or enemies. Players mark those
##     themselves with markers and freehand strokes.
##
##   - Run-scoped (#351 death = full reset): kept across area trips within a
##     run, wiped on death by RunManager's reload.
##
## SETTLED (Colin, 2026-11-08): reveal TIMING - terrain appears as you
## explore. Production wires `explore_rule`: each physics tick the cells
## inside EXPLORE_RADIUS_CELLS of the player become explored - the same
## circle TerrainFog clears around the player (vision_radius = 4), so the
## map shows what the player has actually seen. `reveal_rule` stays the
## seam: a Callable `func(player_pos: Vector2, cell_size: int) -> Array`
## returning the Vector2i cells to mark explored this tick; main.gd
## installs `explore_rule` at mount.
##
## Data is keyed by area id (main.gd passes the area node's name), in world
## coordinates, on the same 64 px cells as TerrainMap/BackgroundGrid.
##
## Limits are PROVISIONAL implementation defaults (not approved design):
## MAX_MARKERS markers and MAX_STROKES strokes per area, MAX_STROKE_POINTS
## points per stroke. Placing past a cap is refused (returns false).

signal changed(area_id: StringName)

enum Symbol { CROSS, CIRCLE, TRIANGLE, STAR }
const SYMBOL_NAMES: Array[String] = ["X", "O", "^", "*"]

const CELL_SIZE := 64
## Explore-reveal radius in cells, matched to TerrainFog.vision_radius:
## the map reveals the circle the player can see.
const EXPLORE_RADIUS_CELLS := 4
const MAX_MARKERS := 32
const MAX_STROKES := 64
const MAX_STROKE_POINTS := 256

## Reveal rule (see header). main.gd installs `explore_rule` in production;
## unset only in bare/harness instances.
var reveal_rule: Callable = Callable()
## Player whose position is fed to reveal_rule each physics tick.
var player: Node2D = null
## The current area; set by main.gd on every area swap.
var area_id: StringName = &""
## The current area's TerrainMap, or null (flat GROUND world). View-only.
var terrain: TerrainMap = null

## area_id -> { "explored": {Vector2i: true}, "markers": Array[Dictionary],
## "strokes": Array[PackedVector2Array] }
var _areas: Dictionary = {}

func set_area(id: StringName, area_terrain: TerrainMap) -> void:
	area_id = id
	terrain = area_terrain
	changed.emit(id)

func _physics_process(_delta: float) -> void:
	if not reveal_rule.is_valid() or not is_instance_valid(player) or area_id == &"":
		return
	reveal_cells(area_id, reveal_rule.call(player.global_position, CELL_SIZE))

## --- reveal ---

func reveal_cells(id: StringName, cells: Array) -> int:
	var explored: Dictionary = _area(id)["explored"]
	var added := 0
	for cell in cells:
		if not explored.has(cell):
			explored[cell] = true
			added += 1
	if added > 0:
		changed.emit(id)
	return added

func is_explored(id: StringName, cell: Vector2i) -> bool:
	return _areas.has(id) and _areas[id]["explored"].has(cell)

func explored_cells(id: StringName) -> Array:
	return _areas[id]["explored"].keys() if _areas.has(id) else []

static func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i((world_pos / float(CELL_SIZE)).floor())

static func cell_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * float(CELL_SIZE)

## Production rule (Colin, 2026-11-08): terrain appears as you explore -
## the vision circle around the player every tick.
static func explore_rule(player_pos: Vector2, _cell_size: int) -> Array:
	return radius_cells(player_pos, EXPLORE_RADIUS_CELLS)

## Cells within `radius` cells of `world_pos`, the TerrainFog circle shape.
static func radius_cells(world_pos: Vector2, radius: int) -> Array:
	var center := world_to_cell(world_pos)
	var out: Array = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy <= radius * radius:
				out.append(center + Vector2i(dx, dy))
	return out

## --- player marks ---

func add_marker(id: StringName, world_pos: Vector2, symbol: Symbol) -> bool:
	var list: Array = _area(id)["markers"]
	if list.size() >= MAX_MARKERS:
		return false
	list.append({"pos": world_pos, "symbol": symbol})
	changed.emit(id)
	return true

func markers(id: StringName) -> Array:
	return _areas[id]["markers"] if _areas.has(id) else []

## Starts an empty stroke; returns its index, or -1 at the cap.
func begin_stroke(id: StringName, world_pos: Vector2) -> int:
	var list: Array = _area(id)["strokes"]
	if list.size() >= MAX_STROKES:
		return -1
	list.append(PackedVector2Array([world_pos]))
	changed.emit(id)
	return list.size() - 1

## Appends a point to stroke `index`; refused past MAX_STROKE_POINTS.
func extend_stroke(id: StringName, index: int, world_pos: Vector2) -> bool:
	var list: Array = _area(id)["strokes"]
	if index < 0 or index >= list.size():
		return false
	var s: PackedVector2Array = list[index]
	if s.size() >= MAX_STROKE_POINTS:
		return false
	s.append(world_pos)
	list[index] = s
	changed.emit(id)
	return true

func strokes(id: StringName) -> Array:
	return _areas[id]["strokes"] if _areas.has(id) else []

## Erases every marker within `radius` of `world_pos` and every stroke with
## a point or segment within it. Returns how many marks were removed.
func erase_near(id: StringName, world_pos: Vector2, radius: float) -> int:
	if not _areas.has(id):
		return 0
	var a: Dictionary = _areas[id]
	var removed := 0
	var keep_m: Array = []
	for m: Dictionary in a["markers"]:
		if (m["pos"] as Vector2).distance_to(world_pos) <= radius:
			removed += 1
		else:
			keep_m.append(m)
	var keep_s: Array = []
	for s: PackedVector2Array in a["strokes"]:
		if _stroke_near(s, world_pos, radius):
			removed += 1
		else:
			keep_s.append(s)
	a["markers"] = keep_m
	a["strokes"] = keep_s
	if removed > 0:
		changed.emit(id)
	return removed

func _stroke_near(s: PackedVector2Array, p: Vector2, radius: float) -> bool:
	if s.size() == 1:
		return s[0].distance_to(p) <= radius
	for i in range(s.size() - 1):
		if Geometry2D.get_closest_point_to_segment(p, s[i], s[i + 1]).distance_to(p) <= radius:
			return true
	return false

func _area(id: StringName) -> Dictionary:
	if not _areas.has(id):
		_areas[id] = {"explored": {}, "markers": [], "strokes": []}
	return _areas[id]
