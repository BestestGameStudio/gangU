extends SceneTree
func _initialize():run.call_deferred()
func run():
 root.size=Vector2i(960,540)
 var stage:=Node2D.new();root.add_child(stage);current_scene=stage
 var p=load('res://game/player/player.tscn').instantiate();stage.add_child(p)
 p.collision_layer=0;p.collision_mask=0;p.set_physics_process(false);p.position=Vector2(250,250)
 var camera:=Camera2D.new();camera.position=Vector2(292,230);camera.zoom=Vector2(3,3);stage.add_child(camera)
 var marker:=Line2D.new();marker.points=PackedVector2Array([Vector2(334,225),Vector2(334,275)]);marker.width=0.7;marker.default_color=Color.GREEN;stage.add_child(marker)
 var start:=Line2D.new();start.points=PackedVector2Array([Vector2(250,225),Vector2(250,275)]);start.width=0.7;start.default_color=Color.GRAY;stage.add_child(start)
 var layer:=CanvasLayer.new();root.add_child(layer);var label:=Label.new();label.position=Vector2(25,25);label.add_theme_font_size_override('font_size',22);layer.add_child(label)
 label.text=OS.get_environment('CASE')+' | Actual Player + Spirit Punch cast | expected84px'
 for i in 30:await process_frame
 var caster=p.get_node('SpellCaster');caster.aim_override=Vector2(1000,250);caster._cast_spell(load('res://data/spells/spirit_punch_launch.tres'))
 while p.is_launching():
  await physics_frame
  p._physics_process(1.0/60.0)
 label.text+='\nSettled displacement %.3fpx | green line expected endpoint'%(p.position.x-250.0)
 for i in 90:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png('/downloads/850-'+OS.get_environment('CASE')+'.png')
 stage.queue_free();layer.queue_free();await process_frame;quit()
