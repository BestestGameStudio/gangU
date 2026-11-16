extends SceneTree
func _initialize():run.call_deferred()
func run():
 var main:Node=load("res://game/core/main.tscn").instantiate();root.add_child(main);current_scene=main
 await process_frame;await process_frame
 var h:HUD=main.get_node("HUD")
 var s:SpiritMeter=main.get_node("Player/SpiritMeter")
 s.set_process(false)
 var checks:Array[bool]=[h._hp_label.get_theme_font_size("font_size")==24,h._hp_label.get_theme_font("font").resource_path=="res://assets/fonts/m5x7/m5x7.ttf",h._spirit_label.get_theme_font_size("font_size")==32,h._spirit_bar.size.y>=36,h._hp_label.get_theme_constant("outline_size")==1]
 main.get_node("Player").hp=55;s.add_spirit(s.max_spirit);h._refresh_spirit()
 checks.append(h._spirit_label.text=="HOLD H TO HEAL")
 checks.append(h._spirit_label.get_theme_color("font_color")==Color("10232c"))
 s.tick_channel(0.1,true);h._refresh_spirit()
 checks.append(h._spirit_label.text=="HEALING...")
 checks.append(h._spirit_label.get_theme_color("font_color")==Color.WHITE and h._spirit_label.get_theme_constant("outline_size")==1)
 for label:Label in [h._hp_label,h._spirit_label]:
  var text_size:=label.get_theme_font("font").get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.get_theme_font_size("font_size"))
  checks.append(text_size.x<=label.size.x-16 and text_size.y<=label.size.y-4)
 print("[728] ",checks.size()," checks: ",checks)
 var ok:=checks.all(func(value):return value)
 main.queue_free();await process_frame
 quit(0 if ok else 1)
