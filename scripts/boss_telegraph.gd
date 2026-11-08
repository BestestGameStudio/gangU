class_name BossTelegraph
extends Node2D
## #177: code-drawn ground telegraphs for the Mustache Warlord's attacks
## (visual only). A wind-up shows WHERE the hit lands and fills up as the
## attack approaches, so every boss hit is readable and dodgeable:
##   LINE - lunge lane (tracks the player, then locks)
##   RING - spin radius (wind-up fill, then a faint live ring while spinning)
##   CONE - volley fan
## Drawn under the boss (z_index -1 in the scene), in the boss's warrior green.

enum Mode { NONE, LINE, RING, CONE }

const WARN_COLOR: Color = Color(0.72, 1.0, 0.26)
const FILL_ALPHA: float = 0.09
const EDGE_ALPHA: float = 0.55
const PULSE_RATE: float = 18.0
## #173: per-boss telegraph colour (the Head boss uses its crimson).
@export var warn_color: Color = WARN_COLOR

var mode: int = Mode.NONE
var _dir: Vector2 = Vector2.RIGHT
var _length: float = 0.0
var _half_width: float = 0.0
var _radius: float = 0.0
var _spread: float = 0.0
var _duration: float = 1.0
var _t: float = 0.0
var _active: bool = false

func show_line(dir: Vector2, length: float, half_width: float, duration: float) -> void:
	_begin(Mode.LINE, duration)
	_dir = dir.normalized()
	_length = length
	_half_width = half_width

func show_ring(radius: float, duration: float, active: bool = false) -> void:
	_begin(Mode.RING, duration)
	_radius = radius
	_active = active

func show_cone(dir: Vector2, length: float, spread_rad: float, duration: float) -> void:
	_begin(Mode.CONE, duration)
	_dir = dir.normalized()
	_length = length
	_spread = spread_rad

func set_direction(dir: Vector2) -> void:
	if dir.length_squared() > 0.0:
		_dir = dir.normalized()

func clear() -> void:
	mode = Mode.NONE
	_active = false
	queue_redraw()

func _begin(m: int, duration: float) -> void:
	mode = m
	_duration = maxf(duration, 0.01)
	_t = 0.0
	_active = false
	queue_redraw()

func _process(delta: float) -> void:
	if mode == Mode.NONE:
		return
	_t += delta
	queue_redraw()

func _draw() -> void:
	if mode == Mode.NONE:
		return
	var f: float = clampf(_t / _duration, 0.0, 1.0)
	var pulse: float = 0.5 + 0.5 * sin(_t * PULSE_RATE)
	var fill := warn_color
	fill.a = FILL_ALPHA * (0.6 + 0.4 * pulse)
	var edge := warn_color
	edge.a = EDGE_ALPHA * (0.7 + 0.3 * pulse)
	var charge := warn_color
	charge.a = 0.08 + 0.22 * f
	match mode:
		Mode.LINE:
			var n := _dir.orthogonal() * _half_width
			var lane := PackedVector2Array([n, _dir * _length + n, _dir * _length - n, -n])
			draw_colored_polygon(lane, fill)
			if f > 0.02: # a zero-length lane would fail triangulation
				var filled := _dir * _length * f
				draw_colored_polygon(PackedVector2Array([n, filled + n, filled - n, -n]), charge)
			draw_polyline(PackedVector2Array([n, _dir * _length + n, _dir * _length - n, -n, n]), edge, 1.5)
		Mode.RING:
			if _active:
				var live := warn_color
				live.a = 0.10 + 0.08 * pulse
				draw_circle(Vector2.ZERO, _radius, live)
				draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 48, edge, 2.0)
			else:
				draw_circle(Vector2.ZERO, _radius, fill)
				draw_circle(Vector2.ZERO, _radius * f, charge)
				draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 48, edge, 2.0)
		Mode.CONE:
			var pts := PackedVector2Array([Vector2.ZERO])
			var steps := 16
			for i in steps + 1:
				var a: float = -_spread * 0.5 + _spread * float(i) / float(steps)
				pts.append(_dir.rotated(a) * _length)
			draw_colored_polygon(pts, fill)
			var inner := PackedVector2Array([Vector2.ZERO])
			for i in steps + 1:
				var a2: float = -_spread * 0.5 + _spread * float(i) / float(steps)
				inner.append(_dir.rotated(a2) * _length * f)
			if f > 0.02:
				draw_colored_polygon(inner, charge)
			var outline := pts.duplicate()
			outline.append(Vector2.ZERO)
			draw_polyline(outline, edge, 1.5)
