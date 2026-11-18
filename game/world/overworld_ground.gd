extends Node2D
class_name OverworldGround
## Authored island coast with desert to the north, grass/dirt plains in the
## middle, and a beach to the south. Ground types drive both the painted
## floor and exploration map. Existing TerrainPieces supply the decor.
## Trees collide only at their narrow trunks; the ocean blocks movement.

const CENTER := Vector2(576, -150)
## Sampling bounds for the authored coast and surrounding ocean.
const RADII := Vector2(2600, 2100)
const SOUTH_EXTEND := 1200.0

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
var terraces := preload("res://game/world/overworld_terraces.gd").new()
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
## Painted ground clutter on the field (TerrainPieces): tuft, flower and
## pebble clusters plus bushes, clumped by low-frequency noise so they gather
## in patches. Presentation only, never collides.
## {"kind": TerrainPieces.Kind, "v": int, "foot": Vector2, "flip": bool}
var scatter: Array[Dictionary] = []
const SCATTER_STEP := 56.0
## Trees in a conifer patch (this noise above PINE_LEVEL) draw as pines.
const PINE_LEVEL := 0.12
var _pine_noise: FastNoiseLite
var _clump_noise: FastNoiseLite
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
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST ## pieces draw at 2x; keep pixels crisp
	outline = _blob(0.0)
	_canopy = _make_canopy()
	_paint = _make_paint()
	_terrace_art = Node2D.new()
	_terrace_art.name = "TerraceTiles"
	_terrace_art.show_behind_parent = true
	var tile_light := ShaderMaterial.new()
	tile_light.shader = preload("res://game/world/terrain/terrace_tile_light.gdshader")
	_terrace_art.material = tile_light
	_terrace_art.draw.connect(func() -> void: preload("res://game/world/terrain/terrace_tile_art.gd").draw_tiles(_terrace_art,terraces,_view))
	add_child(_terrace_art)
	var black := Node2D.new()
	black.name = "BlackBackdrop"
	black.z_as_relative = false
	black.z_index = -99 ## above BackgroundGrid (-100), below the ground
	black.draw.connect(func() -> void: black.draw_rect(Rect2(-20000, -20000, 40000, 40000), Color.BLACK))
	add_child(black)
	_water = preload("res://game/world/overworld_water.gd").new()
	_water.name = "Water"
	_water.ground = self
	add_child(_water)
	_wildlife = OverworldWildlife.new()
	_wildlife.name = "Wildlife"
	_wildlife.ground = self
	_wildlife.water = _water
	add_child(_wildlife)
	_grass_top = Node2D.new()
	_grass_top.name = "GrassTop"
	_grass_top.z_as_relative = false
	_grass_top.z_index = GRASS_TOP_Z
	_grass_top.draw.connect(_draw_grass_top)
	add_child(_grass_top)

func _ready() -> void:
	build_from(get_parent())
	var fireflies := preload("res://game/world/overworld_fireflies.gd").new()
	fireflies.name = "Fireflies"
	fireflies.ground = self
	add_child(fireflies)
	_update_view()
	queue_redraw()
	_canopy.queue_redraw()
	_grass_top.queue_redraw()
	_water.queue_redraw()
	_terrace_art.queue_redraw()

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
	_water.queue_redraw()
	_terrace_art.queue_redraw()

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

static func _palm_texture(v: int) -> Texture2D:
	if _palm_textures.is_empty():
		for n in PALM_SPRITES:
			_palm_textures.append(load("res://assets/sprites/terrain/palm_%d.png" % (n + 1)) as Texture2D)
	return _palm_textures[v % PALM_SPRITES]

static func _driftwood_texture(v: int) -> Texture2D:
	if _driftwood_textures.is_empty():
		for n in DRIFTWOOD_SPRITES:
			_driftwood_textures.append(load("res://assets/sprites/terrain/driftwood_%d.png" % (n + 1)) as Texture2D)
	return _driftwood_textures[v % DRIFTWOOD_SPRITES]

