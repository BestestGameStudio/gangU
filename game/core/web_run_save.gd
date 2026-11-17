class_name WebRunSave
extends Node
## Browser-only progression persistence. Every load starts safely in the hub.
## No player position, HP, enemies, projectiles or fight state is serialized.
const KEY := "gangu.run.v1"
const REJECTED_KEY := KEY+".rejected"
const VERSION := 1
const MAX_BYTES := 4000000
var main: Node
var status := ""
var _timer := 0.0
var _label_left := 0.0 ## #827: seconds the info label stays visible (0 = until replaced)
const RESTORED_SECONDS := 4.0
var _restoring := false
var _callback: JavaScriptObject
var _label: Label
var enabled := false
var _sand_defeated := false
var _rejected := ""
var _recovery: VBoxContainer

func start(host: Node) -> void:
 main=host;enabled=OS.has_feature("web")
 if not enabled:return
 process_mode=Node.PROCESS_MODE_ALWAYS
 var layer:=CanvasLayer.new();layer.layer=100;add_child(layer)
 _label=Label.new();_label.position=Vector2(16,150);layer.add_child(_label)
 _label.add_theme_color_override("font_shadow_color",Color.BLACK)
 _label.add_theme_constant_override("shadow_offset_x",2);_label.add_theme_constant_override("shadow_offset_y",2)
 var raw:String=JavaScriptBridge.eval("(()=>{try{return localStorage.getItem('"+KEY+"')||''}catch(e){return 'storage-unavailable'}})()")
 if raw=="storage-unavailable":_set_status("Browser saving unavailable (storage blocked)")
 elif not raw.is_empty():
  var state:=decode(raw)
  if state.is_empty():
   _rejected=raw
   _show_recovery(decode_error(raw))
  else:
   _restoring=true
   restore(state)
   _restoring=false
   _set_status("Local progression restored",RESTORED_SECONDS)
 _callback=JavaScriptBridge.create_callback(_on_browser_event)
 var window:=JavaScriptBridge.get_interface("window")
 window.ganguRunSave=_callback
 JavaScriptBridge.eval("""
 if(window.ganguSaveCleanup)window.ganguSaveCleanup();
 const save=()=>{if(window.ganguRunSave)window.ganguRunSave()};
 const visibility=()=>{if(document.visibilityState==='hidden')save()};
 window.addEventListener('beforeunload',save);window.addEventListener('pagehide',save);
 document.addEventListener('visibilitychange',visibility);
 window.ganguSaveCleanup=()=>{window.removeEventListener('beforeunload',save);window.removeEventListener('pagehide',save);document.removeEventListener('visibilitychange',visibility)};
 """)
 main.get_node("RunManager").run_restarting.connect(save_death)
 main.area_loader.dungeon_cleared.connect(func(_id):save_now.call_deferred())
 for source in [main.get_node("CurrencyWallet").balance_changed,main.get_node("OwnedRelics").changed,main.get_node("SpellProgress").upgrades_changed,main.get_node("Shop").stock_refreshed,main.get_node("Player/SpellCaster").spell_unlocked,main.get_node("Player/SpellCaster").slot_cleared,main.get_node("SpellProgress").cast_progress_changed,main.get_node("ReviveSatchel").revive_collected]:
  source.connect(func(_a=null):save_now.call_deferred())
 for source in [main.get_node("Player/SpellCaster").slot_assigned,main.get_node("Consumables").carried_changed,main.get_node("ReviveSatchel").revive_used]:
  source.connect(func(_a,_b):save_now.call_deferred())
 save_now()

func _process(delta:float) -> void:
 if not enabled:return
 if _label_left>0.0:
  _label_left-=delta
  if _label_left<=0.0 and _label!=null:_label.text=""
 _timer+=delta
 if _timer>=1.0:
  _timer=0.0;save_now()

func _on_browser_event(_args:Array) -> void:
 save_now()

func _set_status(text:String,seconds:float=0.0) -> void:
 status=text
 _label_left=seconds
 if _label!=null:_label.text=text

func save_now() -> bool:
 if not enabled or _restoring or not _rejected.is_empty() or main.get_node("Player").hp<=0:return false
 var state:=capture(main)
 state.run["sand_defeated"]=_sand_defeated or _sand_won(main)
 return _write(state)

func save_death() -> void:
 # Synchronous before the death pause: closing now cannot resurrect money.
 var state:=capture(main)
 state["run"]={}
 _write(state)

func _write(state:Dictionary) -> bool:
 if not _rejected.is_empty():return false
 var text:=encode(state)
 if text.length()>MAX_BYTES:
  _set_status("Local save too large; previous save kept");return false
 var code:="(()=>{try{localStorage.setItem('"+KEY+"',"+JSON.stringify(text)+");return true}catch(e){return false}})()"
 var ok:bool=JavaScriptBridge.eval(code)
 if not ok:_set_status("Local saving failed; browser storage full or blocked")
 return ok

