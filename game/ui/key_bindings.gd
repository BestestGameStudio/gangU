class_name KeyBindings
extends RefCounted
## #767: physical keys/buttons; existing defaults are explicit so reset and
## scene reload cannot accidentally adopt the previous custom mapping.
const ACTIONS := {
 "move_up": "Move up", "move_down": "Move down", "move_left": "Move left", "move_right": "Move right",
 "dash": "Dash", "spell_slot_1": "Spell slot 1", "spell_slot_2": "Spell slot 2", "spell_slot_3": "Spell slot 3 (Water Shot default)",
 "spell_slot_4": "Spell slot 4", "spell_slot_5": "Spell slot 5", "cast": "Legacy cast", "alternate_cast": "Alternate cast modifier",
 "heal": "Channel heal", "use_consumable": "Use consumable", "equip_panel": "Spell menu", "world_map": "Map"
}
const KEYS := {"move_up":KEY_W,"move_down":KEY_S,"move_left":KEY_A,"move_right":KEY_D,"dash":KEY_SHIFT,"spell_slot_3":KEY_Q,"spell_slot_4":KEY_E,"spell_slot_5":KEY_R,"cast":KEY_SPACE,"alternate_cast":KEY_CTRL,"heal":KEY_H,"use_consumable":KEY_C,"equip_panel":KEY_TAB,"world_map":KEY_M}
const SECTION := "bindings"
static func default_event(action: String) -> InputEvent:
 if action in ["spell_slot_1", "spell_slot_2"]:
  var m := InputEventMouseButton.new();m.button_index = MOUSE_BUTTON_LEFT if action == "spell_slot_1" else MOUSE_BUTTON_RIGHT;return m
 var k := InputEventKey.new();k.physical_keycode = KEYS.get(action, 0);return k
static func normalized(event: InputEvent) -> InputEvent:
 if event is InputEventKey:
  var k := InputEventKey.new();k.physical_keycode = event.physical_keycode if event.physical_keycode else event.keycode;return k
 if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE,MOUSE_BUTTON_XBUTTON1,MOUSE_BUTTON_XBUTTON2]:
  var m := InputEventMouseButton.new();m.button_index=event.button_index;return m
 return null
static func label(event: InputEvent) -> String:
 if event is InputEventMouseButton:
  return {1:"LMB",2:"RMB",3:"MMB",8:"Mouse4",9:"Mouse5"}.get(event.button_index,"Mouse")
 if event is InputEventKey:return OS.get_keycode_string(event.physical_keycode if event.physical_keycode else event.keycode)
 return "Unbound"
static func action_label(action: String) -> String:
 var events := InputMap.action_get_events(action) if InputMap.has_action(action) else []
 return label(events[0]) if not events.is_empty() else "Unbound"
static func assign(action: String, event: InputEvent) -> void:
 if not InputMap.has_action(action):InputMap.add_action(action)
 Input.action_release(action)
 InputMap.action_erase_events(action);InputMap.action_add_event(action,event)
static func conflict(action: String, event: InputEvent) -> String:
 for other: String in ACTIONS:
  if other == action:continue
  for existing: InputEvent in InputMap.action_get_events(other):
   if label(existing) == label(event):return ACTIONS[other]
 return ""
static func load_saved(path: String) -> void:
 var cfg := ConfigFile.new();cfg.load(path)
 for action: String in ACTIONS:
  assign(action,default_event(action))
 for action: String in ACTIONS:
  var raw: Variant=cfg.get_value(SECTION,action,{})
  if not raw is Dictionary:continue
  var ev:InputEvent
  if raw.get("type") == "key" and int(raw.get("code",0)) > 0 and int(raw.code) != KEY_ESCAPE:
   ev=InputEventKey.new();ev.physical_keycode=int(raw.code)
  elif raw.get("type") == "mouse" and int(raw.get("code",0)) in [1,2,3,8,9]:
   ev=InputEventMouseButton.new();ev.button_index=int(raw.code)
  if ev != null:assign(action,ev)
static func save(path: String) -> Error:
 var cfg := ConfigFile.new();cfg.load(path)
 for action: String in ACTIONS:
  var events := InputMap.action_get_events(action)
  if events.is_empty():continue
  var e:InputEvent=events[0]
  cfg.set_value(SECTION,action,{"type":"key" if e is InputEventKey else "mouse","code":e.physical_keycode if e is InputEventKey else e.button_index})
 return cfg.save(path)
static func reset(path: String) -> Error:
 for action: String in ACTIONS:assign(action,default_event(action))
 return save(path)
