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
## #635 (Daniel, WhatsApp 2026-11-12: "extend the map south with grass,
## trees ..."): the field outline reaches this far past the old south edge.
## Only the south half of the outline grows; the north edge and every
## existing decor/meadow/tall-grass slot stay put because the placement
## grids anchor at CENTER and only their southern gy range extends.
const SOUTH_EXTEND := 1200.0
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

## Presentation-only viewport culling. The world, terrain, collisions and
## actor lifetime do not stream. Padding plus cell-bucket updates prevents
## popping while avoiding a redraw for every subpixel of camera movement.
var _view := Rect2(Vector2(-100000,-100000), Vector2(200000,200000))
var _view_bucket := Vector2i(2147483647,2147483647)
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
const TREE_SPRITES := 3
static var _tree_textures: Array[Texture2D] = []
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
	var black := Node2D.new()
	black.name = "BlackBackdrop"
	black.z_as_relative = false
	black.z_index = -99 ## above BackgroundGrid (-100), below the ground
	black.draw.connect(func() -> void: black.draw_rect(Rect2(-20000, -20000, 40000, 40000), Color.BLACK))
	add_child(black)
	_grass_top = Node2D.new()
	_grass_top.name = "GrassTop"
	_grass_top.z_as_relative = false
	_grass_top.z_index = GRASS_TOP_Z
	_grass_top.draw.connect(_draw_grass_top)
	add_child(_grass_top)

func _ready() -> void:
	build_from(get_parent())
	_update_view()
	queue_redraw()
	_canopy.queue_redraw()
	_grass_top.queue_redraw()

func _process(_delta: float) -> void:
	_update_view()

func _update_view() -> void:
	var inverse := get_canvas_transform().affine_inverse()
	var screen := get_viewport_rect().size
	var a := inverse * Vector2.ZERO
	var b := inverse * screen
	var bucket := Vector2i((a / 64.0).floor())
	var next := Rect2(a.min(b), (b-a).abs()).grow(192.0)
	if bucket == _view_bucket and _view.size.distance_to(next.size) < 1.0:
		return
	_view_bucket = bucket
	_view = next
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
	c.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	c.draw.connect(_draw_canopy.bind(c))
	add_child(c)
	return c

func _draw_canopy(c: Node2D) -> void:
	if _tree_textures.is_empty():
		for n in TREE_SPRITES:
			_tree_textures.append(load("res://assets/sprites/terrain/tree_%d.png" % (n + 1)) as Texture2D)
	for d in decor:
		if d["kind"] != "tree":
			continue
		var at: Vector2 = d["at"]
		var r: float = d["r"]
		if not _view.grow(r*3.0).has_point(at): continue
		var tex := _tree_textures[TerrainArt.variant(Vector2i(int(at.x), int(at.y)), 7, TREE_SPRITES)]
		# Bottom-centre anchored: the crown (~90% of the sprite width) spans
		# the collision circle (slightly over), the trunk foot sits just
		# below the circle's centre.
		var k := (2.0 * r * 1.3) / (tex.get_width() * 0.9)
		var size := tex.get_size() * k
		var foot := at + Vector2(0.0, r * 0.85)
		c.draw_texture_rect(tex, Rect2(foot - Vector2(size.x * 0.5, size.y), size), false)

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
			elif c is OverworldRegion:
				landmarks.append((c as OverworldRegion).approach)
	for i in landmarks.size():
		roads.append(_road(spawn, landmarks[i], i))
	_collect_patrols(area)
	_build_patches()
	_build_decor()
	var village := area.get_node_or_null("AbandonedVillage") as AbandonedVillage
	if village != null:
		village.shape_decor(self)
	var desert := area.get_node_or_null("DesertStatueArena")
	if desert != null:
		desert.shape_decor(self)
	_plant_tree_collision(area)
	_plant_border_collision(area)
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
		var wob := 1.0 + 0.027 * (sin(3.0 * a + 1.0) + 0.7 * sin(5.0 * a + 2.0) + 0.5 * sin(9.0 * a))
		# #635: asymmetric south radius - the outline stays a superset of
		# the old ellipse, so no existing slot check changes result.
		var ry := RADII.y + (SOUTH_EXTEND if sin(a) > 0.0 else 0.0)
		pts.append(CENTER + Vector2(cos(a) * (RADII.x * wob + d), sin(a) * (ry * wob + d)))
	return pts

