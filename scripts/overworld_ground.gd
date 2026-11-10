extends Node2D
class_name OverworldGround
## #346: code-drawn overworld field (HubFloor idiom: lives in the area scene,
## freed with it, drawn once). A wide grass field with dirt roads from the
## arrival point to every gate, plus scattered trees and rocks kept off the
## roads and away from the gates. Layout is read from the parent scene on
## _ready (PlayerSpawn + every Gate sibling), so moving an entrance in
## overworld.tscn moves its road with it. Deterministic (hashed, no RNG).
## #391 (Daniel, 2026-11-09: "trees block everything, enemies can pathfind
## around trees, all trees collide"): every decor TREE is now solid - its
## circle marks blocking cells on the area's Terrain grid, so walking,
## dashing, knockback and blinks all stop at trees and grid-wired movers
## (enemies, summons) path around them. Rocks stay walkable decor.
## #407 (Daniel, 2026-11-09: "trees should block projectiles"): each tree's
## drawn circle is also registered on the Terrain grid as an indestructible
## projectile blocker - player, summon and enemy shots all stop at it.
## #419 (Daniel, 2026-11-09: "remove the visible dirt paths leading to
## gates, keep it cosmetic"): the roads are no longer drawn. They are still
## computed (`roads`, `road_distance`) because decor placement keeps trees
## and rocks off them - dropping that would move trees and change collision
## and routes. The arrival clearing and the pad under each gate stay.
## Terrain art pass: the field is drawn from the TerrainArt grass tiles
## (hashed variant per 64 px cell, meadow inside the old darker/lighter
## patches) and each tree crown is a TerrainArt tree sprite sized to its
## collision circle. Layout, collision and blockers are unchanged.

const CENTER := Vector2(576, -150)
## #436 (Daniel, 2026-11-09: "expand the overworld map" - the world itself,
## 2x in each direction, same terrain mix for now): doubled from
## (1200, 1050), quadrupling the explorable area. Gates, spawns and guard
## posts keep their scene positions; the field grows around them. The
## decor/patch grids below derive their extents from RADII so the terrain
## mix covers the whole field at the same density.
const RADII := Vector2(2400, 2100)
const OUTLINE_POINTS := 64
const OUTER_FADE := 160.0

const ARRIVAL_R := 74.0
const DECOR_STEP := 120.0
const ROAD_CLEAR := 70.0
const GATE_CLEAR := 150.0
## #446: decor also keeps this far from every entrance-guard post and patrol
## loop, so a solid tree can never sit on a patrol's beat wherever its gate
## is placed (gates were spread across the field and their guards moved
## with them).
const PATROL_CLEAR := 70.0

const GRASS := Color(0.33, 0.46, 0.26) ## the grass tiles' mean (soft edge band)
const GRASS_DARK := Color(0.13, 0.18, 0.14)
const GRASS_LIGHT := Color(0.19, 0.26, 0.19)
const ROAD := Color(0.31, 0.27, 0.21)
const ROAD_EDGE_COLOR := Color(0.23, 0.2, 0.16)
const STONE := Color(0.33, 0.35, 0.38)
const STONE_DARK := Color(0.22, 0.24, 0.27)
const TREE := Color(0.1, 0.2, 0.12)
const TREE_LIGHT := Color(0.15, 0.28, 0.16)
const SHADOW := Color(0.04, 0.06, 0.05)
## #418: absolute z of the tree crowns - above characters (0), below
## damage numbers (5).
const CANOPY_Z := 3

var outline: PackedVector2Array
var spawn := Vector2(576, 480)
var landmarks: Array[Vector2] = []
## Each road is a polyline from the arrival point to one gate.
var roads: Array[PackedVector2Array] = []
## #446: entrance-guard beats (closed loops; a lone post is a 1-point loop).
var patrols: Array[PackedVector2Array] = []
var patches: Array[PackedVector2Array] = []
var patch_colors := PackedColorArray()
## Patch circles (centre, radius) keyed by their 190 px grid slot, for the
## meadow lookup while tiling.
var _patch_slots: Dictionary = {}
## Decor: {"kind": "tree"|"rock", "at": Vector2, "r": float}
var decor: Array[Dictionary] = []
var _canopy: Node2D
## #461: tall-grass patches. Centres/radii are hashed like the decor; the
## patch is the set of Terrain cells whose centre falls inside the circle,
## so what is drawn is exactly what conceals. Cells are in the area's
## Terrain grid (empty when the area has no Terrain sibling).
## {"at": Vector2, "r": float}
var grass_patches: Array[Dictionary] = []
var grass_cells: Array[Vector2i] = []
var _grass_cell_size := 32
var _grass_top: Node2D

