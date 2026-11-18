extends Node2D
## One connected canopy, one opening. The sheet is seven spatial panels,
## never animation frames. Physics/nav/shot queries use the same wall boxes.
@export var wall_texture: Texture2D
@export var back_texture: Texture2D
const WALL_RECTS: Array[Rect2] = [Rect2(-448,-112,398,108), Rect2(50,-112,398,108), Rect2(-128,-176,256,96)]
func _ready() -> void:
 texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
 z_index = 3
 call_deferred("_mount_wall")
func _mount_wall() -> void:
 var terrain := get_parent().get_node("Terrain") as TerrainMap
 var trunks := terrain.trunk_blockers()
 for rect in WALL_RECTS:
  trunks.append(Rect2(global_position+rect.position,rect.size))
 terrain.set_trunk_blockers(trunks)
 queue_redraw()
func _draw() -> void:
 if back_texture != null:
  draw_texture_rect(back_texture,Rect2(-128,-200,256,128),false)
 if wall_texture != null:
  draw_texture_rect(wall_texture,Rect2(-448,-128,896,128),false)