## A gently bent road: two hashed sideways offsets along the way.
func _road(from: Vector2, to: Vector2, salt: int) -> PackedVector2Array:
	var pts := PackedVector2Array([from])
	var side := (to - from).orthogonal().normalized()
	var length := from.distance_to(to)
	var bend := clampf(length * 0.12, 0.0, 120.0)
	for k: int in [1, 2]:
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
	var gy_s := int(ceil((RADII.y + SOUTH_EXTEND) / 190.0)) + 1
	for gx in range(-gx_n, gx_n + 1):
		for gy in range(-gy_n, gy_s + 1):
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
	var village := area.get_node_or_null("AbandonedVillage") as AbandonedVillage
	if village != null:
		village.plant_footprints(map, cells, blockers) # #546 houses + well
	map.set_cells(cells)
	map.set_projectile_blockers(blockers)

## #461: hashed tall-grass patch centres (deterministic, no RNG). Decor is
## left exactly as it was; grass simply never covers a tree's cells.
func _build_tall_grass() -> void:
	grass_patches.clear()
	var inner := _blob(-120.0)
	var gx_n := int(ceil(RADII.x / GRASS_STEP)) + 1
	var gy_n := int(ceil(RADII.y / GRASS_STEP)) + 1
	var gy_s := int(ceil((RADII.y + SOUTH_EXTEND) / GRASS_STEP)) + 1
	for gx in range(-gx_n, gx_n + 1):
		for gy in range(-gy_n, gy_s + 1):
			if _hash01(gx, gy, 41) > GRASS_CHANCE:
				continue
			var at := CENTER + Vector2(gx, gy) * GRASS_STEP + Vector2(_hash01(gx, gy, 42) - 0.5, _hash01(gx, gy, 43) - 0.5) * GRASS_STEP * 0.6
			if not Geometry2D.is_point_in_polygon(at, inner):
				continue
			var r := 64.0 + _hash01(gx, gy, 44) * 64.0
			var village := get_parent().get_node_or_null("AbandonedVillage") as AbandonedVillage if get_parent() != null else null
			if village != null and at.distance_to(village.position) < 550.0 + r:
				continue
			var desert := get_parent().get_node_or_null("DesertStatueArena") as DesertStatueArena
			if desert != null and desert.contains_footprint(at,r+140.0):
				continue
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
	grass_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))

func _grass_rect(cell: Vector2i) -> Rect2:
	var s := float(_grass_cell_size)
	return Rect2(Vector2(cell) * s, Vector2(s, s))

const GRASS_SPRITES := 5
const GRASS_SPRITE_SIZE := 48.0
static var _grass_textures: Array[Texture2D] = []

static func _grass_texture(k: int) -> Texture2D:
	if _grass_textures.is_empty():
		for n in GRASS_SPRITES:
			_grass_textures.append(load("res://assets/sprites/terrain/tallgrass_%d.png" % (n + 1)) as Texture2D)
	return _grass_textures[k]

## Tall grass is placed sprites now: no floor mat, the ground tile shows
## between the tufts (kept so the old draw hook still exists for callers).
func _draw_grass_floor() -> void:
	pass

## Above characters: one tuft sprite per tall-grass cell, bottom-anchored with
## a hashed offset and variant, drawn back to front (grass_cells is y-sorted).
func _draw_grass_top() -> void:
	for cell in grass_cells:
		var rect := _grass_rect(cell)
		if not _view.intersects(rect.grow(GRASS_SPRITE_SIZE)): continue
		for n in 2:
			var k := int(_hash01(cell.x, cell.y, 50 + n) * GRASS_SPRITES) % GRASS_SPRITES
			var jitter := Vector2(_hash01(cell.x, cell.y, 53 + n) - 0.5, _hash01(cell.x, cell.y, 56 + n) - 0.5) * 22.0
			var base := rect.position + Vector2(rect.size.x * 0.5, rect.size.y * (0.4 + 0.5 * n)) + jitter
			_grass_top.draw_texture(_grass_texture(k), base - Vector2(GRASS_SPRITE_SIZE * 0.5, GRASS_SPRITE_SIZE - 4.0))

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
		for entry: SpawnEntry in (g as AreaSpawnData).entries:
			var loop := PackedVector2Array([entry.position])
			loop.append_array(entry.route)
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
	var gy_s := int(ceil((RADII.y + SOUTH_EXTEND) / DECOR_STEP)) + 1
	for gx in range(-gx_n, gx_n + 1):
		for gy in range(-gy_n, gy_s + 1):
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

