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
const ROCK_ART := preload("res://assets/sprites/thrown_rock.png") ## 7x7 art px, drawn at 2x
const SHADOW_ART := preload("res://assets/sprites/rock_shadow.png") ## 6x6 art px, drawn at 2x

var _spin := 0.0

## Current lift in px for flight fraction `t` (0..1): 4h*t*(1-t).
static func lift(t: float) -> float:
	return ARC_HEIGHT * 4.0 * t * (1.0 - t)

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

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
	draw_texture_rect(SHADOW_ART, Rect2(-6.0, -6.0, 12.0, 12.0), false, SHADOW_COLOR)
	draw_set_transform(Vector2(0.0, -h), _spin, Vector2.ONE)
	draw_texture_rect(ROCK_ART, Rect2(-7.0, -7.0, 14.0, 14.0), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
