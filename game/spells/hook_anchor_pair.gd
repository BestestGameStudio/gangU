class_name HookAnchorPair
extends Node2D
## Pair owns both fixed cast snapshots; per-player cap replaces oldest pair.
var owner_player: Player
var spell: Spell
var anchor: Node2D
var lure: Node2D
var taunt_left := 0.0
var whistle_left := 0.0
var _voice: AudioStreamPlayer2D
var note_age := 0.0

static func place(parent: Node, player: Player, s: Spell, anchor_at: Vector2, lure_at: Vector2) -> HookAnchorPair:
 var peers: Array[HookAnchorPair] = []
 for node in parent.get_tree().get_nodes_in_group("hook_anchor_pairs"):
  if node.owner_player == player and not node.is_queued_for_deletion(): peers.append(node)
 while peers.size() >= maxi(1, s.hook_pair_cap): peers.pop_front().queue_free()
 var pair := HookAnchorPair.new();pair.owner_player=player;pair.spell=s
 pair.anchor=Node2D.new();pair.lure=Node2D.new()
 pair.add_child(pair.anchor);pair.add_child(pair.lure)
 parent.add_child(pair);pair.anchor.global_position=anchor_at;pair.lure.global_position=lure_at
 return pair

func _ready() -> void:
 add_to_group("hook_anchor_pairs")
 _voice=AudioStreamPlayer2D.new();_voice.stream=FishyAudio.WHISTLE;add_child(_voice)

func _physics_process(delta: float) -> void:
 if not is_instance_valid(owner_player) or owner_player.hp<=0 or not owner_player.is_inside_tree():queue_free();return
 taunt_left-=delta
 if taunt_left<=0.0:
  taunt_left=spell.hook_taunt_interval
  for node in get_tree().get_nodes_in_group("enemies"):
   var enemy:=node as Enemy
   if enemy!=null and enemy.hp>0 and enemy.global_position.distance_to(lure.global_position)<=spell.hook_taunt_radius:
    enemy.hook_taunt_target=lure;enemy.hook_taunt_left=spell.hook_taunt_interval
 for node in get_tree().get_nodes_in_group("enemies"):
  var enemy:=node as Enemy
  if enemy!=null and enemy.hp>0 and enemy.global_position.distance_to(lure.global_position)<=16.0:
   HookReel.begin(get_parent(),enemy,anchor,spell)
 # One voice/note emitter for all pairs belonging to one player.
 var first:Node=null
 for node in get_tree().get_nodes_in_group("hook_anchor_pairs"):
  if node.owner_player==owner_player and not node.is_queued_for_deletion():first=node;break
 if first==self:
  whistle_left-=delta;note_age+=delta;_voice.global_position=owner_player.global_position
  if whistle_left<=0.0:_voice.play();whistle_left=maxf(5.0,_voice.stream.get_length())
 queue_redraw()

func _draw() -> void:
 if not is_instance_valid(anchor) or not is_instance_valid(lure):return
 draw_line(to_local(anchor.global_position),to_local(lure.global_position),Color(0.7,0.8,0.8),1)
 draw_circle(to_local(anchor.global_position),8,Color.GRAY)
 draw_circle(to_local(lure.global_position),5,Color.ORANGE)
 if is_instance_valid(owner_player) and note_age>0:
  draw_circle(to_local(owner_player.global_position+Vector2(10,-24-fmod(note_age*12,18))),2,Color.CYAN)

func _exit_tree() -> void:
 if not is_inside_tree():return
 for node in get_tree().get_nodes_in_group("enemies"):
  if node.hook_taunt_target==lure:node.hook_taunt_target=null;node.hook_taunt_left=0.0