static func encode(state:Dictionary) -> String:
 var payload:=Marshalls.raw_to_base64(var_to_bytes(pack_value(state)))
 return JSON.stringify({"version":VERSION,"payload":payload,"sha256":payload.sha256_text()})

static func decode_error(text:String) -> String:
 if text.length()>MAX_BYTES:return "save exceeds size limit"
 var parser:=JSON.new()
 if parser.parse(text)!=OK:return "invalid save JSON"
 var envelope=parser.data
 if not envelope is Dictionary:return "invalid envelope"
 if envelope.get("version")!=VERSION:return "unsupported save version"
 if not envelope.get("payload") is String:return "missing payload"
 if envelope.get("sha256")!=envelope.payload.sha256_text():return "checksum mismatch"
 var value=unpack_value(bytes_to_var(Marshalls.base64_to_raw(envelope.payload)))
 if not valid_state(value):return "missing resource or invalid progression data"
 return ""

static func decode(text:String) -> Dictionary:
 if not decode_error(text).is_empty():return {}
 return unpack_value(bytes_to_var(Marshalls.base64_to_raw(JSON.parse_string(text).payload)))

func _show_recovery(reason:String) -> void:
 _set_status("Save unreadable ("+reason+"). Original kept; saving paused.")
 _recovery=VBoxContainer.new();_recovery.position=Vector2(16,176)
 _label.get_parent().add_child(_recovery)
 var help:=Label.new();help.text="Download your save before starting over. Do not clear site data.";_recovery.add_child(help)
 var download:=Button.new();download.text="Download original save";_recovery.add_child(download)
 download.pressed.connect(func():JavaScriptBridge.download_buffer(_rejected.to_utf8_buffer(),"gangu-save-recovery.json","application/json"))
 var reset:=Button.new();reset.text="Start a new save...";_recovery.add_child(reset)
 var confirm:=ConfirmationDialog.new();confirm.dialog_text="Replace this unreadable save with your current new progress?\nA recovery copy will be kept in this browser.";confirm.ok_button_text="Keep backup and start new";add_child(confirm)
 reset.pressed.connect(func():confirm.popup_centered())
 confirm.confirmed.connect(_start_new_save)

func _start_new_save() -> void:
 # Never replace either the original or an older backup if backup creation fails.
 var code:="(()=>{try{if(localStorage.getItem('"+REJECTED_KEY+"')!==null)return false;localStorage.setItem('"+REJECTED_KEY+"',"+JSON.stringify(_rejected)+");return true}catch(e){return false}})()"
 if not JavaScriptBridge.eval(code):
  _set_status("Saving paused: backup exists or storage blocked. Download original before clearing it.");return
 _rejected="";_recovery.queue_free()
 _set_status("New save started. Previous save kept in browser recovery backup.")
 save_now()

static func valid_state(state:Variant) -> bool:
 if not state is Dictionary or not state.get("progression") is Dictionary or not state.get("run") is Dictionary:return false
 var p:Dictionary=state.progression
 for key in ["unlocked","spells","slots"]:
  if not p.get(key) is Array:return false
  for item in p[key]:
   if item!=null and not item is Spell:return false
 if p.slots.size()!=SpellCaster.SLOT_COUNT or not p.get("progress") is Dictionary or not p.get("relics") is Array:return false
 for item in p.relics:
  if not item is Relic:return false
 for key in ["cast_counts","tiers","quest_counts"]:
  if not p.progress.get(key) is Dictionary:return false
  for count in p.progress[key].values():
   if not count is int or count<0:return false
 if not p.progress.get("tokens") is int:return false
 var r:Dictionary=state.run
 if r.is_empty():return true
 for key in ["wallet","revives","shop_paid"]:
  if not r.get(key) is int or r[key]<0:return false
 for key in ["consumables","map","map_sites","map_positions"]:
  if not r.get(key) is Dictionary:return false
 for key in ["cleared","shop_stock","rewards"]:
  if not r.get(key) is Array:return false
 for item in r.shop_stock:
  if item!=null and not item is ShopEntry:return false
 for item in r.rewards:
  if not item is RewardEntry:return false
 for item in r.cleared:
  if not item is StringName and not item is String:return false
 for item in r.consumables:
  if not item is Consumable or not r.consumables[item] is int:return false
 for id in r.map:
  var area=r.map[id]
  if not area is Dictionary:return false
  for key in ["explored","colors"]:
   if not area.get(key) is Dictionary:return false
  for key in ["markers","strokes"]:
   if not area.get(key) is Array:return false
 return true

static func pack_value(value:Variant) -> Variant:
 if value is Relic:
  var fields:={}
  for key in ["id","display_name","description","rarity","hooked_tags","stage","amount","chance","multiplier","scalar_effects"]:fields[key]=value.get(key)
  return {"@relic":fields}
 if value is Resource:return {"@resource":value.resource_path}
 if value is Dictionary:
  var pairs:=[]
  for key in value:pairs.append([pack_value(key),pack_value(value[key])])
  return {"@dict":pairs}
 if value is Array:
  var out:=[]
  for item in value:out.append(pack_value(item))
  return out
 return value