## #461 layout (implementer defaults, not approved design): one candidate
## per GRASS_STEP grid point, kept with GRASS_CHANCE, radius 64..128 px, and
## nothing within GRASS_CLEAR of a gate or the arrival point, so gate
## guards and the hub arrival stay in the open.
const GRASS_STEP := 420.0
const GRASS_CHANCE := 0.4
const GRASS_CLEAR := 330.0
const TALL_GRASS := Color(0.2, 0.36, 0.17)
const TALL_GRASS_BLADE := Color(0.32, 0.52, 0.24)
const TALL_GRASS_BLADE_DARK := Color(0.15, 0.3, 0.13)
## Blade tufts draw just under the tree crowns, above characters, so anyone
## in the grass is partly covered by it.
const GRASS_TOP_Z := 2

func _init() -> void:
	z_index = -80
	outline = _blob(0.0)
	_canopy = _make_canopy()
	_grass_top = Node2D.new()
	_grass_top.name = "GrassTop"
	_grass_top.z_as_relative = false
	_grass_top.z_index = GRASS_TOP_Z
	_grass_top.draw.connect(_draw_grass_top)
	add_child(_grass_top)

func _ready() -> void:
	build_from(get_parent())
	queue_redraw()
	_canopy.queue_redraw()
	_grass_top.queue_redraw()

## #418: tree canopies draw on their own child at an absolute z above every
## character (player, enemies, summons all sit at z 0), so anyone standing
## close to a tree is visually covered by its crown instead of being drawn
## on top of it. Damage numbers (z 5) and the HUD (CanvasLayer) stay above.
func _make_canopy() -> Node2D:
	var c := Node2D.new()
	c.name = "Canopy"
	c.z_as_relative = false
	c.z_index = CANOPY_Z
	c.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	c.draw.connect(_draw_canopy.bind(c))
	add_child(c)
	return c

func _draw_canopy(c: Node2D) -> void:
	var row := TerrainArt.row(&"tree_summer") * TerrainArt.OBJ_CELL
	for d in decor:
		if d["kind"] != "tree":
			continue
		var at: Vector2 = d["at"]
		var r: float = d["r"]
		# The sprite's crown is ~70 of its 80 px and centred ~38 px down:
		# scale it so the crown spans the collision circle (slightly over).
		var sz := TerrainArt.OBJ_CELL * (2.0 * r * 1.15) / 70.0
		var col := TerrainArt.variant(Vector2i(int(at.x), int(at.y)), 4)
		c.draw_texture_rect_region(TerrainArt.OBJECTS,
			Rect2(at - Vector2(sz * 0.5, sz * 0.47), Vector2(sz, sz)),
			Rect2(col * TerrainArt.OBJ_CELL, row, TerrainArt.OBJ_CELL, TerrainArt.OBJ_CELL))

## Harness introspection: the node that draws the tree crowns.
func canopy() -> Node2D:
	return _canopy

## Reads the arrival marker and every Gate sibling, then lays out roads and
## decor. Public so harnesses can rebuild from a scene without a tree.
func build_from(area: Node) -> void:
	landmarks.clear()
	roads.clear()
	if area != null:
		var marker := area.get_node_or_null("PlayerSpawn") as Node2D
		if marker != null:
			spawn = marker.position
		for c in area.get_children():
			if c is Gate:
				landmarks.append((c as Node2D).position)
	for i in landmarks.size():
		roads.append(_road(spawn, landmarks[i], i))
	_collect_patrols(area)
	_build_patches()
	_build_decor()
	_plant_tree_collision(area)
	_build_tall_grass()
	_plant_tall_grass(area)

func covers(p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p, outline)

## Distance from p to the nearest road centreline.
func road_distance(p: Vector2) -> float:
	var best := INF
	for road in roads:
		for i in road.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(p, road[i], road[i + 1])
			best = minf(best, p.distance_to(q))
	return best

static func _hash01(x: int, y: int, salt: int) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0

