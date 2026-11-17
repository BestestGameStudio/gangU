class_name DualGrid
extends RefCounted
## Dual-grid terrain tiles. A terrain type lives on the LATTICE POINTS (the
## 64 px grid corners); each drawn tile sits between four points and picks its
## art from them. Tile (i, j) covers world rect (i*64, j*64, 64, 64) and reads
## TL=(i,j) TR=(i+1,j) BR=(i+1,j+1) BL=(i,j+1).
##
## Sheets are 256x256, 4x4 tiles of 64 px, named foreground_on_background.
## Tile index == bitmask, row-major, bits TL=1 TR=2 BR=4 BL=8, a set bit =
## that corner is the foreground terrain (mask 15 = all foreground, 0 = all
## background; XOR 15 swaps the roles). Variant strips are 512x64, eight full
## tiles, tile 1 = the base; they swap in for a full tile at VARIANT_CHANCE.
## Everything here is deterministic (hashed, no RNG).

enum T { GRASS, DIRT, SAND, SANDSTONE, STONE, CLIFF, COBBLE, WATER }

const CELL := 64
const DIR := "res://assets/sprites/terrain/"
const VARIANT_CHANCE := 0.35
## [foreground, background, sheet name, xor15]. Optional 4th element: when
## true the sheet's mask bits are the BACKGROUND corners (the sheet is
## authored background_on_foreground) and the computed mask is flipped.
const PAIRS: Array = [
	[T.GRASS, T.DIRT, "dualgrid_grass_on_dirt"],
	[T.GRASS, T.SAND, "dualgrid_grass_on_sand"],
	[T.STONE, T.GRASS, "dualgrid_stonebrick_on_grass"],
	[T.SANDSTONE, T.SAND, "dualgrid_sandstone_on_sand"],
	[T.STONE, T.DIRT, "dualgrid_stonebrick_on_dirt"],
	[T.COBBLE, T.GRASS, "dualgrid_cobble_on_grass"],
	[T.COBBLE, T.DIRT, "dualgrid_cobble_on_dirt"],
	# #811: the grass->cliff rim used to be cliffedge_on_void (rocky edge,
	# then black). The widened cliff band draws real rock now, so the rim
	# uses the cliff_on_grass sheet (flipped: its bits are cliff corners).
	[T.GRASS, T.CLIFF, "dualgrid_cliff_on_grass", true],
	[T.CLIFF, T.DIRT, "dualgrid_cliff_on_dirt"],
	[T.CLIFF, T.SAND, "dualgrid_cliff_on_sand"],
	[T.CLIFF, T.STONE, "dualgrid_cliff_on_stonebrick"],
	[T.CLIFF, T.SANDSTONE, "dualgrid_cliff_on_sandstone"],
	# #811: ocean at the world edge. Water pairs sit last so ties keep the
	# older sheets' behaviour; the lattice never lets water touch grass.
	[T.WATER, T.SAND, "dualgrid_water_on_sand"],
	[T.WATER, T.CLIFF, "dualgrid_water_on_cliff"],
]
## Animated sheets: 256x256 frames stacked vertically, one per loop frame.
## `tile`/`_full` shift the source rect down by frame * 256 for these.
const ANIMATED := {
	"dualgrid_water_on_sand": 5,
	"dualgrid_water_on_cliff": 5,
}
const ANIM_FRAME_H := 256
const VARIANT_NAMES := {
	T.GRASS: "dualgrid_variants_grass",
	T.DIRT: "dualgrid_variants_dirt",
	T.SAND: "dualgrid_variants_sand",
	T.SANDSTONE: "dualgrid_variants_sandstone",
	T.STONE: "dualgrid_variants_stonebrick",
	T.COBBLE: "dualgrid_variants_cobble",
}

static var _textures: Dictionary = {}

static func _tex(name: String) -> Texture2D:
	if not _textures.has(name):
		var path := DIR + name + ".png"
		if not ResourceLoader.exists(path) and name == "dualgrid_cobble_on_dirt":
			# Placeholder until the cobble-on-dirt sheet lands.
			path = DIR + "dualgrid_cobble_on_grass.png"
		elif not ResourceLoader.exists(path) and name.contains("cobble"):
			# Placeholder until the cobble sheets land: reuse stonebrick.
			path = DIR + name.replace("cobble", "stonebrick") + ".png"
		_textures[name] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _textures[name]

static func _hash01(x: int, y: int, salt: int) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0

## Texture + source rect for the tile at (i, j) whose corner types are
## [tl, tr, br, bl]. Returns {"tex": Texture2D, "src": Rect2}, or {} when no
## sheet covers the terrain.
static func tile(i: int, j: int, corners: Array, frame: int = 0) -> Dictionary:
	var best := -1
	var best_cover := -1
	var best_mask := 0
	for p in PAIRS.size():
		var fg: int = PAIRS[p][0]
		var bg: int = PAIRS[p][1]
		var cover := 0
		var mask := 0
		for k in 4:
			var t: int = corners[k]
			if t == fg:
				mask |= 1 << k
				cover += 1
			elif t == bg:
				cover += 1
		# Prefer the pair that explains the most corners; ties keep the first.
		if cover > best_cover:
			best = p
			best_cover = cover
			best_mask = mask
	if best >= 0 and PAIRS[best].size() > 3 and PAIRS[best][3]:
		best_mask ^= 15
	if best < 0 or best_cover == 0:
		return {}
	var uniform := true
	for k in 3:
		if corners[k] != corners[k + 1]:
			uniform = false
	if uniform:
		return _full(i, j, corners[0], frame)
	var tex := _tex(PAIRS[best][2])
	if tex == null:
		return {}
	var src := Rect2(Vector2(best_mask % 4, best_mask / 4) * CELL, Vector2(CELL, CELL))
	if ANIMATED.has(PAIRS[best][2]):
		src.position.y += (frame % int(ANIMATED[PAIRS[best][2]])) * ANIM_FRAME_H
	return {"tex": tex, "src": src}

static func _full(i: int, j: int, t: int, frame: int = 0) -> Dictionary:
	if _hash01(i, j, 91) < VARIANT_CHANCE and VARIANT_NAMES.has(t):
		var strip := _tex(VARIANT_NAMES[t])
		if strip != null:
			var v := 1 + int(_hash01(i, j, 92) * 7.0) % 7
			return {"tex": strip, "src": Rect2(Vector2(v, 0) * CELL, Vector2(CELL, CELL))}
	# Foreground sheets first: a uniform tile should show that terrain's own
	# full art (mask 15), not another sheet's all-background cell. #811:
	# this is what turns the old all-CLIFF band from void (cliffedge's
	# background) into drawn cliff wall that runs out to the ocean.
	for fg_first in [true, false]:
		for p in PAIRS.size():
			if fg_first:
				if PAIRS[p][0] != t:
					continue
			elif PAIRS[p][0] == t or PAIRS[p][1] != t:
				continue
			var tex := _tex(PAIRS[p][2])
			if tex == null:
				return {}
			var mask := 15 if PAIRS[p][0] == t else 0
			if PAIRS[p].size() > 3 and PAIRS[p][3]:
				mask ^= 15
			var src := Rect2(Vector2(mask % 4, mask / 4) * CELL, Vector2(CELL, CELL))
			if ANIMATED.has(PAIRS[p][2]):
				src.position.y += (frame % int(ANIMATED[PAIRS[p][2]])) * ANIM_FRAME_H
			return {"tex": tex, "src": src}
	return {}