static func unpack_value(value:Variant,depth:int=0) -> Variant:
 if depth>32:return null
 if value is Dictionary:
  if value.has("@resource"):
   var path:String=str(value["@resource"])
   var parent_path:=path.split("::")[0]
   if not path.begins_with("res://data/") or ".." in path or not parent_path.ends_with(".tres") or not ResourceLoader.exists(parent_path):return null
   # Embedded reward/shop resources are cached only after their owner loads.
   # On a cold browser start exists(owner::id) is false until then.
   var owner=load(parent_path)
   if owner==null:return null
   var resource=load(path)
   return resource if resource is Spell or resource is Consumable or resource is ShopEntry or resource is RewardEntry else null
  if value.has("@relic"):
   var r:=Relic.new();var f=value["@relic"]
   if not f is Dictionary:return null
   for key in ["id","display_name","description","rarity","hooked_tags","stage","amount","chance","multiplier","scalar_effects"]:
    if f.has(key):r.set(key,f[key])
   return r if r.is_valid_definition() else null
  if not value.get("@dict") is Array:return null
  var out:={}
  for pair in value["@dict"]:
   if not pair is Array or pair.size()!=2:return null
   var key=unpack_value(pair[0],depth+1)
   if key!=null:out[key]=unpack_value(pair[1],depth+1)
  return out
 if value is Array:
  var out:=[]
  for item in value:out.append(unpack_value(item,depth+1))
  return out
 return value

static func capture(host:Node) -> Dictionary:
 var p:Player=host.get_node("Player")
 var caster:SpellCaster=p.get_node("SpellCaster")
 var loader:AreaLoader=host.area_loader
 # Active map colors otherwise remain live-only until the player leaves.
 var map:WorldMap=host.get_node("WorldMap")
 map._snapshot_colors(map.area_id,map.terrain)
 return {"progression":{"unlocked":caster.get_unlocked(),
  "spells":caster.spells.duplicate(),
  "slots":caster.get_slots(),
  "progress":host.get_node("SpellProgress").capture_run_state(),
  "relics":host.get_node("OwnedRelics").all()},
  "run":{"wallet":host.get_node("CurrencyWallet").balance(),
  "revives":host.get_node("ReviveSatchel").carried,
  "consumables":host.get_node("Consumables")._counts.duplicate(),
  "cleared":loader.cleared_ids(),
  "revive_claims":loader._revive_claimed,
  "map":host.get_node("WorldMap")._areas.duplicate(true),
  "map_sites":host.get_node("WorldMap")._sites.duplicate(true),
  "map_positions":host.get_node("WorldMap")._last_pos.duplicate(),
  "shop_stock":host.get_node("Shop")._stock.duplicate(),
  "shop_paid":host.get_node("Shop")._paid_refresh_count,
  "rewards":host.get_node("RewardPool").granted()}}

func restore(state:Dictionary) -> void:
 var progression:Dictionary=state.progression
 var caster:SpellCaster=main.get_node("Player/SpellCaster")
 var unlocked:Array[Spell]=[];unlocked.assign(progression.get("unlocked",[]))
 var spells:Array[Spell]=[];spells.assign(progression.get("spells",[]))
 var slots:Array[Spell]=[];slots.assign(progression.get("slots",[]))
 caster.restore_run_state(unlocked,spells,slots)
 main.get_node("SpellProgress").restore_run_state(progression.get("progress",{}))
 for relic in progression.get("relics",[]):
  if relic is Relic:main.get_node("OwnedRelics").add(relic)
 var run:Dictionary=state.run
 _sand_defeated=bool(run.get("sand_defeated",false))
 if run.is_empty():return
 var loader:AreaLoader=main.area_loader
 for id in run.get("cleared",[]):loader.encounter_state.complete(StringName(id))
 loader._revive_claimed=bool(run.get("revive_claims",false))
 main.get_node("CurrencyWallet").add(maxi(0,int(run.get("wallet",0))))
 main.get_node("ReviveSatchel").carried=maxi(0,int(run.get("revives",0)))
 main.get_node("Consumables")._counts=run.get("consumables",{})
 var map:WorldMap=main.get_node("WorldMap")
 map._areas=run.get("map",{});map._sites=run.get("map_sites",{});map._last_pos=run.get("map_positions",{})
 var shop:Shop=main.get_node("Shop")
 shop._stock.assign(run.get("shop_stock",[]));shop._paid_refresh_count=maxi(0,int(run.get("shop_paid",0)));shop.stock_refreshed.emit()
 main.get_node("RewardPool")._granted.assign(run.get("rewards",[]))

static func _sand_won(host:Node) -> bool:
 var world:Node=host.area_loader._run_overworld
 var arena=world.get_node_or_null("DesertStatueArena") if is_instance_valid(world) else null
 return arena!=null and arena._won

func apply_world_progress(area:Node) -> void:
 var arena=area.get_node_or_null("DesertStatueArena")
 if _sand_defeated and arena!=null:arena.restore_completed_progression()
