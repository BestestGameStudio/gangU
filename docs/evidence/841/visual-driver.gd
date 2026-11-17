extends SceneTree
func _initialize(): run.call_deferred()
func run():
 root.size=Vector2i(1152,648)
 var m=load('res://game/core/main.tscn').instantiate();root.add_child(m);current_scene=m
 await process_frame
 m.area_loader.enter_overworld()
 await process_frame
 m.area_loader._load_hub()
 await process_frame
 m.area_loader.enter_overworld()
 await process_frame
 m.get_node('Player').set_physics_process(false)
 var label:=Label.new();label.text='Cached overworld return - dormant arena';label.position=Vector2(24,135);label.add_theme_font_size_override('font_size',22)
 var overlay:=CanvasLayer.new();overlay.layer=99;root.add_child(overlay);overlay.add_child(label)
 print('841 return immediate ui_visible=',m.area_loader.current_area.get_node('DesertStatueArena')._ui.visible)
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png('/downloads/841-'+OS.get_environment('CASE')+'.png')
 for i in 18: await process_frame
 print('841 visual ui_visible=',m.area_loader.current_area.get_node('DesertStatueArena')._ui.visible)
 quit()
