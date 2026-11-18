extends Node2D
class_name SmokeCloud
## Area-owned, bounded lightweight smoke. Visual only: no sight/HP/collision rule.
const GROUP := &"smoke_clouds"
const MAX_CLOUDS := 3
const STEP := 0.05
const PUFF_ATLAS: Texture2D = preload("res://assets/sprites/effects/smoke-puff.png")
var lifetime := 14.0 # PLACEHOLDER, not a settled balance choice.
var wind := Vector2.ZERO
var _age := 0.0
var _clock := 0.0
var _puffs: Array[Dictionary] = []
var _footprint := PackedVector2Array()
var _footprint_dirty := true
var update_usec := 0
var update_count := 0
var update_max_usec := 0

static func spawn(area: Node2D, at: Vector2) -> SmokeCloud:
 var owned: Array[SmokeCloud] = []
 for child in area.get_children():
  if child is SmokeCloud and not child.is_queued_for_deletion(): owned.append(child)
 if owned.size() >= MAX_CLOUDS:
  owned[0].hide()
  owned[0].set_physics_process(false)
  owned[0].queue_free()
 var cloud := SmokeCloud.new()
 area.add_child(cloud)
 cloud.global_position = at
 return cloud

## Called with an actual post-collision swept path, not per-frame overlaps.
static func trace(tree: SceneTree, a: Vector2, b: Vector2, radius: float, heat := false) -> void:
 for cloud in tree.get_nodes_in_group(GROUP):
  if cloud.is_visible_in_tree() and not cloud.is_queued_for_deletion():
   cloud.apply_segment(a,b,radius,heat)

func _ready() -> void:
 add_to_group(GROUP)
 z_index = 30
 texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
 var unlit := CanvasItemMaterial.new()
 unlit.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
 material = unlit
 for y in range(-3,4):
  for x in range(-4,5):
   var index := x+11*y
   var p := Vector2(x*48.0+sin(index*7.3)*11.0,y*44.0+cos(index*5.1)*10.0)
   if (p/Vector2(230,170)).length() > 1.0: continue
   _puffs.append({"p":p,"r":34.0+fposmod(index*7.1,10.0),"v":Vector2(sin(index)*4,-3)})

func _physics_process(dt: float) -> void:
 _age += dt
 if _age >= lifetime:
  queue_free()
  return
 _clock += dt
 if _clock < STEP: return
 # No catch-up spiral on a slow browser.
 _clock = fmod(_clock,STEP)
 var started := Time.get_ticks_usec()
 for puff in _puffs:
  puff.p += (puff.v+wind)*STEP
  puff.r = maxf(0.0,puff.r-0.06)
 _footprint_dirty = true
 modulate.a = minf(1.0,(lifetime-_age)/2.0)
 queue_redraw()
 var elapsed := Time.get_ticks_usec()-started
 update_usec += elapsed
 update_max_usec = maxi(update_max_usec,elapsed)
 update_count += 1

## World-space inputs. Swept puffs are shrunk and pushed; this is NOT a fluid grid.
func apply_segment(a: Vector2, b: Vector2, radius: float, heat := false) -> void:
 _footprint_dirty = true
 a = to_local(a)
 b = to_local(b)
 for puff in _puffs:
  if puff.r < 5.0: continue
  var near := Geometry2D.get_closest_point_to_segment(puff.p,a,b)
  if near.distance_to(puff.p) < radius+puff.r*0.55:
   puff.r = maxf(0.0,puff.r-(24.0 if heat else 15.0))
   puff.v = (puff.v+(puff.p-near).normalized()*35.0).limit_length(120.0)
 queue_redraw()

func apply_wind(velocity: Vector2) -> void:
 wind = velocity.limit_length(120.0)

func apply_heat(at: Vector2, radius: float) -> void:
 apply_segment(at,at,radius,true)

func apply_blast(at: Vector2, radius: float) -> void:
 apply_segment(at,at,radius)
 for puff in _puffs:
  puff.v = (puff.v+(to_global(puff.p)-at).normalized()*60.0).limit_length(120.0)

func _draw() -> void:
 var frame := int(_age/0.22)%4
 for i in range(_puffs.size()-1,-1,-1):
  var puff: Dictionary = _puffs[i]
  if puff.r < 5.0: continue
  draw_texture_rect_region(PUFF_ATLAS,Rect2(puff.p-Vector2.ONE*puff.r,Vector2.ONE*puff.r*2.0),Rect2(frame*64,0,64,64))

func has_smoke() -> bool:
 if is_queued_for_deletion() or _age >= lifetime: return false
 for puff in _puffs:
  if puff.r >= 5.0:return true
 return false

func contains_smoke(at: Vector2) -> bool:
 var local := to_local(at)
 for puff in _puffs:
  if puff.r >= 5.0 and local.distance_to(puff.p) <= puff.r*0.8:return true
 return false

## Squad engagement footprint: convex envelope of surviving puff extents.
## This bridges interior visual gaps without filling gaps between separate clouds.
## Projectile interaction and exact-puff containment remain unchanged.
func contains_footprint(at: Vector2) -> bool:
 if not has_smoke(): return false
 if _footprint_dirty:
  var points := PackedVector2Array()
  for puff in _puffs:
   if puff.r < 5.0: continue
   for i in 8:
    points.append(puff.p+Vector2.from_angle(float(i)*TAU/8.0)*puff.r)
  _footprint = Geometry2D.convex_hull(points) if not points.is_empty() else PackedVector2Array()
  _footprint_dirty = false
 return _footprint.size() >= 3 and Geometry2D.is_point_in_polygon(to_local(at),_footprint)

func interior_point(index: int) -> Vector2:
 var live: Array[Vector2] = []
 for puff in _puffs:
  if puff.r >= 5.0:live.append(puff.p)
 if live.is_empty():return global_position
 return to_global(live[(index*11+int(live.size()/2))%live.size()])
