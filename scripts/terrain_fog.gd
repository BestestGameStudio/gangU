class_name TerrainFog
extends Node2D
## Fog of war over a bounded cell rect of a TerrainMap. Consumes only the
## map's cell<->world helpers and cell_size.
##
## State is derived from two sets rather than stored per cell, so a cell
## that is visible but unexplored cannot be represented: every update adds
## the visible set into the explored set.

enum State { UNSEEN, SEEN, VISIBLE }

const UNSEEN_COLOR: Color = Color(0.02, 0.02, 0.03, 1.0)
const SEEN_COLOR: Color = Color(0.02, 0.02, 0.03, 0.6)

@export var map: TerrainMap
@export var bounds: Rect2i
@export var vision_radius: int = 4
@export var target: Node2D

var _explored: Dictionary = {} ## Vector2i -> true
var _visible: Dictionary = {} ## Vector2i -> true, always a subset of _explored
var _center: Vector2i
var _has_center := false

func _init() -> void:
	z_index = 1

func _process(_delta: float) -> void:
	if is_instance_valid(target) and map != null:
		update_vision(target.global_position)

func update_vision(world_pos: Vector2) -> void:
	var center := map.world_to_cell(world_pos)
	if _has_center and center == _center:
		return
	_center = center
	_has_center = true
	_visible.clear()
	var r2 := vision_radius * vision_radius
	for dy in range(-vision_radius, vision_radius + 1):
		for dx in range(-vision_radius, vision_radius + 1):
			var cell := center + Vector2i(dx, dy)
			if dx * dx + dy * dy <= r2 and bounds.has_point(cell):
				_visible[cell] = true
				_explored[cell] = true
	queue_redraw()

func state_at_cell(cell: Vector2i) -> State:
	if _visible.has(cell):
		return State.VISIBLE
	if _explored.has(cell):
		return State.SEEN
	return State.UNSEEN

func state_at(world_pos: Vector2) -> State:
	return state_at_cell(map.world_to_cell(world_pos))

func reset() -> void:
	_explored.clear()
	_visible.clear()
	_has_center = false
	queue_redraw()

func _draw() -> void:
	if map == null:
		return
	var size := Vector2(map.cell_size, map.cell_size)
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var cell := Vector2i(x, y)
			var state := state_at_cell(cell)
			if state == State.VISIBLE:
				continue
			var top_left := to_local(map.cell_to_world(cell)) - size * 0.5
			draw_rect(Rect2(top_left, size), UNSEEN_COLOR if state == State.UNSEEN else SEEN_COLOR)
