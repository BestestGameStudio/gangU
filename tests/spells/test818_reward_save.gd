extends SceneTree
var failures:=0
func check(ok:bool,label:String):
 print('[818] ',label,': ',ok)
 if not ok:failures+=1
func _initialize():run.call_deferred()
func run():
 # This owner is deliberately NOT loaded before resolving the embedded entry.
 var entry=WebRunSave.unpack_value({'@resource':'res://data/rewards/fishy_hook_table.tres::hook'})
 check(entry is RewardEntry and entry.spell==load('res://data/spells/hook_shot.tres'),'cold reward subresource resolves through parent table')
 check(WebRunSave.unpack_value({'@resource':'res://data/../game/core/main.tscn'})==null,'traversal rejected')
 check(WebRunSave.unpack_value({'@resource':'res://game/core/main.tscn'})==null,'non-data resources rejected')
 var main=load('res://game/core/main.tscn').instantiate();root.add_child(main);current_scene=main
 await process_frame
 var caster:SpellCaster=main.get_node('Player/SpellCaster')
 var empty:Array[Spell]=[]
 var files:=DirAccess.get_files_at('res://data/spells');var total:=0
 for file in files:
  if not file.ends_with('.tres'):continue
  var spell=load('res://data/spells/'+file)
  if not spell is Spell:continue
  total+=1
  caster.restore_run_state(empty,empty,empty)
  check(caster.unlock_spell(spell),'grant '+file)
  main.get_node('SpellProgress')._on_spell_cast(spell)
  var state:=WebRunSave.decode(WebRunSave.encode(WebRunSave.capture(main)))
  check(not state.is_empty() and state.progression.unlocked==[spell] and state.progression.slots[0]==spell,'codec '+file)
  caster.restore_run_state(empty,empty,empty)
  var saver:=WebRunSave.new();main.add_child(saver);saver.main=main
  state.run={};saver.restore(state)
  check(caster.get_unlocked()==[spell] and caster.get_slots()[0]==spell,'restore '+file)
  saver.queue_free()
 check(total>=34,'all source spell resources discovered')
 check(WebRunSave.decode_error('{oops')=='invalid save JSON','invalid JSON diagnostic')
 check(WebRunSave.decode_error('{"version":999}')=='unsupported save version','version diagnostic')
 main.queue_free();await process_frame;await process_frame
 print('[818] failures=',failures);quit(1 if failures else 0)