## Dual-grid terrain (DualGrid): the field's terrain type lives on 64 px
## lattice points, every drawn tile blends the four points around it. Grass
## everywhere inside the outline, a stone-brick clearing at the arrival,
## dirt pads under the gates and in some of the old patch slots, the desert
## arena as sandstone slabs ringed by sand, and a cliff border outside the
## outline (the cliff set, DualGrid.T.CLIFF). Layout, decor and collision are
## unchanged: this is presentation only.
const ARRIVAL_STONE_R := 88.0
const GATE_PAD_R := 76.0
## Cells past the outline that the border covers (drawn) and blocks (collision).
const BORDER_DRAWN := 112.0
const BORDER_BLOCKED := 192.0
var _lattice_memo: Dictionary = {}
var _desert_noise: FastNoiseLite

## Terrain type at a lattice point (world position = point * 64).
func _lattice_type(x: int, y: int) -> int:
	var key := Vector2i(x, y)
	if _lattice_memo.has(key):
		return _lattice_memo[key]
	var t := _compute_lattice_type(Vector2(x, y) * float(DualGrid.CELL))
	_lattice_memo[key] = t
	return t

func _compute_lattice_type(p: Vector2) -> int:
	if not covers(p):
		return DualGrid.T.CLIFF
	# Only grass meets the cliff edge (the edge art is grass over void).
	if _inner_edge.is_empty():
		_inner_edge = _blob(-140.0)
	if not Geometry2D.is_point_in_polygon(p, _inner_edge):
		return DualGrid.T.GRASS
	var parent := get_parent()
	var desert := parent.get_node_or_null("DesertStatueArena") as DesertStatueArena if parent != null else null
	var desert_near := false
	if desert != null:
		var r := desert.arena_radius
		var to := p - desert.position
		var d := to.length()
		var ang := to.angle()
		# Wobbly edge so the desert is not a perfect circle.
		var wob := 1.0 + 0.06 * sin(ang * 3.0 + 1.3) + 0.04 * sin(ang * 7.0 + 0.4)
		if _desert_noise == null:
			_desert_noise = FastNoiseLite.new()
			_desert_noise.seed = 698
			_desert_noise.frequency = 1.0 / 210.0
		if d < r * 0.78 * wob:
			# Sandstone slabs and sand blown across them.
			return DualGrid.T.SANDSTONE if _desert_noise.get_noise_2dv(p) > -0.12 else DualGrid.T.SAND
		if d < r * 1.08 * wob:
			return DualGrid.T.SAND
		desert_near = d < r * 1.08 * wob + 220.0
	# Arrival clearing and the pad under every gate.
	if p.distance_to(spawn) <= ARRIVAL_STONE_R:
		return DualGrid.T.STONE
	# Abandoned village: worn stone paths from a central walk to every door.
	var vil := get_parent().get_node_or_null("AbandonedVillage") if get_parent() != null else null
	if vil != null:
		var q: Vector2 = p - (vil as Node2D).position
		if absf(q.x) < 420.0 and absf(q.y) < 300.0:
			if _cobble_nodes.is_empty():
				_build_cobble_nodes((vil as Node2D).position)
			if _cobble_nodes.has(Vector2i((p / 64.0).round())):
				return DualGrid.T.COBBLE
			if _dirt_nodes.has(Vector2i((p / 64.0).round())):
				return DualGrid.T.DIRT
		# No stray dirt patches around the village.
		if q.length() < 470.0:
			return DualGrid.T.GRASS
	if not desert_near:
		for l in landmarks:
			if p.distance_to(l) <= GATE_PAD_R:
				return DualGrid.T.DIRT
		# Some of the old darker/lighter patch slots become bare dirt.
		if _in_patch(p):
			var g := Vector2i(((p - CENTER) / 190.0).round())
			if _hash01(g.x, g.y, 61) < 0.25 and p.distance_to(spawn) > ARRIVAL_STONE_R + 128.0:
				return DualGrid.T.DIRT
	return DualGrid.T.GRASS

