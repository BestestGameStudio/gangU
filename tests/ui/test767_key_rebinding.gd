extends SceneTree
var failures := 0
const PATH := "user://test767-settings.cfg"
func check(ok: bool, label: String) -> void:
 print('[767] ',label,' ',ok)
 if not ok:failures+=1
func key(code: Key) -> InputEventKey:
 var e:=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=true;return e
func _initialize():run.call_deferred()
func run():
 var cfg:=ConfigFile.new();cfg.set_value('audio','master_volume',0.42);cfg.save(PATH)
 var panel:=SettingsPanel.new();panel.settings_path=PATH;root.add_child(panel)
 panel.open()
 check(KeyBindings.action_label('move_up')=='W','default movement')
 check(KeyBindings.action_label('spell_slot_3')=='Q','Q slot default')
 panel.begin_rebind('move_up');panel._input(key(KEY_K))
 check(InputMap.event_is_action(key(KEY_K),'move_up'),'new key works')
 check(not InputMap.event_is_action(key(KEY_W),'move_up'),'old key removed')
 check(is_equal_approx(SettingsPanel.load_master_volume(PATH),0.42),'preserves volume')
 panel.begin_rebind('move_down');panel._input(key(KEY_K))
 check(panel._capture_action=='move_down' and KeyBindings.action_label('move_down')=='S','conflict does not overwrite')
 panel._input(key(KEY_ESCAPE))
 check(panel._capture_action.is_empty() and panel.is_open(),'Esc cancels capture without closing')
 KeyBindings.load_saved(PATH)
 check(InputMap.event_is_action(key(KEY_K),'move_up'),'reload restores')
 panel.begin_rebind('spell_slot_1')
 var mouse:=InputEventMouseButton.new();mouse.button_index=MOUSE_BUTTON_MIDDLE;mouse.pressed=true
 panel._input(mouse)
 check(KeyBindings.action_label('spell_slot_1')=='MMB' and SpellCaster.slot_key_label(0)=='MMB','mouse input and dynamic label')
 panel.begin_rebind('alternate_cast');panel._input(key(KEY_ALT))
 check(InputMap.event_is_action(key(KEY_ALT),'alternate_cast'),'alternate modifier rebind')
 panel.reset_bindings()
 check(KeyBindings.action_label('move_up')=='W' and KeyBindings.action_label('spell_slot_1')=='LMB','reset defaults')
 check(KeyBindings.action_label('alternate_cast')=='Ctrl','reset modifier')
 check(is_equal_approx(SettingsPanel.load_master_volume(PATH),0.42),'reset preserves volume')
 var main=load("res://game/core/main.tscn").instantiate();root.add_child(main)
 await process_frame
 var caster:SpellCaster=main.get_node("Player/SpellCaster")
 check(caster.get_slots()[2]==load("res://data/spells/water_shot.tres"),"new run Water Shot on Q")
 main.queue_free();await process_frame
 DirAccess.remove_absolute(PATH)
 panel.queue_free();await process_frame
 quit(1 if failures else 0)
