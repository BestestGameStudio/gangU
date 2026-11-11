class_name RockVisual
extends Node2D
## #443: code-drawn look for the mustache men's thrown rock, fitted through
## Projectile.visual_override (assign before add_child). Visual only: the
## shot still flies the straight Projectile path and hits/blocks exactly as
## a LOBBED projectile. The rock is drawn lifted on a parabola over that
## path (peak ARC_HEIGHT at mid-flight) with a ground shadow underneath, so
## it reads as thrown OVER trees and crates.

const ARC_HEIGHT: float = 34.0 ## PLACEHOLDER: peak lift in px at mid-flight
const SPIN_RATE: float = 9.0 ## rad/s tumble
const ROCK_COLOR := Color(0.62, 0.58, 0.52, 1.0)
const ROCK_DARK := Color(0.38, 0.35, 0.32, 1.0)
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.35)
const ROCK_POLY: PackedVector2Array = [
	Vector2(-6, -2), Vector2(-3, -6), Vector2(3, -6), Vector2(7, -1),
	Vector2(5, 5), Vector2(-1, 7), Vector2(-6, 4)]

var _spin := 0.0

## Current lift in px for flight fraction `t` (0..1): 4h*t*(1-t).
static func lift(t: float) -> float:
	return ARC_HEIGHT * 4.0 * t * (1.0 - t)

func _process(delta: float) -> void:
	_spin += SPIN_RATE * delta
	# Cancel the projectile's flight rotation so "up" is screen up.
	var p := get_parent() as Node2D
	if p != null:
		rotation = -p.rotation
	queue_redraw()

func _draw() -> void:
	var t := 0.0
	var p := get_parent() as Projectile
	if p != null:
		t = p.travel_fraction()
	var h := lift(t)
	# Shadow shrinks as the rock rises.
	var s := 1.0 - 0.4 * (h / ARC_HEIGHT)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s * 0.5))
	draw_circle(Vector2.ZERO, 6.0, SHADOW_COLOR)
	draw_set_transform(Vector2(0.0, -h), _spin, Vector2.ONE)
	draw_colored_polygon(ROCK_POLY, ROCK_COLOR)
	var outline := ROCK_POLY.duplicate()
	outline.append(ROCK_POLY[0])
	draw_polyline(outline, ROCK_DARK, 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
