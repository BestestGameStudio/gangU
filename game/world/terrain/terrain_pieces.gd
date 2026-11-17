class_name TerrainPieces
extends RefCounted
## Painted terrain pieces (trees, pines, bushes, pillars, boulders and
## tuft / flower / pebble clusters) placed off the grid on top of the
## dual-grid ground. Baked by tools/sprites/draw_terrain_pieces.py into two
## atlases with one layout: BASE draws under characters (trunks, shadows,
## ground clutter), TOP above them at the canopy z (crowns, bushes, pillars).
## Each 48x64 art-px cell has its foot (trunk base / ground contact) at FOOT.

enum Kind { TREE, PINE, BUSH, PILLAR, BOULDER, TUFTS, FLOWERS, PEBBLES }

const BASE: Texture2D = preload("res://assets/sprites/terrain/terrain_pieces_base.png")
const TOP: Texture2D = preload("res://assets/sprites/terrain/terrain_pieces_top.png")
const CELL := Vector2(48, 64)
const FOOT := Vector2(24, 56)
const VARIANTS := 8
## World px per art px (the same pixel size as the landscape sample).
const ART_SCALE := 2.0
## #771 trunk rule: collision is a small box at the trunk base, never the crown.
const TRUNK_SIZE := Vector2(8, 6)

static func src(kind: int, variant: int) -> Rect2:
	return Rect2(Vector2(variant, kind) * CELL, CELL)

## World rect of a piece whose foot is at `foot`. `flip` mirrors it; only
## flip unlit clutter (tufts, flowers, pebbles), lit pieces keep the light
## coming from the upper left.
static func dest(foot: Vector2, flip := false) -> Rect2:
	var size := CELL * ART_SCALE
	var r := Rect2(foot - FOOT * ART_SCALE, size)
	if flip:
		r.position.x += size.x
		r.size.x = -size.x
	return r

static func draw(ci: CanvasItem, top: bool, kind: int, variant: int, foot: Vector2, flip := false) -> void:
	ci.draw_texture_rect_region(TOP if top else BASE, dest(foot, flip), src(kind, variant))

static func trunk_rect(foot: Vector2) -> Rect2:
	return Rect2(foot - Vector2(TRUNK_SIZE.x * 0.5, TRUNK_SIZE.y), TRUNK_SIZE)

## Variant 0..7 whose painted size best fits `t` in 0..1, with a hashed
## +-1 step so equal sizes do not all share one sprite.
static func sized_variant(t: float, hash01: float) -> int:
	var v := roundi(clampf(t, 0.0, 1.0) * (VARIANTS - 1)) + (int(hash01 * 3.0) - 1)
	return clampi(v, 0, VARIANTS - 1)
