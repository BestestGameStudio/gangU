class_name DesertSpearVisual
extends Node2D
## Faces +X like Projectile. The shared projectile owns movement and swept hits.

func _draw() -> void:
	draw_line(Vector2(-60,0),Vector2(-28,0),Color(0.95,0.25,0.15,0.18),6)
	draw_line(Vector2(-42,0),Vector2(-12,0),Color(0.35,0.17,0.12),5)
	draw_line(Vector2(-42,-1),Vector2(-12,-1),Color("d5b075"),2)
	draw_colored_polygon(PackedVector2Array([Vector2(13,0),Vector2(-13,-7),Vector2(-8,0),Vector2(-13,7)]),Color("fff1d7"))
	draw_polyline(PackedVector2Array([Vector2(-13,-7),Vector2(13,0),Vector2(-13,7)]),Color("ac4e40"),2,true)
	draw_colored_polygon(PackedVector2Array([Vector2(-15,-3),Vector2(-30,-9),Vector2(-24,0),Vector2(-31,7),Vector2(-14,3)]),Color("cb443e"))
