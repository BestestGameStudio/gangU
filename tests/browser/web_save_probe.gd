extends Node
var callback:JavaScriptObject
func _ready():
 callback=JavaScriptBridge.create_callback(_command)
 JavaScriptBridge.get_interface('window').ganguTest=callback
func _command(args:Array):
 var main=get_parent()
 var saver=main.get_node('WebRunSave')
 var caster=main.get_node('Player/SpellCaster')
 var command=str(args[0])
 if command=='seed':
  main.get_node('CurrencyWallet').add(321)
  main.get_node('SpellProgress').add_upgrade_token(3)
  var rock=load('res://data/spells/hook_shot_rock.tres')
  caster.unlock_spell(rock)
  for i in SpellCaster.SLOT_COUNT:
   if caster.get_slots()[i]==rock:caster.clear_slot(i)
  caster.clear_slot(0);caster.assign_slot(0,rock)
  main.get_node('OwnedRelics').add(load('res://data/relics/twin_dash.tres'))
  main.area_loader.complete_encounter(&'dungeon_a')
  main.get_node('ReviveSatchel').carried=2
  main.get_node('Shop')._paid_refresh_count=4
  main.get_node('Player').hp=42
 elif command=='death':
  main.get_node('ReviveSatchel').carried=0
  main.get_node('Player').apply_damage(100000)
 elif command=='add':main.get_node('CurrencyWallet').add(7)
 elif command=='silent':
  saver.set_process(false)
  main.get_node('CurrencyWallet')._balance+=13
 elif command=='save':saver.save_now()
 var slots:=[]
 for s in caster.get_slots():slots.append(s.resource_path if s!=null else '')
 var data={"wallet":main.get_node('CurrencyWallet').balance(),"tokens":main.get_node('SpellProgress').upgrade_tokens(),"slots":slots,"relics":main.get_node('OwnedRelics').count(),"cleared":main.area_loader.is_cleared(&'dungeon_a'),"revives":main.get_node('ReviveSatchel').carried,"paid":main.get_node('Shop')._paid_refresh_count,"hp":main.get_node('Player').hp,"area":str(main.area_loader.current_area.name),"status":saver.status}
 JavaScriptBridge.get_interface('window').ganguTestResult=JSON.stringify(data)
