extends SceneTree
var scene:Node
var pair:HookAnchorPair
var label:Label
var enemy:Enemy
var cycles:=0
func wait_frames(n:int):
 for i in n:await physics_frame
func _initialize():run.call_deferred()
func run():
 scene=load('res://game/core/main.tscn').instantiate();root.add_child(scene);current_scene=scene
 await wait_frames(5)
 var player=scene.get_node('Player') as Player;player.set_physics_process(false);player.position=Vector2(500,440)
 var cam=scene.get_node('FollowCamera');var focus:=Node2D.new();scene.add_child(focus);focus.position=Vector2(500,345);cam.target=focus;cam.position=focus.position;cam.zoom=Vector2(1.1,1.1)
 var layer:=CanvasLayer.new();scene.add_child(layer);label=Label.new();layer.add_child(label);var backdrop:=ColorRect.new();layer.add_child(backdrop);backdrop.position=Vector2(0,540);backdrop.size=Vector2(1152,108);backdrop.color=Color(0.02,0.025,0.035,0.96);layer.move_child(backdrop,0);label.position=Vector2(20,550);label.add_theme_font_size_override('font_size',30)
 var spell=load('res://data/spells/hook_shot_anchor.tres') as Spell
 pair=HookAnchorPair.place(scene,player,spell,Vector2(350,345),Vector2(650,345))
 enemy=load('res://game/enemies/enemy.tscn').instantiate() as Enemy;scene.add_child(enemy);enemy.set_physics_process(false);enemy.position=Vector2(850,600)
 label.text='ROCK ALT: original cast + four returns\nScripted real-game lifecycle'
 await wait_frames(60)
 for cycle in 5:
  enemy.position=Vector2(650,345);enemy.show();label.text='Catch %d/5  |  automatic recasts used: %d/4\nAnchor stays left; lure returns right' % [cycle+1,cycle]
  while is_instance_valid(pair) and not pair.consumed:await physics_frame
  if not is_instance_valid(pair):break
  var reel:=pair.active_reel
  while is_instance_valid(reel) and not reel.arrived:await physics_frame
  if cycle<4:
   label.text='Automatic return %d/4 to cast point\nNo capture until lure returns' % [cycle+1]
   while is_instance_valid(pair) and pair.returning:await physics_frame
   enemy.position=Vector2(850,600);enemy.hide()
   await wait_frames(30)
  else:
   label.text='Five catches: four recasts exhausted\nAnchor + lure removed; no further return'
 await wait_frames(45)
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png('user://lure-recasts-final.png')
 await wait_frames(60);quit()
