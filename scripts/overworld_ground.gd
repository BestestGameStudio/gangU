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

const CENTER := Vector2(576, -150)
const RADII := Vector2(1200, 1050)
const OUTLINE_POINTS := 64
const OUTER_FADE := 160.0

const ROAD_W := 46.0
const ROAD_EDGE := 4.0
const ARRIVAL_R := 74.0
const DECOR_STEP := 120.0
const ROAD_CLEAR := 70.0
const GATE_CLEAR := 150.0

const GRASS := Color(0.16, 0.22, 0.17)
const GRASS_DARK := Color(0.13, 0.18, 0.14)
const GRASS_LIGHT := Color(0.19, 0.26, 0.19)
const ROAD := Color(0.31, 0.27, 0.21)
const ROAD_EDGE_COLOR := Color(0.23, 0.2, 0.16)
const STONE := Color(0.33, 0.35, 0.38)
const STONE_DARK := Color(0.22, 0.24, 0.27)
const TREE := Color(0.1, 0.2, 0.12)
const TREE_LIGHT := Color(0.15, 0.28, 0.16)
const SHADOW := Color(0.04, 0.06, 0.05)

var outline: PackedVector2Array
var spawn := Vector2(576, 480)
var landmarks: Array[Vector2] = []
## Each road is a polyline from the arrival point to one gate.
var roads: Array[PackedVector2Array] = []
var patches: Array[PackedVector2Array] = []
var patch_colors := PackedColorArray()
## Decor: {"kind": "tree"|"rock", "at": Vector2, "r": float}
var decor: Array[Dictionary] = []

func _init() -> void:
	z_index = -80
	outline = _blob(0.0)

func _ready() -> void:
	build_from(get_parent())
	queue_redraw()

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
	_build_patches()
	_build_decor()
	_plant_tree_collision(area)

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
	var n := 0
	for gx in range(-6, 7):
		for gy in range(-6, 6):
			var at := CENTER + Vector2(gx * 190.0, gy * 190.0) + Vector2(_hash01(gx, gy, 21) - 0.5, _hash01(gx, gy, 22) - 0.5) * 120.0
			if not covers(at):
				continue
			var r := 50.0 + _hash01(gx, gy, 23) * 70.0
			var poly := PackedVector2Array()
			for i in 10:
				var a := TAU * i / 10.0
				poly.append(at + Vector2(cos(a), sin(a) * 0.7) * r * (0.8 + _hash01(n, i, 24) * 0.4))
			patches.append(poly)
			patch_colors.append(GRASS_DARK if _hash01(gx, gy, 25) < 0.5 else GRASS_LIGHT)
			n += 1

## #391: every decor tree marks its cells on the area's Terrain grid as
## OBSTACLE (blocking). Not the TREE type: TREE is destroyable under any
## damage, so one stray spell would silently delete a tree's collision
## while its code-drawn circle stays. A cell is blocked when its CENTER
## falls inside the tree circle, keeping the blocked patch at or inside
## the visual. No Terrain sibling (harnesses, older fixtures) = decor
## stays purely visual, the pre-#391 behavior.
func _plant_tree_collision(area: Node) -> void:
	var map := area.get_node_or_null("Terrain") as TerrainMap
	if map == null:
		return
	var cells := {}
	for d in decor:
		if d["kind"] != "tree":
			continue
		var at: Vector2 = d["at"]
		var r: float = d["r"]
		var lo := map.world_to_cell(at - Vector2(r, r))
		var hi := map.world_to_cell(at + Vector2(r, r))
		for cx in range(lo.x, hi.x + 1):
			for cy in range(lo.y, hi.y + 1):
				var cell := Vector2i(cx, cy)
				if map.cell_to_world(cell).distance_to(at) <= r:
					cells[cell] = TerrainTypes.OBSTACLE
	map.set_cells(cells)

func _clear_spot(p: Vector2) -> bool:
	if p.distance_to(spawn) < GATE_CLEAR:
		return false
	for l in landmarks:
		if p.distance_to(l) < GATE_CLEAR:
			return false
	return road_distance(p) > ROAD_CLEAR

func _build_decor() -> void:
	decor.clear()
	var inner := _blob(-60.0)
	for gx in range(-12, 13):
		for gy in range(-11, 9):
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

func _draw_band(inner: PackedVector2Array, outer: PackedVector2Array, ci: Color, co: Color) -> void:
	var n := inner.size()
	for i in n:
		var j := (i + 1) % n
		draw_polygon(PackedVector2Array([inner[i], inner[j], outer[j], outer[i]]), PackedColorArray([ci, ci, co, co]))

func _draw_road(road: PackedVector2Array, width: float, color: Color) -> void:
	draw_polyline(road, color, width, true)
	for p in road:
		draw_circle(p, width * 0.5, color)

func _draw() -> void:
	_draw_band(outline, _blob(OUTER_FADE), Color(GRASS, 0.85), Color(GRASS, 0.0))
	draw_colored_polygon(outline, GRASS)
	for i in patches.size():
		draw_colored_polygon(patches[i], patch_colors[i])
	for road in roads:
		_draw_road(road, ROAD_W + ROAD_EDGE * 2.0, ROAD_EDGE_COLOR)
	for road in roads:
		_draw_road(road, ROAD_W, ROAD)
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
			draw_circle(at + Vector2(4, r * 0.55), r * 0.9, Color(SHADOW, 0.45))
			draw_circle(at, r, TREE)
			draw_circle(at + Vector2(-r * 0.25, -r * 0.3), r * 0.55, TREE_LIGHT)
		else:
			var rock := PackedVector2Array()
			for i in 6:
				var a := TAU * i / 6.0 + 0.3
				rock.append(at + Vector2(cos(a), sin(a) * 0.75) * r)
			draw_colored_polygon(rock, STONE_DARK)
			draw_circle(at + Vector2(-r * 0.2, -r * 0.25), r * 0.45, STONE)
