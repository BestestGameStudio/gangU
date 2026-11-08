extends SceneTree
## Layout archetype harness: the null layout keeps the plain generator,
## every preset is deterministic, bordered and navigable, enclosed maps are
## mostly rock, and a forked map survives a corridor cut that strands a
## linear one.

const SIZE := Vector2i(40, 24)
const SEEDS := 10
const PRESETS: Array[String] = ["open_linear", "open_forked", "enclosed_linear", "enclosed_forked"]
const EXPECTED_ENUMS: Dictionary = {
	"open_linear": [TerrainLayout.Enclosure.OPEN, TerrainLayout.Route.LINEAR],
	"open_forked": [TerrainLayout.Enclosure.OPEN, TerrainLayout.Route.FORKED],
	"enclosed_linear": [TerrainLayout.Enclosure.ENCLOSED, TerrainLayout.Route.LINEAR],
	"enclosed_forked": [TerrainLayout.Enclosure.ENCLOSED, TerrainLayout.Route.FORKED],
}
const OPEN_MIN_WALKABLE := 0.9
const ENCLOSED_MAX_WALKABLE := 0.35

var failures := 0
var layouts: Dictionary = {}

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[166] ", name, " -> PASS")
	else:
		failures += 1
		print("[166] ", name, " -> FAIL")

func _initialize() -> void:
	for p in PRESETS:
		var layout := load("res://resources/terrain_layouts/%s.tres" % p) as TerrainLayout
		_check(layout != null, "%s.tres loads as a TerrainLayout" % p)
		layouts[p] = layout
		_check(layout != null and [layout.enclosure, layout.route] == EXPECTED_ENUMS[p], "%s has enclosure %d, route %d" % [p, EXPECTED_ENUMS[p][0], EXPECTED_ENUMS[p][1]])
	if failures == 0:
		_null_layout_legs()
		_preset_legs()
		_fork_legs()
	_done()

func _grid(m: TerrainMap) -> Array[StringName]:
	var out: Array[StringName] = []
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			out.append(m.tile_type_at_cell(Vector2i(x, y)))
	return out

func _gen(map_seed: int, layout: TerrainLayout) -> Array:
	var m := TerrainMap.new()
	var r := TerrainGen.generate(m, map_seed, SIZE, layout)
	return [m, r]

func _border_is_obstacle(m: TerrainMap) -> bool:
	for x in range(SIZE.x):
		if m.tile_type_at_cell(Vector2i(x, 0)) != TerrainTypes.OBSTACLE or m.tile_type_at_cell(Vector2i(x, SIZE.y - 1)) != TerrainTypes.OBSTACLE:
			return false
	for y in range(SIZE.y):
		if m.tile_type_at_cell(Vector2i(0, y)) != TerrainTypes.OBSTACLE or m.tile_type_at_cell(Vector2i(SIZE.x - 1, y)) != TerrainTypes.OBSTACLE:
			return false
	return true

func _walkable_fraction(m: TerrainMap) -> float:
	var walkable := 0
	for y in range(1, SIZE.y - 1):
		for x in range(1, SIZE.x - 1):
			if m.is_walkable_at_cell(Vector2i(x, y)):
				walkable += 1
	return float(walkable) / float((SIZE.x - 2) * (SIZE.y - 2))

func _has_biomes(m: TerrainMap) -> Array[bool]:
	var g := _grid(m)
	return [g.has(TerrainTypes.GRASS) or g.has(TerrainTypes.TREE), g.has(TerrainTypes.SNOW) or g.has(TerrainTypes.ICE)]

func _reaches(m: TerrainMap, r: Dictionary) -> bool:
	return TerrainNav.reachable_from_cell(m, r["spawn"]).has(r["exit"])

func _null_layout_legs() -> void:
	var same := 0
	for s in range(1, 6):
		var plain := TerrainMap.new()
		TerrainGen.generate(plain, s, SIZE)
		var pair := _gen(s, null)
		if _grid(plain) == _grid(pair[0]):
			same += 1
		_check((pair[1]["waypoints"] as Array).is_empty(), "seed %d: null layout has no skeleton waypoints" % s)
		plain.free()
		pair[0].free()
	_check(same == 5, "seeds 1..5: null layout grid identical to the layout-free call over all %d cells (%d/5)" % [SIZE.x * SIZE.y, same])