## #811: same transform as the palm branch of _draw_canopy. The palm art is
## cropped symmetric around the trunk column, so the base sits at bottom
## centre exactly like the trees; the box hugs the narrower palm trunk.
func palm_trunk_rect(d: Dictionary) -> Rect2:
	var at: Vector2 = d["at"]
	var r: float = d["r"]
	var tex := _palm_texture(d["v"])
	var k := (2.0 * r * 1.3) / (tex.get_height() * 0.95)
	var size := tex.get_size() * k
	var foot := at + Vector2(0, r * 0.85)
	var width := 5.0
	var source := Rect2(Vector2(tex.get_width() * 0.5 - width * 0.5, tex.get_height() - 10), Vector2(width, 5))
	return Rect2(foot - Vector2(size.x * 0.5, size.y) + source.position * k, source.size * k)

## #811: hashed beach set dressing on the south sand band - palms on the
## inner band (walkable, trunk collision planted with the trees) and
## driftwood along the waterline, inside and just past the outline.
func _build_beach_decor() -> void:
	beach_decor.clear()
	var step := 90.0
	var grass_rim := _blob(-40.0)       ## stay off the grass/sand blend
	var waterline := _blob(-64.0)       ## in-field driftwood hugs the shore
	var outer_sand := _blob(BEACH_OUT - 24.0)
	var x0 := int(floor((CENTER.x - RADII.x) / step))
	var x1 := int(ceil((CENTER.x + RADII.x) / step))
	var y0 := int(floor((CENTER.y + RADII.y * 0.35) / step))
	var y1 := int(ceil((CENTER.y + RADII.y + SOUTH_EXTEND + BEACH_OUT) / step))
	for gx in range(x0, x1 + 1):
		for gy in range(y0, y1 + 1):
			var at := Vector2(gx, gy) * step + Vector2(_hash01(gx, gy, 71) - 0.5, _hash01(gx, gy, 72) - 0.5) * step * 0.7
			if not _is_south(at):
				continue
			var v := int(_hash01(gx, gy, 75) * 2.0) % 2
			var h := _hash01(gx, gy, 73)
			if covers(at):
				if at.y < _beach_edge_y(at.x) + 80.0 or not Geometry2D.is_point_in_polygon(at, grass_rim):
					continue
				var near_decor := false
				for d in decor:
					if d["at"].distance_to(at) < 80.0:
						near_decor = true
						break
				if near_decor:
					continue
				if h < 0.28 and _clear_spot(at):
					beach_decor.append({"kind": "palm", "at": at,
						"r": 28.0 + _hash01(gx, gy, 74) * 12.0, "v": v})
				elif h < 0.48 and not Geometry2D.is_point_in_polygon(at, waterline):
					beach_decor.append({"kind": "driftwood", "at": at, "r": 1.0, "v": v})
			elif Geometry2D.is_point_in_polygon(at, outer_sand) and h < 0.22:
				# Washed up on the outer sand, inside the blocked band.
				beach_decor.append({"kind": "driftwood", "at": at, "r": 1.0, "v": v})

## Crowns and bushes in view, back to front (by foot y) so a southern crown
## overlaps the one behind it. Collision is only the trunk box at the foot.
func _draw_canopy(c: Node2D) -> void:
	var items: Array[Dictionary] = []
	var reach := _view.grow(TerrainPieces.CELL.y * TerrainPieces.ART_SCALE)
	for d in decor:
		if d["kind"] == "tree" and reach.has_point(d["at"]):
			var piece := tree_piece(d)
			items.append({"kind": piece.x, "v": piece.y, "foot": tree_foot(d), "flip": false})
	for s in scatter:
		if s["kind"] == TerrainPieces.Kind.BUSH and reach.has_point(s["foot"]):
			items.append(s)
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["foot"].y < b["foot"].y)
	for it in items:
		TerrainPieces.draw(c, true, it["kind"], it["v"], it["foot"])
	# #811: beach palms, same bottom-centre anchoring but scaled by height
	# (the art is wider than tall, unlike the trees).
	for d in beach_decor:
		if d["kind"] != "palm":
			continue
		var at: Vector2 = d["at"]
		var r: float = d["r"]
		if not _view.grow(r*3.0).has_point(at): continue
		var tex := _palm_texture(d["v"])
		var k := (2.0 * r * 1.3) / (tex.get_height() * 0.95)
		var size := tex.get_size() * k
		var foot := at + Vector2(0.0, r * 0.85)
		c.draw_texture_rect(tex, Rect2(foot - Vector2(size.x * 0.5, size.y), size), false)

