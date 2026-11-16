extends SceneTree
## #797: actual mounted Hook chain reveals only applied panorama pieces.
var checks := 0
var failures := 0
func check(ok: bool, label: String):
 checks += 1
 if not ok: failures += 1
 print('[797] ', label, ' -> ', 'PASS' if ok else 'FAIL')
func _initialize():run.call_deferred()
func run():
 var main=load('res://game/core/main.tscn').instantiate()
 root.add_child(main);current_scene=main
 for i in 12:await process_frame
 var caster=main.get_node('Player/SpellCaster')
 var panel=main.get_node('EquipPanel')
 panel.show_panel()
 for id in ['hook_shot','hook_shot_magnet','hook_shot_catch','hook_shot_rock']:
  var spell=load('res://data/spells/%s.tres'%id)
  caster.unlock_spell(spell);caster.clear_slot(2);caster.assign_slot(2,spell)
  panel._selected=spell;panel._refresh()
  for i in 8:await process_frame
  check(panel._upgrade_cards.size()==3,'three Hook result cards: '+id)
  for index in panel._upgrade_cards.size():
   var card=panel._upgrade_cards[index]
   var applied:bool=index < ['hook_shot','hook_shot_magnet','hook_shot_catch','hook_shot_rock'].find(id)
   var expected=EquipPanel.HOOK_CARD_ART.values()[index] if applied else null
   check(card._art.visible==applied and card._art.texture==expected,'applied-only panorama: '+id+' / '+str(index))
   if applied:
    check(card._art.texture.get_size()==Vector2(48,64) and card._art.size==card.size and card._art.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST,'pixel-art bounds and filter')
    check(card.description_label.get_global_rect().end.y<=card.get_global_rect().end.y-11,'authored description fits: '+id+' / '+str(index))
   for state in ['locked','ready','token','unavailable']:
    card.set_unlock_state(state,5,10)
    check(not card._art.visible and card._art.texture==null,'no splash in '+state)
 main.queue_free();await process_frame
 print('[797] ',checks,' checks, ',failures,' failures')
 quit(1 if failures else 0)
