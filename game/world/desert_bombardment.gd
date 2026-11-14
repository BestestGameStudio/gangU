class_name DesertBombardment
extends Node2D
## Phase-two bombardment closes inward evenly toward the arena center.

signal bombardment_due

@export var arena_radius := 500.0
@export var damage := 12
## Base delay between bombardment pulses. Pulses become more frequent as the
## safe circle shrinks.
@export var interval := 2.0
@export var shrink_duration := 45.0
@export var final_interval_scale := 0.35
@export var final_safe_radius := 88.0
@export_range(0.0, 1.0) var max_progress := 1.0

var progress := 0.0
var safe_radius := 0.0
var safe_center := Vector2.ZERO
var active := false
var _initial_safe_radius := 0.0
var _elapsed := 0.0
var _until_bombardment := 0.0


## The initial safe circle covers the arena, then contracts toward its center.
func start(radius: float) -> void:
	arena_radius = maxf(radius, 1.0)
	safe_center = Vector2.ZERO
	_initial_safe_radius = arena_radius
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
	progress = clampf(_elapsed / maxf(shrink_duration, 0.1), 0.0, max_progress)
	_update_geometry()
	_until_bombardment -= delta
	while _until_bombardment <= 0.0:
		bombardment_due.emit()
		_until_bombardment += maxf(interval * lerpf(1.0, final_interval_scale, progress), 0.2)
	queue_redraw()


func is_safe(world_position: Vector2, arena_center: Vector2) -> bool:
	var local_position := world_position-arena_center
	return local_position.length() <= arena_radius and local_position.distance_to(safe_center) <= safe_radius


func _update_geometry() -> void:
	safe_radius = lerpf(_initial_safe_radius, final_safe_radius, progress)


func _draw() -> void:
	if not active:
		return
	# The bombardment wash covers the arena, then the clipped green circle shows
	# the portion still protected from the rain.
	draw_circle(Vector2.ZERO, arena_radius, Color(0.68, 0.12, 0.07, 0.12))
	_draw_safe_circle()
	_draw_safe_boundary()
	_draw_rain()


func _draw_safe_circle() -> void:
	draw_circle(safe_center, minf(safe_radius, arena_radius), Color(0.27, 0.82, 0.46, 0.2))


func _draw_safe_boundary() -> void:
	if progress <= 0.0:
		return
	draw_arc(safe_center, minf(safe_radius, arena_radius), 0, TAU, 128, Color("ffe08a"), 5.0, true)


func _draw_rain() -> void:
	if progress <= 0.0:
		return
	# Fixed pseudo-random placement avoids flicker from regenerating particles.
	for i in 96:
		var seed := float(i)
		var angle := seed*2.399963
		var distance := sqrt((seed+0.5)/96.0)*arena_radius
		var point := Vector2.from_angle(angle)*distance
		if point.distance_to(safe_center) <= safe_radius:
			continue
		var streak := Vector2(-4.0, 13.0)
		draw_line(point, point+streak, Color(1.0, 0.36, 0.16, 0.62), 2.0, true)
		draw_circle(point+streak, 2.5, Color(1.0, 0.67, 0.29, 0.72))