## Trunk base of a decor tree (the piece's foot).
func tree_foot(d: Dictionary) -> Vector2:
	return (d["at"] as Vector2) + Vector2(0.0, float(d["r"]) * 0.85)

## (kind, variant) of a decor tree: pine inside conifer patches, broadleaf
## elsewhere; the variant grows with the decor radius (18..32 px).
func tree_piece(d: Dictionary) -> Vector2i:
	var at: Vector2 = d["at"]
	if _pine_noise == null:
		_pine_noise = FastNoiseLite.new()
		_pine_noise.seed = 451
		_pine_noise.frequency = 1.0 / 700.0
	var kind := TerrainPieces.Kind.PINE if _pine_noise.get_noise_2dv(at) > PINE_LEVEL else TerrainPieces.Kind.TREE
	var t := (float(d["r"]) - 18.0) / 14.0
	return Vector2i(kind, TerrainPieces.sized_variant(t, _hash01(int(at.x), int(at.y), 97)))

## Harness introspection: the node that draws the tree crowns.
func canopy() -> Node2D:
	return _canopy

## Reads the arrival marker and every Gate sibling, then lays out roads and
## decor. Public so harnesses can rebuild from a scene without a tree.
func build_from(area: Node) -> void:
	_lattice_memo.clear()
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
	_build_beach_decor()
	var village := area.get_node_or_null("AbandonedVillage") as AbandonedVillage
	if village != null:
		village.shape_decor(self)
	var desert := area.get_node_or_null("DesertStatueArena")
	if desert != null:
		desert.shape_decor(self)
	_plant_tree_collision(area)
	_plant_border_collision(area)
	var terrain := area.get_node_or_null("Terrain") as TerrainMap
	if terrain != null:
		terrain.set_cells(terraces.walls)
	_build_tall_grass()
	_plant_tall_grass(area)
	_build_scatter(area)
	_build_ground_paint()

func covers(p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p, outline)

## #834: flat map colour for the 64 px cell at `cell` (the M map), taken from
## the same lattice the ground shader paints, so the map matches the world.
## Majority of the four lattice corners around the cell; ties keep the first.
const MAP_COLORS := {
	DualGrid.T.GRASS: Color8(66, 118, 58),
	DualGrid.T.DIRT: Color8(119, 98, 70),
	DualGrid.T.SAND: Color8(214, 182, 122),
	DualGrid.T.SANDSTONE: Color8(219, 180, 128),
	DualGrid.T.STONE: Color8(95, 104, 126),
	DualGrid.T.CLIFF: Color8(94, 71, 64),
	DualGrid.T.COBBLE: Color8(114, 107, 98),
	DualGrid.T.WATER: Color8(38, 88, 124),
}

func map_color(cell: Vector2i) -> Color:
	var sample := terraces.cell_at((Vector2(cell) + Vector2(0.5, 0.5)) * DualGrid.CELL)
	if terraces.stairs.has(sample):
		return Color8(173, 154, 119)
	if terraces.walls.has(sample):
		return MAP_COLORS[DualGrid.T.CLIFF]
	var types: Array[int] = [
		_lattice_type(cell.x, cell.y), _lattice_type(cell.x + 1, cell.y),
		_lattice_type(cell.x, cell.y + 1), _lattice_type(cell.x + 1, cell.y + 1)]
	var best: int = types[0]
	var best_n := 0
	for t in types:
		var n := types.count(t)
		if n > best_n:
			best = t
			best_n = n
	return MAP_COLORS.get(best, WorldMap.FALLBACK_GROUND)

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

