extends SceneTree
var failures:=0
var kills:=0
func check(ok:bool,text:String):
 print('[795] ',text,': ',ok)
 if not ok:failures+=1
func _initialize():run.call_deferred()
func run():
 var source:Node=load('res://game/world/overworld.tscn').instantiate()
 var entries:Array[SpawnEntry]=source.get_node('FishySouth').entries
 for entry in entries:
  var area:=Node2D.new();root.add_child(area);current_scene=area
  var pool:=RewardPool.new();area.add_child(pool)
  var player:=load('res://game/player/player.tscn').instantiate() as Player;area.add_child(player)
  var spawner:=EnemySpawner.new();area.add_child(spawner);spawner.setup([entry],NodePath(''),null,area)
  var enemy:=spawner.request_spawn(entry)
  enemy.apply_damage(10000);kills+=1
  for i in 3:await process_frame
  var drops:=get_nodes_in_group('reward_drops')
  check(drops.size()==1,'production entry kill produces one drop')
  if drops.size()==1:
   var drop:=drops[0] as RewardDrop
   check(drop.entry.spell!=null and drop.entry.spell.resource_path=='res://data/spells/hook_shot.tres','production drop is Hook Shot, not currency')
   drop._on_body_entered(player)
  check(player.get_node('SpellCaster').has_logical_spell(load('res://data/spells/hook_shot.tres')),'actual pickup unlocks Hook Shot')
  for i in 2:await process_frame
  var next:=spawner.request_spawn(entry);next.apply_damage(10000);kills+=1
  for i in 3:await process_frame
  check(get_nodes_in_group('reward_drops').is_empty(),'no Hook Shot repeat after pickup')
  area.free();await process_frame
 source.free()
 print('[795] actual production-entry kills tried: ',kills)
 quit(1 if failures else 0)