## Irregular field outline: an ellipse with hashed radial wobble, grown by d.
func _blob(d: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in OUTLINE_POINTS:
		var a := TAU * i / OUTLINE_POINTS
		var wob := 1.0 + (_hash01(i, 0, 11) - 0.5) * 0.12
		pts.append(CENTER + Vector2(cos(a) * (RADII.x * wob + d), sin(a) * (RADII.y * wob + d)))
	return pts

## A gently bent road: two hashed sideways offsets along the way.
func _road(from: Vector2, to: Vector2, salt: int) -> PackedVector2Array:
	var pts := PackedVector2Array([from])
	var side := (to - from).orthogonal().normalized()
	var length := from.distance_to(to)
	var bend := clampf(length * 0.12, 0.0, 120.0)
	for k in [1, 2]:
		var t: float = k / 3.0
		var off := (_hash01(salt, k, 7) - 0.5) * 2.0 * bend
		pts.append(from.lerp(to, t) + side * off)
	pts.append(to)
	return pts

func _build_patches() -> void:
	patches.clear()
	patch_colors.clear()
	_patch_slots.clear()
	var n := 0
	var gx_n := int(ceil(RADII.x / 190.0)) + 1
	var gy_n := int(ceil(RADII.y / 190.0)) + 1
	for gx in range(-gx_n, gx_n + 1):
		for gy in range(-gy_n, gy_n + 1):
			var at := CENTER + Vector2(gx * 190.0, gy * 190.0) + Vector2(_hash01(gx, gy, 21) - 0.5, _hash01(gx, gy, 22) - 0.5) * 120.0
			if not covers(at):
				continue
			var r := 50.0 + _hash01(gx, gy, 23) * 70.0
			var poly := PackedVector2Array()
			for i in 10:
				var a := TAU * i / 10.0
				poly.append(at + Vector2(cos(a), sin(a) * 0.7) * r * (0.8 + _hash01(n, i, 24) * 0.4))
			patches.append(poly)
			_patch_slots[Vector2i(gx, gy)] = Vector3(at.x, at.y, r * 0.9)
			patch_colors.append(GRASS_DARK if _hash01(gx, gy, 25) < 0.5 else GRASS_LIGHT)
			n += 1

## #391: every decor tree marks its cells on the area's Terrain grid as
## OBSTACLE (blocking). Not the TREE type: TREE is destroyable under any
## damage, so one stray spell would silently delete a tree's collision
## while its code-drawn circle stays. The tree's own cell is always
## blocked; further cells are blocked when their CENTER falls inside the
## tree circle, keeping the blocked patch at or inside the visual. No
## Terrain sibling (harnesses, older fixtures) = decor stays purely
## visual, the pre-#391 behavior.
func _plant_tree_collision(area: Node) -> void:
	var map := area.get_node_or_null("Terrain") as TerrainMap
	if map == null:
		return
	var cells := {}
	var blockers: Array[Vector3] = []
	for d in decor:
		if d["kind"] != "tree":
			continue
		var at: Vector2 = d["at"]
		var r: float = d["r"]
		# #407: the drawn canopy circle also stops every projectile.
		blockers.append(Vector3(at.x, at.y, r))
		var lo := map.world_to_cell(at - Vector2(r, r))
		var hi := map.world_to_cell(at + Vector2(r, r))
		for cx in range(lo.x, hi.x + 1):
			for cy in range(lo.y, hi.y + 1):
				var cell := Vector2i(cx, cy)
				if map.cell_to_world(cell).distance_to(at) <= r:
					cells[cell] = TerrainTypes.OBSTACLE
		# A small tree near a cell corner has no cell center inside its
		# circle: its own cell is blocked regardless, so no tree is
		# walkable at its own position.
		cells[map.world_to_cell(at)] = TerrainTypes.OBSTACLE
	map.set_cells(cells)
	map.set_projectile_blockers(blockers)

## #461: hashed tall-grass patch centres (deterministic, no RNG). Decor is
## left exactly as it was; grass simply never covers a tree's cells.
func _build_tall_grass() -> void:
	grass_patches.clear()
	var inner := _blob(-120.0)
	var gx_n := int(ceil(RADII.x / GRASS_STEP)) + 1
	var gy_n := int(ceil(RADII.y / GRASS_STEP)) + 1
	for gx in range(-gx_n, gx_n + 1):
		for gy in range(-gy_n, gy_n + 1):
			if _hash01(gx, gy, 41) > GRASS_CHANCE:
				continue
			var at := CENTER + Vector2(gx, gy) * GRASS_STEP + Vector2(_hash01(gx, gy, 42) - 0.5, _hash01(gx, gy, 43) - 0.5) * GRASS_STEP * 0.6
			if not Geometry2D.is_point_in_polygon(at, inner):
				continue
			var r := 64.0 + _hash01(gx, gy, 44) * 64.0
			if at.distance_to(spawn) < GRASS_CLEAR + r:
				continue
			var near_gate := false
			for l in landmarks:
				if at.distance_to(l) < GRASS_CLEAR + r:
					near_gate = true
					break
			if near_gate:
				continue
			grass_patches.append({"at": at, "r": r})

## #461: writes every patch's cells into the area's Terrain grid as
## TALL_GRASS, skipping cells already blocked (tree collision).
func _plant_tall_grass(area: Node) -> void:
	grass_cells.clear()
	var map := area.get_node_or_null("Terrain") as TerrainMap if area != null else null
	if map == null:
		return
	_grass_cell_size = map.cell_size
	var cells := {}
	for p in grass_patches:
		var at: Vector2 = p["at"]
		var r: float = p["r"]
		var lo := map.world_to_cell(at - Vector2(r, r))
		var hi := map.world_to_cell(at + Vector2(r, r))
		for cx in range(lo.x, hi.x + 1):
			for cy in range(lo.y, hi.y + 1):
				var cell := Vector2i(cx, cy)
				if map.tile_type_at_cell(cell) != TerrainTypes.GROUND:
					continue
				# Hashed ragged edge: the outer ring keeps ~60% of its cells.
				var d := map.cell_to_world(cell).distance_to(at)
				if d > r or (d > r * 0.75 and _hash01(cx, cy, 45) > 0.6):
					continue
				cells[cell] = TerrainTypes.TALL_GRASS
	map.set_cells(cells)
	grass_cells.assign(cells.keys())

func _grass_rect(cell: Vector2i) -> Rect2:
	var s := float(_grass_cell_size)
	return Rect2(Vector2(cell) * s, Vector2(s, s))

## Floor layer: the dark mat under each tall-grass cell.
func _draw_grass_floor() -> void:
	for cell in grass_cells:
		draw_rect(_grass_rect(cell).grow(2.0), TALL_GRASS)

## Above characters: a few hashed blades per cell.
func _draw_grass_top() -> void:
	for cell in grass_cells:
		var rect := _grass_rect(cell)
		for k in 4:
			var base := rect.position + Vector2(_hash01(cell.x, cell.y, 50 + k), 0.55 + 0.45 * _hash01(cell.x, cell.y, 60 + k)) * rect.size
			var h := rect.size.y * (0.45 + 0.35 * _hash01(cell.x, cell.y, 70 + k))
			var lean := (_hash01(cell.x, cell.y, 80 + k) - 0.5) * 10.0
			var c := TALL_GRASS_BLADE if k % 2 == 0 else TALL_GRASS_BLADE_DARK
			_grass_top.draw_colored_polygon(PackedVector2Array([
				base + Vector2(-3.5, 0), base + Vector2(lean, -h), base + Vector2(3.5, 0)]), c)

## Harness introspection: the node that draws the blades over characters.
func grass_top() -> Node2D:
	return _grass_top

## #446: reads every EntranceGuards carrier under the area's
## "EntranceGuards" container: each entry's post plus its patrol route.
func _collect_patrols(area: Node) -> void:
	patrols.clear()
	var holder := area.get_node_or_null("EntranceGuards") if area != null else null
	if holder == null:
		return
	for g in holder.get_children():
		if not g is AreaSpawnData:
			continue
		for entry: Dictionary in (g as AreaSpawnData).entries:
			var loop := PackedVector2Array([entry.get("position", Vector2.ZERO)])
			for q in entry.get("route", []):
				loop.append(q)
			patrols.append(loop)

## Distance from p to the nearest entrance-guard post or patrol loop.
func patrol_distance(p: Vector2) -> float:
	var best := INF
	for loop in patrols:
		var n := loop.size()
		if n == 1:
			best = minf(best, p.distance_to(loop[0]))
		for i in n:
			var a := loop[i]
			var b := loop[(i + 1) % n]
			best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best

func _clear_spot(p: Vector2) -> bool:
	if p.distance_to(spawn) < GATE_CLEAR:
		return false
	for l in landmarks:
		if p.distance_to(l) < GATE_CLEAR:
			return false
	if patrol_distance(p) <= PATROL_CLEAR:
		return false
	return road_distance(p) > ROAD_CLEAR

func _build_decor() -> void:
	decor.clear()
	var inner := _blob(-60.0)
	# +1: the outline's radial wobble bulges up to 6% past RADII.
	var gx_n := int(ceil(RADII.x / DECOR_STEP)) + 1
	var gy_n := int(ceil(RADII.y / DECOR_STEP)) + 1
	for gx in range(-gx_n, gx_n + 1):
		for gy in range(-gy_n, gy_n + 1):
			var at := CENTER + Vector2(gx, gy) * DECOR_STEP + Vector2(_hash01(gx, gy, 31) - 0.5, _hash01(gx, gy, 32) - 0.5) * DECOR_STEP * 0.8
			if _hash01(gx, gy, 33) > 0.42:
				continue
			# Keep decor inside the field, clear of the soft edge.
			if not Geometry2D.is_point_in_polygon(at, inner):
				continue
			if not _clear_spot(at):
				continue
			var tree := _hash01(gx, gy, 34) < 0.7
			decor.append({"kind": "tree" if tree else "rock", "at": at,
				"r": (18.0 + _hash01(gx, gy, 35) * 14.0) if tree else (8.0 + _hash01(gx, gy, 35) * 8.0)})

## True when `p` lies in one of the old grass patches (drawn as meadow).
func _in_patch(p: Vector2) -> bool:
	var g := Vector2i(((p - CENTER) / 190.0).round())
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var c: Variant = _patch_slots.get(g + Vector2i(dx, dy))
			if c != null and p.distance_to(Vector2(c.x, c.y)) <= c.z:
				return true
	return false

## The field as TerrainArt floor tiles: every 64 px cell whose centre is
## inside the outline (grown by half a cell so the tiles reach the edge
## band), one of 4 hashed grass variants, meadow inside a patch.
func _draw_grass_tiles() -> void:
	var cell := float(TerrainArt.CELL)
	var grown := _blob(cell * 0.5)
	var lo := Vector2i(((CENTER - RADII * 1.1) / cell).floor())
	var hi := Vector2i(((CENTER + RADII * 1.1) / cell).ceil())
	var grass := TerrainArt.row(&"grass_summer") * TerrainArt.CELL
	var meadow := TerrainArt.row(&"meadow") * TerrainArt.CELL
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var at := Vector2(x + 0.5, y + 0.5) * cell
			if not Geometry2D.is_point_in_polygon(at, grown):
				continue
			var v := TerrainArt.variant(Vector2i(x, y), 5)
			var src_y := meadow if _in_patch(at) else grass
			draw_texture_rect_region(TerrainArt.TILES, Rect2(Vector2(x, y) * cell, Vector2(cell, cell)),
				Rect2(v * TerrainArt.CELL, src_y, TerrainArt.CELL, TerrainArt.CELL))

func _draw_band(inner: PackedVector2Array, outer: PackedVector2Array, ci: Color, co: Color) -> void:
	var n := inner.size()
	for i in n:
		var j := (i + 1) % n
		draw_polygon(PackedVector2Array([inner[i], inner[j], outer[j], outer[i]]), PackedColorArray([ci, ci, co, co]))

func _draw() -> void:
	_draw_band(outline, _blob(OUTER_FADE), Color(GRASS, 0.85), Color(GRASS, 0.0))
	_draw_grass_tiles()
	_draw_grass_floor() # #461
	# #419: roads are no longer drawn (cosmetic only). Their polylines are
	# still laid out in build_from so decor/tree placement - and with it the
	# tree collision on the Terrain grid - stays exactly as before.
	# Arrival clearing: a flagstone ring where the hub passage drops you off.
	draw_circle(spawn, ARRIVAL_R + 6.0, ROAD_EDGE_COLOR)
	draw_circle(spawn, ARRIVAL_R, ROAD)
	draw_arc(spawn, ARRIVAL_R - 12.0, 0.0, TAU, 64, STONE_DARK, 3.0, true)
	for k in 8:
		var d := Vector2.from_angle(TAU * k / 8.0)
		draw_circle(spawn + d * (ARRIVAL_R - 12.0), 5.0, STONE)
	# Landing pad under every gate.
	for l in landmarks:
		draw_circle(l, 54.0, ROAD_EDGE_COLOR)
		draw_circle(l, 48.0, ROAD)
		draw_arc(l, 48.0, 0.0, TAU, 48, STONE_DARK, 3.0, true)
	for d in decor:
		var at: Vector2 = d["at"]
		var r: float = d["r"]
		if d["kind"] == "tree":
			# #418: only the ground shadow stays on the floor layer; the
			# canopy itself is drawn by the Canopy child, above characters.
			draw_circle(at + Vector2(4, r * 0.55), r * 0.9, Color(SHADOW, 0.45))
		else:
			var rock := PackedVector2Array()
			for i in 6:
				var a := TAU * i / 6.0 + 0.3
				rock.append(at + Vector2(cos(a), sin(a) * 0.75) * r)
			draw_colored_polygon(rock, STONE_DARK)
			draw_circle(at + Vector2(-r * 0.2, -r * 0.25), r * 0.45, STONE)