## Coast traced from the layout sketch, in a 6 px world scale.
const COAST_SKETCH: Array[Vector2] = [
	Vector2(108, 300), Vector2(120, 265), Vector2(165, 218),
	Vector2(212, 176), Vector2(280, 137), Vector2(350, 104),
	Vector2(430, 86), Vector2(520, 75), Vector2(590, 77),
	Vector2(680, 89), Vector2(760, 106), Vector2(830, 127),
	Vector2(875, 153), Vector2(904, 194), Vector2(917, 237),
	Vector2(911, 292), Vector2(899, 352), Vector2(872, 405),
	Vector2(837, 461), Vector2(804, 520), Vector2(768, 581),
	Vector2(731, 632), Vector2(698, 681), Vector2(665, 732),
	Vector2(637, 780), Vector2(611, 815), Vector2(581, 835),
	Vector2(551, 838), Vector2(498, 833), Vector2(452, 821),
	Vector2(428, 806), Vector2(411, 783), Vector2(390, 739),
	Vector2(369, 688), Vector2(347, 631), Vector2(327, 577),
	Vector2(303, 528), Vector2(273, 495), Vector2(230, 474),
	Vector2(190, 454), Vector2(158, 435), Vector2(143, 399),
	Vector2(125, 350), Vector2(114, 324),
]

func _blob(d: float) -> PackedVector2Array:
	var coast := PackedVector2Array()
	for point in COAST_SKETCH:
		coast.append(Vector2(576, 900) + (point - Vector2(533, 540)) * 6.0)
	if is_zero_approx(d):
		return coast
	var grown := Geometry2D.offset_polygon(coast, d, Geometry2D.JOIN_ROUND)
	return grown[0] if not grown.is_empty() else coast

## The desert's southern edge bows north at the centre of the island.
func _desert_edge_y(x: float) -> float:
	var dx := (x - 400.0) / 2100.0
	return -120.0 + 520.0 * dx * dx + 28.0 * sin(x / 330.0)

func _beach_edge_y(x: float) -> float:
	return 2010.0 + 42.0 * sin(x / 140.0) + 24.0 * sin(x / 71.0)

func _hub_bounds() -> Rect2:
	var hub := get_parent().get_node_or_null("HubServices") if get_parent() != null else null
	return hub.world_bounds() if hub != null else Rect2()

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

## #771: keep tree hitboxes out of the cell store: a full terrain cell
## is wider than a trunk. Village cell/circle footprints stay unchanged.
func _plant_tree_collision(area: Node) -> void:
	var map := area.get_node_or_null("Terrain") as TerrainMap
	if map == null:
		return
	var cells := {}
	var blockers: Array[Vector3] = []
	var trunks: Array[Rect2] = []
	for d in decor:
		if d["kind"] == "tree": trunks.append(tree_trunk_rect(d))
	for d in beach_decor:
		if d["kind"] == "palm": trunks.append(palm_trunk_rect(d))
	map.set_trunk_blockers(trunks)
	var village := area.get_node_or_null("AbandonedVillage") as AbandonedVillage
	if village != null:
		village.plant_footprints(map, cells, blockers) # #546 houses + well
	map.set_cells(cells)
	map.set_projectile_blockers(blockers)

## #771: a small box at the painted trunk base (the piece's foot); the
## canopy never collides.
func tree_trunk_rect(d: Dictionary) -> Rect2:
	return TerrainPieces.trunk_rect(tree_foot(d))

