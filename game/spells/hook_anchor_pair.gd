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
const ROPE := preload("res://assets/spells/hook_shot/rope.png")
const ANCHOR := preload("res://assets/spells/hook_shot/anchor.png")
const LURE := preload("res://assets/spells/hook_shot/lure.png")
const NOTES := preload("res://assets/spells/hook_shot/music_notes.png")
var caught_enemy: Enemy = null
var active_reel: HookReel = null
var consumed := false
var lure_cast_position := Vector2.ZERO
var recasts_used := 0
var returning := false

static func place(parent: Node, player: Player, s: Spell, anchor_at: Vector2, lure_at: Vector2) -> HookAnchorPair:
 var peers: Array[HookAnchorPair] = []
 for node in parent.get_tree().get_nodes_in_group("hook_anchor_pairs"):
  if node.owner_player == player and not node.is_queued_for_deletion(): peers.append(node)
 while peers.size() >= maxi(1, s.hook_pair_cap): peers.pop_front().queue_free()
 var pair := HookAnchorPair.new();pair.owner_player=player;pair.spell=s
 pair.anchor=Node2D.new();pair.lure=Node2D.new()
 pair.add_child(pair.anchor);pair.add_child(pair.lure)
 parent.add_child(pair);pair.anchor.global_position=anchor_at;pair.lure.global_position=lure_at
 pair.lure_cast_position=lure_at
 return pair

func _ready() -> void:
 add_to_group("hook_anchor_pairs")
 _voice=AudioStreamPlayer2D.new();_voice.stream=FishyAudio.WHISTLE;add_child(_voice)

func _physics_process(delta: float) -> void:
 if not is_instance_valid(owner_player) or owner_player.hp<=0 or not owner_player.is_inside_tree():queue_free();return
 _tick_emitter(delta)
 if returning:
  lure.global_position=lure.global_position.move_toward(lure_cast_position,maxf(spell.projectile_speed,1.0)*delta)
  if lure.global_position.is_equal_approx(lure_cast_position):
   returning=false;taunt_left=0.0
  queue_redraw();return
 if consumed:
  if not is_instance_valid(active_reel) or active_reel.is_queued_for_deletion() or not is_instance_valid(caught_enemy):
   queue_free();return
  lure.global_position=caught_enemy.global_position
  queue_redraw();return
 taunt_left-=delta
 if taunt_left<=0.0:
  taunt_left=spell.hook_taunt_interval
  for node in get_tree().get_nodes_in_group("enemies"):
   var enemy:=node as Enemy
   if enemy!=null and enemy.hp>0 and HitContext.targetable(enemy) and enemy.global_position.distance_to(lure.global_position)<=spell.hook_taunt_radius:
    enemy.hook_taunt_target=lure;enemy.hook_taunt_left=spell.hook_taunt_interval
 for node in get_tree().get_nodes_in_group("enemies"):
  var enemy:=node as Enemy
  if enemy!=null and enemy.hp>0 and HitContext.targetable(enemy) and enemy.global_position.distance_to(lure.global_position)<=16.0:
   var reel := HookReel.begin(get_parent(),enemy,anchor,spell)
   if reel != null:
    consumed=true;caught_enemy=enemy;active_reel=reel
    reel.reached_target.connect(_on_reel_arrived,CONNECT_ONE_SHOT)
    lure.global_position=enemy.global_position
    break

 queue_redraw()

func _on_reel_arrived() -> void:
 if is_queued_for_deletion():return
 if recasts_used>=maxi(0,spell.hook_lure_recasts):
  queue_free();return
 # Snapshot the landed position before releasing the enemy reference. The same
 # anchor stays fixed; only this pair's lure flies back to its original cast.
 if is_instance_valid(caught_enemy):lure.global_position=caught_enemy.global_position
 recasts_used+=1;returning=true;consumed=false
 caught_enemy=null;active_reel=null
 queue_redraw()

func _tick_emitter(delta: float) -> void:
 # One voice/note emitter for all pairs belonging to one player.
 var first:Node=null
 for node in get_tree().get_nodes_in_group("hook_anchor_pairs"):
  if node.owner_player==owner_player and not node.is_queued_for_deletion():first=node;break
 if first==self:
  whistle_left-=delta;note_age+=delta;_voice.global_position=owner_player.global_position
  if whistle_left<=0.0:_voice.play();whistle_left=maxf(5.0,_voice.stream.get_length())

func _draw() -> void:
 if not is_instance_valid(anchor) or not is_instance_valid(lure):return
 var a := to_local(anchor.global_position); var b := to_local(lure.global_position)
 draw_set_transform(a,(b-a).angle())
 draw_texture_rect(ROPE,Rect2(0,-2,a.distance_to(b),4),true)
 draw_set_transform(Vector2.ZERO)
 draw_texture(ANCHOR,a-Vector2(12,21))
 draw_texture(LURE,b-Vector2(8,12))
 if is_instance_valid(owner_player) and note_age>0:
  var frame := int(note_age/0.12)%3
  var point := to_local(owner_player.global_position+Vector2(8,-24-fmod(note_age*12,18)))
  draw_texture_rect_region(NOTES,Rect2(point,Vector2(8,12)),Rect2(frame*8,0,8,12))

func _exit_tree() -> void:
 if is_instance_valid(active_reel):
  if is_instance_valid(caught_enemy):HookPullStack.detach(caught_enemy,active_reel)
  active_reel.queue_free()
 if not is_inside_tree():return
 for node in get_tree().get_nodes_in_group("enemies"):
  if node.hook_taunt_target==lure:node.hook_taunt_target=null;node.hook_taunt_left=0.0
