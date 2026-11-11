extends Node2D
class_name BackgroundGrid
## #20: neutral repeating background grid so camera-follow movement is visible.
## Pure background: no gameplay interaction, no assets, drawn in _draw().
## Instance once into the world (main.tscn) BEHIND gameplay nodes.

@export var spacing: int = 64 ## Grid cell size in pixels.
@export var half_extent: int = 4096 ## Grid covers +-half_extent around origin.
@export var line_color: Color = Color(0.35, 0.38, 0.42, 1.0)
@export var major_every: int = 4 ## Every Nth line is a major line.
@export var major_color: Color = Color(0.5, 0.54, 0.6, 1.0)

func _ready() -> void:
	z_index = -100 ## Always behind gameplay.
	queue_redraw()

func _draw() -> void:
	var e := float(half_extent)
	var n := int(half_extent / spacing)
	for i in range(-n, n + 1):
		var c: Color = major_color if i % major_every == 0 else line_color
		var w := 2.0 if i % major_every == 0 else 1.0
		var o := float(i * spacing)
		draw_line(Vector2(o, -e), Vector2(o, e), c, w)
		draw_line(Vector2(-e, o), Vector2(e, o), c, w)