## Ground clutter over the whole field, on hashed grid slots like the decor
## (deterministic, no RNG). Density follows low-frequency noise, so tufts
## and flowers gather in meadows and thin out between them. Kept off
## non-grass ground (pebbles also allowed on dirt), the arrival clearing,
## the village and the desert arena.
func _build_scatter(area: Node) -> void:
	scatter.clear()
	_clump_noise = FastNoiseLite.new()
	_clump_noise.seed = 2027
	_clump_noise.frequency = 1.0 / 520.0
	var inner := _blob(-40.0)
	var village := area.get_node_or_null("AbandonedVillage") as Node2D if area != null else null
	var desert := area.get_node_or_null("DesertStatueArena") as DesertStatueArena if area != null else null
	var gx_n := int(ceil(RADII.x / SCATTER_STEP)) + 1
	var gy_n := int(ceil(RADII.y / SCATTER_STEP)) + 1
	var gy_s := int(ceil((RADII.y + SOUTH_EXTEND) / SCATTER_STEP)) + 1
	for gx in range(-gx_n, gx_n + 1):
		for gy in range(-gy_n, gy_s + 1):
			var at := CENTER + Vector2(gx, gy) * SCATTER_STEP + Vector2(_hash01(gx, gy, 91) - 0.5, _hash01(gx, gy, 92) - 0.5) * SCATTER_STEP
			var dens := smoothstep(-0.25, 0.45, _clump_noise.get_noise_2dv(at))
			var roll := _hash01(gx, gy, 93)
			var kind := -1
			var edge := 0.03 + 0.42 * dens
			if roll < edge:
				kind = TerrainPieces.Kind.TUFTS
			elif roll < edge + 0.14 * dens * dens:
				kind = TerrainPieces.Kind.FLOWERS
			elif roll < edge + 0.14 * dens * dens + 0.025:
				kind = TerrainPieces.Kind.PEBBLES
			elif roll < edge + 0.14 * dens * dens + 0.025 + 0.03 * dens:
				kind = TerrainPieces.Kind.BUSH
			if kind < 0 or not Geometry2D.is_point_in_polygon(at, inner):
				continue
			if _hub_bounds().grow(100.0).has_point(at) or terraces.clear_ground.has(terraces.cell_at(at)):
				continue
			if at.distance_to(spawn) < ARRIVAL_STONE_R + 48.0:
				continue
			if village != null and at.distance_to(village.position) < 470.0:
				continue
			if desert != null and desert.contains_footprint(at, 48.0):
				continue
			var ground := _lattice_type(roundi(at.x / 64.0), roundi(at.y / 64.0))
			if ground != DualGrid.T.GRASS and not (kind == TerrainPieces.Kind.PEBBLES and ground == DualGrid.T.DIRT):
				continue
			var flip := kind != TerrainPieces.Kind.BUSH and _hash01(gx, gy, 95) < 0.5
			scatter.append({"kind": kind, "v": int(_hash01(gx, gy, 94) * TerrainPieces.VARIANTS) % TerrainPieces.VARIANTS,
				"foot": at, "flip": flip})

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
			if at.y < _desert_edge_y(at.x) + r or at.y + r > _beach_edge_y(at.x) or _hub_bounds().grow(r).has_point(at):
				continue
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
				if terraces.clear_ground.has(cell) or map.tile_type_at_cell(cell) != TerrainTypes.GROUND:
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
## Runtime 240x48 atlas of the five blade textures: one shared texture lets
## the back-to-front blades batch into a single draw call instead of one
## texture switch per blade. Same source art, same texels, same draw order.
static var _grass_atlas: Texture2D = null

static func _grass_atlas_texture() -> Texture2D:
	if _grass_atlas == null:
		var img := Image.create(int(GRASS_SPRITE_SIZE) * GRASS_SPRITES, int(GRASS_SPRITE_SIZE), false, Image.FORMAT_RGBA8)
		for n in GRASS_SPRITES:
			var src := (load("res://assets/sprites/terrain/tallgrass_%d.png" % (n + 1)) as Texture2D).get_image()
			img.blit_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), Vector2i(int(GRASS_SPRITE_SIZE) * n, 0))
		_grass_atlas = ImageTexture.create_from_image(img)
	return _grass_atlas

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
			_grass_top.draw_texture_rect_region(_grass_atlas_texture(), Rect2(base - Vector2(GRASS_SPRITE_SIZE * 0.5, GRASS_SPRITE_SIZE - 4.0), Vector2(GRASS_SPRITE_SIZE, GRASS_SPRITE_SIZE)), Rect2(GRASS_SPRITE_SIZE * k, 0, GRASS_SPRITE_SIZE, GRASS_SPRITE_SIZE))

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
	if _hub_bounds().grow(100.0).has_point(p) or terraces.clear_ground.has(terraces.cell_at(p)):
		return false
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
			if at.y < _desert_edge_y(at.x) + 100.0 or at.y > _beach_edge_y(at.x) - 100.0:
				continue
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