var _cobble_nodes: Dictionary = {}
var _dirt_nodes: Dictionary = {}
var _lane_nodes: Dictionary = {}
var _inner_edge := PackedVector2Array()

## One-tile-wide trails: snap every path polyline onto the 64px lattice and
## fill the corner of each diagonal step so the trail stays connected.
func _build_cobble_nodes(origin: Vector2) -> void:
	var seg_i := 0
	for seg: PackedVector2Array in AbandonedVillage.path_segments():
		seg_i += 1
		var prev := Vector2i(-99999, -99999)
		for k in range(seg.size() - 1):
			var a := seg[k] + origin
			var b := seg[k + 1] + origin
			var n := int(a.distance_to(b) / 8.0) + 1
			for t in n + 1:
				var node := Vector2i((a.lerp(b, float(t) / n) / 64.0).round())
				if node == prev:
					continue
				if prev.x != -99999 and node.x != prev.x and node.y != prev.y:
					_cobble_nodes[Vector2i(node.x, prev.y)] = true
					if seg_i == 1:
						_lane_nodes[Vector2i(node.x, prev.y)] = true
				_cobble_nodes[node] = true
				if seg_i == 1:
					_lane_nodes[node] = true
				prev = node
	# Cobble -> dirt -> grass: a ragged dirt ring around the trail. Every
	# neighbour is dirt except hashed gaps, plus a patchy second ring.
	for c: Vector2i in _lane_nodes.keys():
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var n := c + Vector2i(dx, dy)
				if _cobble_nodes.has(n):
					continue
				var ring := maxi(absi(dx), absi(dy))
				var keep := 0.55 if ring == 1 else 0.0
				if _hash01(n.x, n.y, 313) < keep:
					_dirt_nodes[n] = true

func _draw_dual_grid() -> void:
	var grown := _blob(BORDER_DRAWN)
	var lo := Vector2i(((CENTER - RADII * 1.1) / 64.0).floor()) - Vector2i(8, 8)
	var hi := Vector2i(((CENTER + (RADII + Vector2(0, SOUTH_EXTEND)) * 1.1) / 64.0).ceil()) + Vector2i(8, 8)
	lo = lo.max(Vector2i((_view.position / 64.0).floor()))
	hi = hi.min(Vector2i((_view.end / 64.0).ceil()))
	for j in range(lo.y, hi.y + 1):
		for i in range(lo.x, hi.x + 1):
			if not Geometry2D.is_point_in_polygon(Vector2(i + 0.5, j + 0.5) * 64.0, grown):
				continue
			var tl := (_lattice_type(i, j))
			var tr := (_lattice_type(i + 1, j))
			var br := (_lattice_type(i + 1, j + 1))
			var bl := (_lattice_type(i, j + 1))
			var t := DualGrid.tile(i, j, [tl, tr, br, bl])
			if t.is_empty():
				continue
			draw_texture_rect_region(t["tex"], Rect2(Vector2(i, j) * 64.0, Vector2(64, 64)), t["src"])

## Block the border band so the playable area ends at the cliff: every
## Terrain cell whose centre lies between the outline and the blocked band
## becomes OBSTACLE (indestructible, like tree collision).
func _plant_border_collision(area: Node) -> void:
	var map := area.get_node_or_null("Terrain") as TerrainMap if area != null else null
	if map == null:
		return
	var band := _blob(BORDER_BLOCKED)
	var cells := {}
	var lo := map.world_to_cell(CENTER - (RADII + Vector2(BORDER_BLOCKED, BORDER_BLOCKED)) * 1.1)
	var hi := map.world_to_cell(CENTER + (RADII + Vector2(BORDER_BLOCKED, BORDER_BLOCKED + SOUTH_EXTEND)) * 1.1)
	for cx in range(lo.x, hi.x + 1):
		for cy in range(lo.y, hi.y + 1):
			var at := map.cell_to_world(Vector2i(cx, cy))
			if covers(at) or not Geometry2D.is_point_in_polygon(at, band):
				continue
			cells[Vector2i(cx, cy)] = TerrainTypes.OBSTACLE
	map.set_cells(cells)

