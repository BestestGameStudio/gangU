extends SceneTree
var failures:=0
func check(ok:bool,label:String):
 print('[814] ',label,': ',ok)
 if not ok:failures+=1
func _initialize():run.call_deferred()
func run():
 var main=load('res://game/core/main.tscn').instantiate();root.add_child(main);current_scene=main
 await process_frame
 var p:Player=main.get_node('Player');p.set_physics_process(false)
 var caster:SpellCaster=p.get_node('SpellCaster')
 var rock=load('res://data/spells/hook_shot_rock.tres') as Spell
 caster.unlock_spell(rock)
 for i in SpellCaster.SLOT_COUNT:
  if caster.get_slots()[i]==rock:caster.clear_slot(i)
 caster.clear_slot(0);caster.assign_slot(0,rock)
 main.get_node('CurrencyWallet').add(321)
 main.get_node('SpellProgress').add_upgrade_token(3)
 main.get_node('SpellProgress')._on_spell_cast(rock)
 main.get_node('OwnedRelics').add(load('res://data/relics/twin_dash.tres'))
 main.get_node('ReviveSatchel').carried=2
 main.area_loader.complete_encounter(&'dungeon_a')
 main.get_node('Shop')._paid_refresh_count=4
 main.area_loader._revive_claimed=true
 var map:WorldMap=main.get_node('WorldMap')
 map.reveal_cells(&'Overworld',[Vector2i(60,60)])
 var expected_color:=WorldMap.terrain_color(map.terrain,Vector2i(60,60))
 var snapshot:=WebRunSave.capture(main)
 check(not snapshot.has('area') and not snapshot.run.has('position') and not snapshot.run.has('hp'),'no position/fight/HP persistence')
 var text:=WebRunSave.encode(snapshot)
 var decoded:=WebRunSave.decode(text)
 check(not decoded.is_empty(),'complete snapshot roundtrips')
 check(decoded.progression.slots[0]==rock and decoded.progression.progress.tokens==3,'resource slots and tokens roundtrip')
 check(decoded.progression.relics.size()==1 and decoded.progression.relics[0].id==&'twin_dash','duplicated relic roundtrips')
 check(decoded.run.shop_stock==snapshot.run.shop_stock,'subresource shop stock roundtrips')
 check(decoded.run.map[&'Overworld'].colors[Vector2i(60,60)].is_equal_approx(expected_color),'capture snapshots current live terrain colors before leaving area')
 check(WebRunSave.decode('{oops').is_empty() and WebRunSave.decode('{"version":999}').is_empty(),'corrupt and future version rejected')
 check(WebRunSave.decode(WebRunSave.encode({'progression':{},'run':{}})).is_empty(),'valid encoding with invalid schema rejected')
 main.queue_free();await process_frame;await process_frame
 var fresh=load('res://game/core/main.tscn').instantiate();root.add_child(fresh);current_scene=fresh
 await process_frame
 var save:=WebRunSave.new();fresh.add_child(save);save.main=fresh;save.restore(decoded)
 var c:SpellCaster=fresh.get_node('Player/SpellCaster')
 check(c.get_slots()[0]==rock and fresh.get_node('SpellProgress').upgrade_tokens()==3,'restore actual slots and tokens')
 check(fresh.get_node('CurrencyWallet').balance()==321 and fresh.get_node('ReviveSatchel').carried==2,'restore wallet and carried revives')
 check(fresh.area_loader.is_cleared(&'dungeon_a') and fresh.get_node('Shop')._paid_refresh_count==4,'restore cleared rooms and paid shop price')
 check(fresh.area_loader.current_area.name==&'Overworld' and fresh.area_loader.current_area.get_node('HubServices').contains_player(fresh.get_node('Player').global_position) and fresh.get_node('Player').hp==100,'restore starts hub fresh health')
 check(fresh.area_loader._revive_claimed,'fixed revive claim persists, cannot duplicate item')
 check(fresh.get_node('WorldMap').cell_color(&'Overworld',Vector2i(60,60)).is_equal_approx(expected_color),'hub-restored explored map retains water color')
 check(not save.enabled,'native build does not enable browser saves')
 save._sand_defeated=true;fresh.area_loader.enter_overworld()
 var arena=fresh.area_loader.current_area.get_node('DesertStatueArena')
 save.apply_world_progress(fresh.area_loader.current_area)
 check(arena._won and not arena.is_active() and not arena._reward_pending,'completed Sand boss restores without restarting combat or issuing reward')
 fresh.queue_free();await process_frame;await process_frame
 print('[814] failures=',failures);quit(1 if failures else 0)