## The 64 px ground lattice feeds the floor shader and animated water.
const ARRIVAL_STONE_R := 88.0
const GATE_PAD_R := 76.0
## Cells past the outline that the border covers (drawn) and blocks (collision).
## #820 (Mitra: "we shouldn't be able to float"): the blocked band used to end
## 192 past the outline, but the rock and water run ~290 past it, so the
## strip beyond was walkable void. It now reaches past the whole cliff band
## and the first stretch of ocean.
const BORDER_BLOCKED := 640.0
## #820 (Mitra: "the collider should sit on the edge of the water"): on the
## south beach the block starts at the waterline, not at the outline.
const BEACH_WALK_OUT := 112.0
## #811 (Mitra, 2026-11-16: "extend the cliff so the cliff wall shows from
## front-facing views, then blend into water ... the bottom becomes a beach
## so water is the barrier"): the world edge in lattice terms. North/east/
## west: the cliff wall reaches CLIFF_BAND past the outline, then ocean.
## South: a sand beach runs BEACH_IN deep inside the outline and BEACH_OUT
## past it, then ocean. Water tiles are drawn (animated) by OverworldWater;
## the blocked band below already ends movement before either waterline.
const CLIFF_BAND := 256.0
const BEACH_IN := 192.0
const BEACH_OUT := 128.0
var _beach_outer := PackedVector2Array()
var _cliff_rim := PackedVector2Array()
## Beach set dressing on the south sand: {"kind": "palm"|"driftwood",
## "at": Vector2, "r": float, "v": int}. Palms draw on the Canopy and
## collide at the trunk like trees; driftwood lies flat, no collision.
var beach_decor: Array[Dictionary] = []
var _water: OverworldWater
var _wildlife: OverworldWildlife
const PALM_SPRITES := 2
const DRIFTWOOD_SPRITES := 2
static var _palm_textures: Array[Texture2D] = []
static var _driftwood_textures: Array[Texture2D] = []
var _lattice_memo: Dictionary = {}
var _desert_noise: FastNoiseLite

## Downward extrusion exposes cliffs only on the front-facing coast.
func _front_rim() -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p in outline:
		pts.append(p + Vector2(0, 144))
	return pts

## Terrain type at a lattice point (world position = point * 64).
func _lattice_type(x: int, y: int) -> int:
	var key := Vector2i(x, y)
	if _lattice_memo.has(key):
		return _lattice_memo[key]
	var t := _compute_lattice_type(Vector2(x, y) * float(DualGrid.CELL))
	_lattice_memo[key] = t
	return t

## Only the southern tip gets a walkable sand apron into the sea.
func _is_south(p: Vector2) -> bool:
	return p.y > 1700.0