func _draw() -> void:
	_draw_dual_grid()
	_draw_grass_floor() # #461
	# #419: roads are no longer drawn (cosmetic only). Their polylines are
	# still laid out in build_from so decor/tree placement - and with it the
	# tree collision on the Terrain grid - stays exactly as before.
	# The arrival clearing (stone brick) and the dirt pad under every gate are
	# part of the dual-grid field (see _lattice_type).
	for d in decor:
		var at: Vector2 = d["at"]
		var r: float = d["r"]
		if not _view.grow(r*2.0).has_point(at): continue
		if d["kind"] == "tree":
			# #418: only the ground shadow stays on the floor layer; the
			# canopy itself is drawn by the Canopy child, above characters.
			pass  # new tree sprites carry their own baked shadow
		else:
			var rock := PackedVector2Array()
			for i in 6:
				var a := TAU * i / 6.0 + 0.3
				rock.append(at + Vector2(cos(a), sin(a) * 0.75) * r)
			draw_colored_polygon(rock, STONE_DARK)
			draw_circle(at + Vector2(-r * 0.2, -r * 0.25), r * 0.45, STONE)

## #614: reserve_regions drops decor trees within a margin wider than a
## region's footprint, but _plant_tree_collision already marked those trees'
## cells OBSTACLE on the shared Terrain and regions only restamp cells inside
## their bounds. Release the cells of every tree about to be removed, so bare
## grass around a dungeon is not an invisible wall. A cell stays blocked when
## a surviving tree still covers it, and region-owned cells are left alone.
func _release_removed_tree_cells(regions: Array[OverworldRegion]) -> void:
	var map := get_parent().get_node_or_null("Terrain") as TerrainMap
	if map == null:
		return
	var kept := {}
	var released := {}
	for d in decor:
		if d["kind"] != "tree":
			continue
		var at: Vector2 = d["at"]
		var r: float = d["r"]
		var removed := false
		for region in regions:
			if region.bounds.grow(r + 48.0).has_point(at):
				removed = true
		var lo := map.world_to_cell(at - Vector2(r, r))
		var hi := map.world_to_cell(at + Vector2(r, r))
		var own := map.world_to_cell(at)
		for cx in range(lo.x, hi.x + 1):
			for cy in range(lo.y, hi.y + 1):
				var cell := Vector2i(cx, cy)
				if cell == own or map.cell_to_world(cell).distance_to(at) <= r:
					if removed:
						released[cell] = true
					else:
						kept[cell] = true
	for cell: Vector2i in released:
		if kept.has(cell) or map.tile_type_at_cell(cell) != TerrainTypes.OBSTACLE:
			continue
		var world := map.cell_to_world(cell)
		var owned := false
		for region in regions:
			if region.bounds.has_point(world):
				owned = true
		if not owned:
			map.clear_cell(cell)

## Region terrain owns its footprint. Delete both visual trees and their
## projectile circles there; replacing only sparse cells leaves ghost trees.
func reserve_regions(regions: Array[OverworldRegion]) -> void:
	_release_removed_tree_cells(regions)
	decor = decor.filter(func(d: Dictionary) -> bool:
		for region in regions:
			if region.bounds.grow(float(d["r"]) + 48.0).has_point(d["at"]):
				return false
		return true)
	var map := get_parent().get_node_or_null("Terrain") as TerrainMap
	if map != null:
		var circles: Array[Vector3] = []
		for d in decor:
			if d["kind"] == "tree":
				var at: Vector2 = d["at"]
				circles.append(Vector3(at.x, at.y, d["r"]))
		map.set_projectile_blockers(circles)
		grass_cells = grass_cells.filter(func(cell: Vector2i) -> bool:
			return map.tile_type_at_cell(cell) == TerrainTypes.TALL_GRASS)
	queue_redraw()
	_canopy.queue_redraw()
	_grass_top.queue_redraw()
