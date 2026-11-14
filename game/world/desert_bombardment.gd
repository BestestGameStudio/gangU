class_name DesertBombardment
extends Node2D
## Phase-two arena hazard. A horizontal bombardment front advances from the
## south wall toward the north wall, leaving a shrinking safe cap around the boss.

signal bombardment_due

@export var arena_radius := 500.0
@export var damage := 12
## Base delay between bombardment pulses. Pulses become more frequent as the
## safe area shrinks.
@export var interval := 2.0
@export var shrink_duration := 45.0
@export var final_interval_scale := 0.35

var progress := 0.0
var safe_radius := 0.0
var active := false
var _elapsed := 0.0
var _until_bombardment := 0.0


func start(radius: float) -> void:
	arena_radius = maxf(radius, 1.0)
	progress = 0.0
	_elapsed = 0.0
	_until_bombardment = maxf(interval, 0.1)
	active = true
	_update_geometry()
	queue_redraw()


func advance(delta: float) -> void:
	if not active or delta <= 0.0:
		return
	_elapsed += delta
	progress = clampf(_elapsed / maxf(shrink_duration, 0.1), 0.0, 1.0)
	_update_geometry()
	_until_bombardment -= delta
	while _until_bombardment <= 0.0:
		bombardment_due.emit()
		_until_bombardment += maxf(interval * lerpf(1.0, final_interval_scale, progress), 0.2)
	queue_redraw()


## The safe region is the part of the arena north (above) the moving front.
func is_safe(world_position: Vector2, arena_center: Vector2) -> bool:
	var local_position := world_position - arena_center
	if local_position.length_squared() > arena_radius * arena_radius:
		return false
	return local_position.y <= _boundary_y() + 0.001


func _boundary_y() -> float:
	return arena_radius - 2.0 * arena_radius * progress


func _update_geometry() -> void:
	var y := _boundary_y()
	safe_radius = sqrt(maxf(arena_radius * arena_radius - y * y, 0.0))


func _draw() -> void:
	if not active:
		return
	# A subtle wash marks the bombardment zone; red streaks make it read as
	# actively dangerous without obscuring the arena or its combatants.
	draw_circle(Vector2.ZERO, arena_radius, Color(0.68, 0.12, 0.07, 0.12))
	_draw_safe_cap()
	_draw_rain()
	var y := _boundary_y()
	if progress < 1.0:
		var half_width := sqrt(maxf(arena_radius * arena_radius - y * y, 0.0))
		draw_line(Vector2(-half_width, y), Vector2(half_width, y), Color("ffe08a"), 5.0, true)
		draw_line(Vector2(-half_width, y + 5.0), Vector2(half_width, y + 5.0), Color(1.0, 0.42, 0.13, 0.72), 2.0, true)


func _draw_safe_cap() -> void:
	if progress <= 0.0:
		draw_circle(Vector2.ZERO, arena_radius, Color(0.35, 0.75, 0.42, 0.15))
		return
	if progress >= 1.0:
		return
	var y := _boundary_y()
	var x := sqrt(maxf(arena_radius * arena_radius - y * y, 0.0))
	var right_angle := atan2(y, x)
	var left_angle := atan2(y, -x)
	var points := PackedVector2Array()
	points.append(Vector2(x, y))
	var steps := 48
	for i in range(1, steps + 1):
		var angle := lerpf(right_angle, left_angle, float(i) / float(steps))
		points.append(Vector2.from_angle(angle) * arena_radius)
	points.append(Vector2(-x, y))
	draw_colored_polygon(points, Color(0.27, 0.82, 0.46, 0.2))


func _draw_rain() -> void:
	if progress <= 0.0:
		return
	# Fixed pseudo-random placement avoids flicker from regenerating particles.
	for i in 72:
		var seed := float(i)
		var angle := seed * 2.399963
		var distance := sqrt((seed + 0.5) / 72.0) * arena_radius
		var point := Vector2.from_angle(angle) * distance
		if point.y <= _boundary_y():
			continue
		var streak := Vector2(-4.0, 13.0)
		draw_line(point, point + streak, Color(1.0, 0.36, 0.16, 0.55), 2.0, true)
		draw_circle(point + streak, 2.5, Color(1.0, 0.67, 0.29, 0.68))
