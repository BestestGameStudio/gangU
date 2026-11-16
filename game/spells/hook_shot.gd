class_name HookShot
extends Projectile
## Shared sweep geometry, but a separate no-damage/no-terrain-destruction dispatch.
signal resolved(count: int)
var destination := Vector2.ZERO
var _resolved := false

func prepare_shape() -> void:
 var dart := Polygon2D.new(); dart.name = "Dart"; add_child(dart)
 var visual := Polygon2D.new(); visual.name = "Visual"; add_child(visual)
 var shape := CollisionShape2D.new(); shape.name = "CollisionShape2D"
 shape.shape = CircleShape2D.new(); add_child(shape)

func _physics_process(delta: float) -> void:
 if not is_instance_valid(source) or (source is Player and source.hp <= 0):
  finish(0); return
 if freeze.is_frozen(): return
 var distance := global_position.distance_to(destination)
 var motion := global_position.direction_to(destination) * minf(distance, spell.projectile_speed * delta)
 var before := global_position
 _sweep_segment(before, motion)
 if is_queued_for_deletion(): return
 global_position += motion
 queue_redraw()
 if global_position.distance_to(destination) < 0.1: _at_destination()

func _sweep_segment(from: Vector2, motion: Vector2) -> void:
 var events := _body_events(from, motion)
 events.append_array(_terrain_events(from, motion))
 if is_instance_valid(_terrain):
  var t := _terrain.projectile_block_t(from, motion)
  if t >= 0.0: events.append({"t": t, "blocker": true})
 events.sort_custom(func(a, b): return a.t < b.t)
 for event in events:
  if event.has("body"):
   var body: Node2D = event.body
   if body == source: continue
   if body is Enemy and spell.hook_magnet_radius > 0.0: continue
   global_position = from + motion * float(event.t)
   _on_body_entered(body)
  else:
   global_position = from + motion * float(event.t)
   finish(0)
  if is_queued_for_deletion(): return

func _on_body_entered(body: Node2D) -> void:
 if _resolved or body == source: return
 if body is Enemy and spell.hook_magnet_radius > 0.0: return
 var count := 0
 if body is Enemy and HookReel.begin(get_parent(), body, source, spell) != null: count = 1
 finish(count)

func finish(count: int) -> void:
 if _resolved: return
 _resolved = true
 resolved.emit(count)
 queue_free()

func _draw() -> void:
 if is_instance_valid(source):
  draw_line(to_local(source.global_position), Vector2.ZERO, Color(0.7, 0.8, 0.8), 1.0)

func _at_destination() -> void:
 var candidates: Array[Enemy] = []
 if spell.hook_magnet_radius > 0.0:
  for node in get_tree().get_nodes_in_group("enemies"):
   var enemy := node as Enemy
   if enemy == null or enemy.hp <= 0 or enemy.global_position.distance_to(destination) > spell.hook_magnet_radius: continue
   candidates.append(enemy)
 var group := HookGroupReel.begin(get_parent(), candidates, source, spell)
 finish(group.enemies.size() if group != null else 0)