func _compute_lattice_type(p: Vector2) -> int:
	if not covers(p):
		if _is_south(p):
			if _beach_outer.is_empty():
				_beach_outer = _blob(BEACH_OUT)
			return DualGrid.T.SAND if Geometry2D.is_point_in_polygon(p, _beach_outer) else DualGrid.T.WATER
		if _cliff_rim.is_empty():
			_cliff_rim = _front_rim()
		return DualGrid.T.CLIFF if Geometry2D.is_point_in_polygon(p, _cliff_rim) else DualGrid.T.WATER
	if p.y >= _beach_edge_y(p.x):
		return DualGrid.T.SAND
	if p.y > _beach_edge_y(p.x) - 100.0:
		return DualGrid.T.GRASS
	if _hub_bounds().grow(32.0).has_point(p):
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
		# Keep every fight tile solid stone, including the dual-grid's 64px
		# blend footprint beyond the player barrier. Sand drifts only cross
		# the outer collar, never the combat floor or its telegraphs.
		if d < desert.barrier_radius + 96.0:
			return DualGrid.T.SANDSTONE
		if d < r * 1.01 * wob:
			var drift := _desert_noise.get_noise_2dv(p)
			if drift > -0.08 and d < r * (0.95 + drift * 0.18) * wob:
				return DualGrid.T.SANDSTONE
		# Scattered paving on the west approach becomes an unbroken floor.
		if to.x < 0.0 and to.x > -r * 1.15 and absf(to.y) < 80.0:
			if DualGrid._hash01(int(p.x / 64.0), int(p.y / 64.0), 711) > 0.38:
				return DualGrid.T.SANDSTONE
		if d < r * 1.08 * wob:
			return DualGrid.T.SAND
		desert_near = d < r * 1.08 * wob + 220.0
	if p.y < _desert_edge_y(p.x):
		return DualGrid.T.SAND
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

## Set false (and drop _dirt_nodes) once the cobble sheet has a baked dirt rim.
const VILLAGE_DIRT_RING := false
var _cobble_nodes: Dictionary = {}
var _dirt_nodes: Dictionary = {}
var _lane_nodes: Dictionary = {}

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
	for c: Vector2i in (_lane_nodes.keys() if VILLAGE_DIRT_RING else []):
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var n := c + Vector2i(dx, dy)
				if _cobble_nodes.has(n):
					continue
				var ring := maxi(absi(dx), absi(dy))
				var keep := 0.55 if ring == 1 else 0.0
				if _hash01(n.x, n.y, 313) < keep:
					_dirt_nodes[n] = true

## The ground is painted by one shader quad (ground_paint.gdshader), not
## tiles: every lattice type of the field is baked into a tiny R8 texture
## (one texel per 64 px point) that the shader samples at noise-warped
## positions, so boundaries curve instead of stepping along the grid.
## Outside the outline every point is CLIFF (rock face, then void).
const GROUND_SHADER := preload("res://game/world/terrain/ground_paint.gdshader")
var _terrace_art: Node2D
var _paint: Node2D
var _paint_rect := Rect2()

func _make_paint() -> Node2D:
	var p := Node2D.new()
	p.name = "GroundPaint"
	p.show_behind_parent = true ## under the pieces Ground draws itself
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter("cliff_edges", preload("res://assets/sprites/terrain/terrace_ground_edges.png"))
	mat.set_shader_parameter("cliff_materials", preload("res://assets/sprites/terrain/terrace_cliffs.png"))
	p.material = mat
	p.draw.connect(func() -> void: p.draw_rect(_paint_rect, Color.WHITE))
	add_child(p)
	return p

