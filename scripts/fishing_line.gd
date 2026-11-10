class_name FishingLine
extends Node2D
## #464: the Fishy's fishing line + hook (visual only). EnemyBehaviorFishy
## calls set_line() every physics step with world-space end points; the node
## is top_level, so its local space is world space. A slack line sags; a
## taut one (player hooked) is drawn straight and a little brighter. The hook
## is the board's own hook frame (fishy_frames "hook").

const LINE_COLOR := Color(0.9, 0.93, 0.96, 0.85)
const TAUT_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const SAG := 0.06 ## slack sag as a share of the line length
## The packed hook frame is not centred in its cell (cell px).
const HOOK_CELL_CENTER := Vector2(37, 26)

var active := false
var from := Vector2.ZERO
var to := Vector2.ZERO
var taut := false
var _hook: Texture2D = null

func _ready() -> void:
	top_level = true
	global_position = Vector2.ZERO
	z_index = 2
	var sprite := get_parent().get_node_or_null("Sprite") as AnimatedSprite2D
	if sprite != null and sprite.sprite_frames != null and sprite.sprite_frames.has_animation(&"hook"):
		_hook = sprite.sprite_frames.get_frame_texture(&"hook", 0)

func set_line(on: bool, p_from: Vector2, p_to: Vector2, p_taut: bool) -> void:
	if on == active and p_from == from and p_to == to and p_taut == taut:
		return
	active = on
	from = p_from
	to = p_to
	taut = p_taut
	queue_redraw()

func _draw() -> void:
	if not active:
		return
	if taut:
		draw_line(from, to, TAUT_COLOR, 1.5)
	else:
		var mid := (from + to) * 0.5 + Vector2(0, from.distance_to(to) * SAG)
		var pts := PackedVector2Array()
		for i in 13:
			var t := float(i) / 12.0
			pts.append(from.lerp(mid, t).lerp(mid.lerp(to, t), t))
		draw_polyline(pts, LINE_COLOR, 1.0)
	if _hook != null:
		draw_texture(_hook, (to - HOOK_CELL_CENTER).round())
	else:
		draw_circle(to, 3.0, TAUT_COLOR)
