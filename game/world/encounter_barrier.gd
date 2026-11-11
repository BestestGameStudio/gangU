class_name EncounterBarrier
extends StaticBody2D
## #550: shared encounter barrier for boss lairs (#182 D12-style lock-in as
## physical overworld doors) and later defense encounters (#551). A gray stone
## wall segment that blocks passage while locked and disappears when unlocked.
##
## Contract (origin lead, 2026-11-10):
## - Starts UNLOCKED (invisible, no collision). The caller owns placement,
##   lifecycle and when to lock: a barrier never locks on its own, so it can
##   never trap the player without a clearable encounter wired by the caller.
## - set_locked() is logically IMMEDIATE (is_locked() reflects it at once);
##   the visual and the collision rectangle switch together in a physics-safe
##   deferred callback.
## - Sits on the existing terrain/wall physics layer (PhysicsLayers.WORLD,
##   no new bit): walking actors (ACTOR_MASK) and both projectile masks
##   already collide with WORLD, so a locked barrier blocks players, enemies
##   and projectiles exactly like terrain. Mask 0: a static wall scans
##   nothing itself.
## - Encounter-agnostic: no damage, teleport, push, despawn, timer, AI or
##   boss knowledge here; consumer clear/fail policy stays consumer-side.
##   Boss scenes, art, behavior and music are untouched.
## - Visuals use no new assets: a flat gray stone draw in the existing locked
##   portal tint family (exit_portal.gd LOCKED_TINT).

## The wall segment's rectangle, centered on this node's origin.
@export var size := Vector2(96, 24):
	set(value):
		size = value
		_sync_shape()
		queue_redraw()

## Emitted when the barrier transitions from locked to unlocked. Consumers
## (#550 lair wiring, #551 defense encounters) connect here; the barrier
## itself owns no clear/fail policy.
signal unlocked

## Gray stone: the existing locked-portal tint family (exit_portal.gd).
const STONE_FILL := Color(0.4, 0.4, 0.45)

## #615: terrain art id (a TerrainArt autotile wall set, e.g. obstacle_brown)
## drawn instead of the flat gray stand-in. Empty keeps the gray rectangle.
@export var wall_art: StringName = &"":
	set(value):
		wall_art = value
		queue_redraw()

var _locked := false


func _ready() -> void:
	collision_layer = PhysicsLayers.WORLD
	collision_mask = 0
	# Instance-local shape so per-segment sizes never leak between barriers.
	var shape := _shape_node()
	if shape != null and shape.shape != null:
		shape.shape = shape.shape.duplicate()
	_sync_shape()
	# Direct application is safe before the node enters physics.
	_apply_locked_state()


## Logical state changes immediately; visual + collision follow deferred.
func set_locked(locked_state: bool) -> void:
	var was_locked := _locked
	_locked = locked_state
	if was_locked and not _locked:
		unlocked.emit()
	call_deferred("_apply_locked_state")


func is_locked() -> bool:
	return _locked


## Compatibility helpers for consumers wired like exit_portal.gd.
func lock() -> void:
	set_locked(true)


func unlock() -> void:
	set_locked(false)


func _apply_locked_state() -> void:
	var shape := _shape_node()
	if shape != null:
		shape.disabled = not _locked
	visible = _locked


func _shape_node() -> CollisionShape2D:
	return get_node_or_null("CollisionShape2D") as CollisionShape2D


func _sync_shape() -> void:
	var shape := _shape_node()
	if shape != null and shape.shape is RectangleShape2D:
		(shape.shape as RectangleShape2D).size = size


func _draw() -> void:
	if TerrainArt.kind(wall_art) == TerrainArt.Kind.AUTOTILE:
		_draw_wall_art()
		return
	var rect := Rect2(-size * 0.5, size)
	draw_rect(rect, STONE_FILL, true)
	draw_rect(rect, STONE_FILL.darkened(0.4), false, 2.0)

## #615: wall pieces from the terrain autotile atlas, the same art the
## region's own walls use, instead of the flat gray stand-in. The barrier
## is a wall strip: only its two long faces are exposed.
func _draw_wall_art() -> void:
	var horizontal := size.x >= size.y
	var nx := maxi(1, roundi(size.x / float(TerrainArt.CELL)))
	var ny := maxi(1, roundi(size.y / float(TerrainArt.CELL)))
	var piece := Vector2(size.x / nx, size.y / ny)
	var cell_px := float(TerrainArt.CELL)
	for ix in nx:
		for iy in ny:
			var mask := 0
			if horizontal:
				if iy == 0:
					mask |= TerrainArt.N
				if iy == ny - 1:
					mask |= TerrainArt.S
			else:
				if ix == 0:
					mask |= TerrainArt.W
				if ix == nx - 1:
					mask |= TerrainArt.E
			var alt := TerrainArt.variant(Vector2i(ix, iy), 3, 2)
			var src := Rect2(Vector2(mask, TerrainArt.row(wall_art) + alt) * cell_px, Vector2(cell_px, cell_px))
			draw_texture_rect_region(TerrainArt.TILES, Rect2(-size * 0.5 + Vector2(ix, iy) * piece, piece), src)