func _build_ground_paint() -> void:
	var pad := Vector2i(8, 8) + Vector2i.ONE * int(ceil(CLIFF_BAND / 64.0)) ## #811: beach and water band reach past the outline
	var lo := Vector2i(((CENTER - RADII * 1.1) / 64.0).floor()) - pad
	var hi := Vector2i(((CENTER + (RADII + Vector2(0, SOUTH_EXTEND)) * 1.1) / 64.0).ceil()) + pad
	var size := hi - lo + Vector2i.ONE
	var img := Image.create(size.x, size.y, false, Image.FORMAT_R8)
	var grown := _blob(CLIFF_BAND)
	for j in size.y:
		for i in size.x:
			var p := lo + Vector2i(i, j)
			var t := DualGrid.T.CLIFF
			if Geometry2D.is_point_in_polygon(Vector2(p) * 64.0, grown):
				t = _lattice_type(p.x, p.y)
				if t == DualGrid.T.WATER:
					t = DualGrid.T.SAND ## sand under the animated water layer
					for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						if _lattice_type(p.x + n.x, p.y + n.y) == DualGrid.T.CLIFF:
							t = DualGrid.T.CLIFF ## carry rock under transparent shore pixels
							break
						if _lattice_type(p.x + n.x, p.y + n.y) == DualGrid.T.GRASS:
							t = DualGrid.T.GRASS ## grass meets the water directly
							break
			img.set_pixel(i, j, Color8(t, 0, 0))
	var mat := _paint.material as ShaderMaterial
	terraces.bake(mat)
	mat.set_shader_parameter("types", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("lattice_origin", Vector2(lo) * 64.0)
	_paint_rect = Rect2(Vector2(lo) * 64.0, Vector2(size - Vector2i.ONE) * 64.0)
	_paint.queue_redraw()

## Block the border band so the playable area ends at the cliff: every
## Terrain cell whose centre lies between the outline and the blocked band
## becomes OBSTACLE (indestructible, like tree collision).
func _plant_border_collision(area: Node) -> void:
	var map := area.get_node_or_null("Terrain") as TerrainMap if area != null else null
	if map == null:
		return
	var band := _blob(BORDER_BLOCKED)
	var beach_walk := _blob(BEACH_WALK_OUT)
	var cells := {}
	var lo := map.world_to_cell(CENTER - (RADII + Vector2(BORDER_BLOCKED, BORDER_BLOCKED)) * 1.1)
	var hi := map.world_to_cell(CENTER + (RADII + Vector2(BORDER_BLOCKED, BORDER_BLOCKED + SOUTH_EXTEND)) * 1.1)
	for cx in range(lo.x, hi.x + 1):
		for cy in range(lo.y, hi.y + 1):
			var at := map.cell_to_world(Vector2i(cx, cy))
			if covers(at) or not Geometry2D.is_point_in_polygon(at, band):
				continue
			if _is_south(at) and Geometry2D.is_point_in_polygon(at, beach_walk):
				continue ## sand between the outline and the waterline stays walkable
			cells[Vector2i(cx, cy)] = TerrainTypes.OBSTACLE
	map.set_cells(cells)

func _draw() -> void:
	_draw_grass_floor() # #461
	# #419: roads are no longer drawn (cosmetic only). Their polylines are
	# still laid out in build_from so decor/tree placement - and with it the
	# tree collision on the Terrain grid - stays exactly as before.
	# The arrival clearing (stone brick) and the dirt pad under every gate are
	# part of the dual-grid field (see _lattice_type).
	# Painted pieces, ground layer (TerrainPieces.BASE): clutter first, then
	# trunks + shadows of trees and the rocks (boulders). #418: crowns and
	# bushes are drawn by the Canopy child, above characters.
	var reach := _view.grow(TerrainPieces.CELL.y * TerrainPieces.ART_SCALE)
	for s in scatter:
		if reach.has_point(s["foot"]):
			TerrainPieces.draw(self, false, s["kind"], s["v"], s["foot"], s["flip"])
	for d in decor:
		var at: Vector2 = d["at"]
		if not reach.has_point(at): continue
		if d["kind"] == "tree":
			var piece := tree_piece(d)
			TerrainPieces.draw(self, false, piece.x, piece.y, tree_foot(d))
		else:
			var v := TerrainPieces.sized_variant((float(d["r"]) - 8.0) / 8.0, _hash01(int(at.x), int(at.y), 98))
			TerrainPieces.draw(self, false, TerrainPieces.Kind.BOULDER, v, at)
	# #811: driftwood lies flat on the sand, bottom-centre anchored, 1:1.
	for d in beach_decor:
		if d["kind"] != "driftwood":
			continue
		var at: Vector2 = d["at"]
		if not _view.grow(64.0).has_point(at): continue
		var tex := _driftwood_texture(d["v"])
		draw_texture(tex, at - Vector2(tex.get_width() * 0.5, tex.get_height() * 0.75))

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
