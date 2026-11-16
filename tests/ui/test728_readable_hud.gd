extends SceneTree
func _initialize():run.call_deferred()
func run():
 var main:Node=load("res://game/core/main.tscn").instantiate();root.add_child(main);current_scene=main
 await process_frame;await process_frame
 var h:HUD=main.get_node("HUD")
 var s:SpiritMeter=main.get_node("Player/SpiritMeter")
 s.set_process(false)
 var checks:Array[bool]=[h._hp_label.get_theme_font_size("font_size")==24,h._hp_label.get_theme_font("font").resource_path=="res://assets/fonts/m5x7/m5x7.ttf",h._hp_label.get_theme_constant("outline_size")==1]
 checks.append(h._spirit_bar.get_node_or_null("SpiritLabel")==null)
 checks.append(h._spirit_bar.size==Vector2(284,16) and h._spirit_bar.position==Vector2(38,46))
 main.get_node("Player").hp=55;s.add_spirit(s.max_spirit);h._refresh_spirit()
 var fill:=h._spirit_bar.get_theme_stylebox("fill") as StyleBoxTexture
 checks.append(fill.texture==HUD.SPIRIT_READY_TEXTURE and h._spirit_bar.value==1.0)
 s.tick_channel(0.1,true);h._refresh_spirit()
 checks.append(fill.texture==HUD.SPIRIT_READY_TEXTURE and is_equal_approx(h._spirit_bar.value,s.channel_fraction()))
 var label:=h._hp_label
 var text_size:=label.get_theme_font("font").get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.get_theme_font_size("font_size"))
 checks.append(text_size.x<=label.size.x-16 and text_size.y<=label.size.y-4)
 print("[728] ",checks.size()," checks: ",checks)
 var ok:=checks.all(func(value):return value)
 main.queue_free();await process_frame
 quit(0 if ok else 1)