func _preset_legs() -> void:
	var mean: Dictionary = {}
	for p in PRESETS:
		var layout: TerrainLayout = layouts[p]
		var deterministic := 0
		var navigable := 0
		var skeleton_connects := 0
		var bordered := 0
		var both_biomes := 0
		var total := 0.0
		var lo := 1.0
		var hi := 0.0
		for s in range(1, SEEDS + 1):
			var a := _gen(s, layout)
			var b := _gen(s, layout)
			var m: TerrainMap = a[0]
			var r: Dictionary = a[1]
			if _grid(m) == _grid(b[0]) and r["waypoints"] == b[1]["waypoints"]:
				deterministic += 1
			if TerrainNav.is_navigable(m, m.cell_to_world(r["spawn"]), m.cell_to_world(r["exit"])):
				navigable += 1
			if not r["carved"]:
				skeleton_connects += 1
			if _border_is_obstacle(m):
				bordered += 1
			if _has_biomes(m) == [true, true]:
				both_biomes += 1
			var f := _walkable_fraction(m)
			total += f
			lo = minf(lo, f)
			hi = maxf(hi, f)
			m.free()
			b[0].free()
		mean[p] = total / SEEDS
		_check(deterministic == SEEDS, "%s seeds 1..%d: same seed -> identical grid and waypoints (%d/%d)" % [p, SEEDS, deterministic, SEEDS])
		_check(navigable == SEEDS, "%s seeds 1..%d: navigable spawn -> exit (%d/%d)" % [p, SEEDS, navigable, SEEDS])
		_check(skeleton_connects == SEEDS, "%s seeds 1..%d: skeleton connects without the fallback carve (%d/%d)" % [p, SEEDS, skeleton_connects, SEEDS])
		_check(bordered == SEEDS, "%s seeds 1..%d: border all OBSTACLE (%d/%d)" % [p, SEEDS, bordered, SEEDS])
		if layout.enclosure == TerrainLayout.Enclosure.OPEN:
			_check(both_biomes == SEEDS, "%s seeds 1..%d: both biomes present (%d/%d)" % [p, SEEDS, both_biomes, SEEDS])
			_check(lo > OPEN_MIN_WALKABLE, "%s: every seed's interior walkable fraction > %.2f (min %.3f)" % [p, OPEN_MIN_WALKABLE, lo])
		else:
			print("[166] %s seeds 1..%d with both biomes: %d/%d" % [p, SEEDS, both_biomes, SEEDS])
			_check(hi < ENCLOSED_MAX_WALKABLE, "%s: every seed's interior walkable fraction < %.2f (max %.3f)" % [p, ENCLOSED_MAX_WALKABLE, hi])
		print("[166] %s walkable fraction mean %.3f, min %.3f, max %.3f" % [p, mean[p], lo, hi])

	var distinct := 0
	for s in range(1, SEEDS + 1):
		var grids: Array = []
		for p in PRESETS:
			var pair := _gen(s, layouts[p])
			var g := _grid(pair[0])
			if not grids.has(g):
				grids.append(g)
			pair[0].free()
		if grids.size() == PRESETS.size():
			distinct += 1
	_check(distinct == SEEDS, "seeds 1..%d: the four presets give four different grids (%d/%d)" % [SEEDS, distinct, SEEDS])

## Interior column strictly between the widest-spaced consecutive waypoints
## of `route`, where only that pair's corridor crosses.
func _cut_column(route: Array) -> int:
	var best := 0
	for i in range(1, route.size() - 1):
		if route[i + 1].x - route[i].x > route[best + 1].x - route[best].x:
			best = i
	return (route[best].x + route[best + 1].x) / 2

func _walkable_in_column(m: TerrainMap, x: int, rows: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(rows.x, rows.y + 1):
		if m.is_walkable_at_cell(Vector2i(x, y)):
			out.append(Vector2i(x, y))
	return out

func _block(m: TerrainMap, cells: Array[Vector2i]) -> void:
	for c in cells:
		m.set_cell(c, TerrainTypes.OBSTACLE)

func _fork_legs() -> void:
	var mid := SIZE.y / 2
	var linear_narrow := 0
	var linear_cut := 0
	var fork_survives := 0
	var fork_both_cut := 0
	for s in range(1, SEEDS + 1):
		var lin := _gen(s, layouts["enclosed_linear"])
		var lm: TerrainMap = lin[0]
		var lr: Dictionary = lin[1]
		var lx := _cut_column(lr["routes"][0])
		var section := _walkable_in_column(lm, lx, Vector2i(1, SIZE.y - 2))
		if section.size() == TerrainGen.CORRIDOR_WIDTH:
			linear_narrow += 1
		_block(lm, section)
		if _reaches(lm, lr) == false and section.size() > 0:
			linear_cut += 1
		lm.free()

		var fork := _gen(s, layouts["enclosed_forked"])
		var fm: TerrainMap = fork[0]
		var fr: Dictionary = fork[1]
		var branch_a: Array = fr["routes"][0]
		var fx: int = (branch_a[2].x + branch_a[3].x) / 2
		var top := _walkable_in_column(fm, fx, Vector2i(1, mid - 1))
		var bottom := _walkable_in_column(fm, fx, Vector2i(mid, SIZE.y - 2))
		_block(fm, top)
		if top.size() > 0 and _reaches(fm, fr):
			fork_survives += 1
		_block(fm, bottom)
		if bottom.size() > 0 and not _reaches(fm, fr):
			fork_both_cut += 1
		fm.free()
	_check(linear_narrow == SEEDS, "enclosed_linear seeds 1..%d: cut column holds exactly the %d-wide corridor (%d/%d)" % [SEEDS, TerrainGen.CORRIDOR_WIDTH, linear_narrow, SEEDS])
	_check(linear_cut == SEEDS, "enclosed_linear seeds 1..%d: blocking that corridor cross-section strands the exit (%d/%d)" % [SEEDS, linear_cut, SEEDS])
	_check(fork_survives == SEEDS, "enclosed_forked seeds 1..%d: blocking branch A's corridor mid-branch leaves the exit reachable (%d/%d)" % [SEEDS, fork_survives, SEEDS])
	_check(fork_both_cut == SEEDS, "enclosed_forked seeds 1..%d: blocking branch B in the same column too strands the exit (%d/%d)" % [SEEDS, fork_both_cut, SEEDS])

func _done() -> void:
	if failures == 0:
		print("[166] PASS")
	else:
		print("[166] DONE failures=", failures)
	quit(0 if failures == 0 else 1)
