extends Node2D
class_name DesertMustacheGroup
## Unplaced scene content. No level, spawn catalog or encounter mounts this.
enum State { TRAVEL, SPREAD, THROW, WAIT_SMOKE, CHARGE, SMOKE_HOLD, SCATTER }
# PLACEHOLDER tuning, not settled balance.
@export var player_path := NodePath("../../Player")
@export var terrain_path := NodePath("../Terrain")
@export var approach_range := 360.0
@export var disengage_range := 760.0
@export var keep_distance := 230.0
@export var spread_seconds := 1.8
@export var throw_windup := 0.4
@export var travel_points := PackedVector2Array([Vector2(-140,0),Vector2(140,0)])
var state := State.TRAVEL
var members: Array[Enemy] = []
var leader: Enemy
var _player: Player
var _clock := 0.0
var _route_index := 1
var _travel_center := Vector2.ZERO
var _spread_angle := 0.0
var _generation := 0
var _grenade: SmokeGrenade
var _cloud: SmokeCloud
var _scatter_origin := Vector2.ZERO
var _travel_time := 0.0
var _rearm := 0.0

func _ready() -> void:
 _player = get_node_or_null(player_path) as Player
 for child in get_children():
  if child is Enemy:
   members.append(child)
   child.terrain = get_node_or_null(terrain_path) as TerrainMap
 _travel_center = global_position
 _elect_leader()

func _elect_leader() -> void:
 members = members.filter(func(member: Enemy) -> bool: return is_instance_valid(member) and member.hp > 0 and not member.is_queued_for_deletion())
 if is_instance_valid(leader) and leader.hp > 0 and not leader.is_queued_for_deletion(): return
 leader = null
 for member in members:
  if is_instance_valid(member) and member.hp > 0 and not member.is_queued_for_deletion():
   leader = member
   return

func target() -> Player:
 if not is_instance_valid(_player) or _player.hp <= 0: return null
 for member in members:
  if is_instance_valid(member) and member.hp > 0 and TallGrass.can_see(member.terrain,member.global_position,_player.global_position): return _player
 return null

func _physics_process(dt: float) -> void:
 _elect_leader()
 if leader == null:
  queue_free()
  return
 _travel_time += dt
 _rearm = maxf(0.0,_rearm-dt)
 var player := target()
 if state in [State.CHARGE,State.SMOKE_HOLD]:
  if not is_instance_valid(_cloud) or not _cloud.has_smoke():
   _enter(State.SCATTER)
  elif player != null and _cloud.contains_smoke(player.global_position):
   if state != State.CHARGE:_enter(State.CHARGE)
  elif state != State.SMOKE_HOLD:_enter(State.SMOKE_HOLD)
 if state == State.SCATTER:
  _clock += dt
  if _clock >= 3.0:
   _enter(State.TRAVEL)
   _rearm = 4.0
  return
 var distance := leader.global_position.distance_to(player.global_position) if player != null else INF
 if state not in [State.CHARGE,State.SMOKE_HOLD] and (player == null or distance > disengage_range):
  if state != State.TRAVEL: _enter(State.TRAVEL)
 if state == State.TRAVEL:
  if not travel_points.is_empty():
   var goal := to_global(travel_points[_route_index%travel_points.size()])
   _travel_center = _travel_center.move_toward(goal,65.0*dt)
   if _travel_center.distance_to(goal) < 4.0: _route_index = (_route_index+1)%travel_points.size()
  if player != null and distance <= approach_range and _rearm <= 0.0:
   _spread_angle = player.global_position.direction_to(leader.global_position).angle()
   _enter(State.SPREAD)
  return
 if leader.freeze.is_frozen() or leader.stun_left > 0.0: return
 _clock += dt
 if state == State.SPREAD and _clock >= spread_seconds:
  _enter(State.THROW)
  leader.play_action(&"windup_ranged",true)
 elif state == State.WAIT_SMOKE and _clock > 3.0:
  # A removed/missed grenade never leaves a permanent wait or invents landing.
  _enter(State.TRAVEL)
 elif state == State.THROW and _clock >= throw_windup:
  if player == null: return
  _enter(State.WAIT_SMOKE)
  leader.play_action(&"ranged")
  _generation += 1
  call_deferred("_throw",leader.global_position,player.global_position,_generation)

func _throw(from: Vector2, at: Vector2, generation: int) -> void:
 if not is_inside_tree() or state != State.WAIT_SMOKE or generation != _generation: return
 # Parent area, not the leader: a killed thrower does not delete an airborne lob.
 _grenade = SmokeGrenade.launch(get_parent(),from,at)
 _grenade.landed.connect(_on_smoke_landed.bind(generation),CONNECT_ONE_SHOT)

func _on_smoke_landed(cloud: SmokeCloud, generation: int) -> void:
 if generation != _generation or state != State.WAIT_SMOKE  : return
 _cloud = cloud
 _scatter_origin = cloud.global_position
 _enter(State.CHARGE)

func _enter(next: State) -> void:
 state = next
 _clock = 0.0
 if next == State.TRAVEL: _generation += 1
 for member in members:
  if is_instance_valid(member) and member.hp > 0: member.clear_action()

func destination(member: Enemy) -> Vector2:
 var index := members.find(member)
 var player := target()
 if state == State.SCATTER:
  return _scatter_origin+Vector2.from_angle(float(index)*TAU/maxi(1,members.size())+0.35)*260.0
 if state in [State.CHARGE,State.SMOKE_HOLD] and is_instance_valid(_cloud) and _cloud.has_smoke():
  if player != null and _cloud.contains_smoke(player.global_position):return player.global_position
  return _cloud.interior_point(index)
 if state == State.TRAVEL or player == null:
  var offsets := [Vector2(-18,-12),Vector2(-74,21),Vector2(35,44),Vector2(-40,-60),Vector2(65,-28)]
  var sway := Vector2(sin(_travel_time*0.7+index*2.1),cos(_travel_time*0.53+index*1.7))*12.0
  return _travel_center+offsets[clampi(index,0,4)]+sway
 # Fan around approach bearing, not a tight cluster or a teleporting ring.
 var angle := _spread_angle+(float(index)-2.0)*0.48
 return player.global_position+Vector2.from_angle(angle)*keep_distance

func debug_state_text() -> String:
 return State.keys()[state]
