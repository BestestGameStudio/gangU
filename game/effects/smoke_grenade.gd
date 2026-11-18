extends Node2D
class_name SmokeGrenade
## Area-owned visual lob. Emits once when its cloud is in the tree.
signal landed(cloud: SmokeCloud)
var start := Vector2.ZERO
var target := Vector2.ZERO
var _time := 0.0
var _landed := false
static func launch(area: Node2D, from: Vector2, to: Vector2) -> SmokeGrenade:
 var grenade := SmokeGrenade.new()
 grenade.start = from
 grenade.target = from+(to-from).limit_length(360.0)
 area.add_child(grenade)
 grenade.global_position = from
 return grenade
func _physics_process(dt: float) -> void:
 if _landed: return
 _time += dt
 var f := minf(_time/0.6,1.0)
 global_position = start.lerp(target,f)+Vector2(0,-sin(f*PI)*72.0)
 queue_redraw()
 if f >= 1.0:
  _landed = true
  call_deferred("_land")
func _land() -> void:
 if not is_inside_tree() or not get_parent() is Node2D: return
 var cloud := SmokeCloud.spawn(get_parent(),target)
 landed.emit(cloud)
 queue_free()
func _draw() -> void:
 # Reuse approved SpriteU puff art for the small lob placeholder too.
 draw_texture_rect_region(SmokeCloud.PUFF_ATLAS,Rect2(-7,-7,14,14),Rect2(0,0,64,64))
