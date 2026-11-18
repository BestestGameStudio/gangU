extends Node2D
class_name DesertMustacheGroup
## Five-member desert squad, mounted by desert_squad_placement.gd.
## All transitions pass through _enter. Only WAIT_SMOKE accepts a landing.
enum State { TRAVEL, SPREAD, THROW, WAIT_SMOKE, CHARGE, SMOKE_HOLD, SCATTER }
const TRANSITIONS := {
 State.TRAVEL: [State.SPREAD],
 State.SPREAD: [State.TRAVEL,State.THROW],
 State.THROW: [State.TRAVEL,State.SPREAD,State.WAIT_SMOKE],
 State.WAIT_SMOKE: [State.TRAVEL,State.CHARGE],
 State.CHARGE: [State.SMOKE_HOLD,State.SCATTER,State.SPREAD],
 State.SMOKE_HOLD: [State.CHARGE,State.SCATTER,State.SPREAD],
 State.SCATTER: [State.TRAVEL,State.SPREAD],
}
# PLACEHOLDER tuning, not settled balance.
@export var player_path := NodePath("../../Player")
@export var terrain_path := NodePath("../Terrain")
@export var approach_range := 360.0
@export var disengage_range := 760.0
@export var keep_distance := 230.0
@export var spread_seconds := 1.8
@export var throw_windup := 0.4
@export var outside_seconds := 1.0
@export var launch_cooldown := 3.0
@export var scatter_seconds := 3.0
@export var travel_points := PackedVector2Array([Vector2(-140,0),Vector2(140,0)])
var state := State.TRAVEL
var members: Array[Enemy] = []
var leader: Enemy # Travel anchor only, never an exclusive thrower.
var thrower: Enemy
var _slots: Dictionary = {}
var _next_slot := 0
var _slot_count := 0
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
var _outside_clock := 0.0

func _ready() -> void:
 _player = get_node_or_null(player_path) as Player
 for child in get_children():
  if child is Enemy:
   _slots[child.get_instance_id()] = _slot_count
   _slot_count += 1
   members.append(child)
   child.terrain = get_node_or_null(terrain_path) as TerrainMap
 _travel_center = global_position
 _elect_leader()

func _alive(member) -> bool:
 return is_instance_valid(member) and member.hp > 0 and not member.is_queued_for_deletion()

func _eligible(member) -> bool:
 return _alive(member) and not member.freeze.is_frozen() and member.stun_left <= 0.0

func _elect_leader() -> void:
 for i in range(members.size()-1,-1,-1):
  if not _alive(members[i]): members.remove_at(i)
 if _alive(leader): return
 leader = members[0] if not members.is_empty() else null

func _pick_thrower() -> Enemy:
 # Stable scene slots survive pruning. Every eligible survivor gets a turn.
 for offset in _slot_count:
  var slot := (_next_slot+offset)%maxi(1,_slot_count)
  for member in members:
   if _eligible(member) and _slots.get(member.get_instance_id(),-1) == slot: return member
 return null

func target() -> Player:
 if not is_instance_valid(_player) or _player.hp <= 0: return null
 for member in members:
  if _alive(member) and TallGrass.can_see(member.terrain,member.global_position,_player.global_position): return _player
 return null

func _distance_to(player: Player) -> float:
 var distance := INF
 if player != null:
  for member in members:
   if _alive(member): distance = minf(distance,member.global_position.distance_to(player.global_position))
 return distance

func _prepare_spread(player: Player) -> void:
 _spread_angle = player.global_position.direction_to(leader.global_position).angle()
 _enter(State.SPREAD)

func _physics_process(dt: float) -> void:
 _elect_leader()
 if leader == null:
  queue_free()
  return
 _travel_time += dt
 _rearm = maxf(0.0,_rearm-dt)
 var player := target()
 var distance := _distance_to(player)
 if state in [State.CHARGE,State.SMOKE_HOLD]:
  if not is_instance_valid(_cloud) or not _cloud.has_smoke():
   _enter(State.SCATTER)
   return
  var inside := player != null and _cloud.contains_smoke(player.global_position)
  if inside:
   _outside_clock = 0.0
   if state != State.CHARGE: _enter(State.CHARGE)
  else:
   if state != State.SMOKE_HOLD: _enter(State.SMOKE_HOLD)
   # No throws at a dead, hidden or disengaged player. Keep the cloud refuge.
   if player != null and distance <= disengage_range:
    _outside_clock += dt
    if _outside_clock >= outside_seconds and _rearm <= 0.0:
     _prepare_spread(player)
   else: _outside_clock = 0.0
  return
 if state == State.SCATTER:
  _clock += dt
  if _clock >= scatter_seconds:
   if player != null and distance <= disengage_range and _rearm <= 0.0: _prepare_spread(player)
   else: _enter(State.TRAVEL)
  return
 if player == null or distance > disengage_range:
  if state != State.TRAVEL: _enter(State.TRAVEL)
 if state == State.TRAVEL:
  if not travel_points.is_empty():
   var goal := to_global(travel_points[_route_index%travel_points.size()])
   _travel_center = _travel_center.move_toward(goal,65.0*dt)
   if _travel_center.distance_to(goal) < 4.0: _route_index = (_route_index+1)%travel_points.size()
  if player != null and distance <= approach_range and _rearm <= 0.0: _prepare_spread(player)
  return
 if state == State.THROW and not _eligible(thrower):
  if _alive(thrower): thrower.clear_action()
  thrower = _pick_thrower()
  _clock = 0.0
  if thrower == null: _enter(State.SPREAD)
  else: thrower.play_action(&"windup_ranged",true)
  return
 _clock += dt
 if state == State.SPREAD and _clock >= spread_seconds and _rearm <= 0.0:
  _enter(State.THROW)
 elif state == State.WAIT_SMOKE and _clock > 3.0:
  _enter(State.TRAVEL) # Missing landing never invents a charge or permanent wait.
 elif state == State.THROW and _clock >= throw_windup:
  if player == null: return
  var from := thrower.global_position
  var at := player.global_position
  var actor := thrower
  _next_slot = (int(_slots[actor.get_instance_id()])+1)%maxi(1,_slot_count)
  _enter(State.WAIT_SMOKE)
  actor.play_action(&"ranged")
  _rearm = launch_cooldown
  _generation += 1
  call_deferred("_throw",from,at,_generation)

func _throw(from: Vector2, at: Vector2, generation: int) -> void:
 if not is_inside_tree() or state != State.WAIT_SMOKE or generation != _generation: return
 # Area-owned: death or disable after release cannot delete an airborne lob.
 _grenade = SmokeGrenade.launch(get_parent(),from,at)
 _grenade.landed.connect(_on_smoke_landed.bind(generation),CONNECT_ONE_SHOT)

func _on_smoke_landed(cloud, generation: int) -> void:
 if generation != _generation or state != State.WAIT_SMOKE or not is_instance_valid(cloud): return
 _cloud = cloud
 _scatter_origin = cloud.global_position
 _outside_clock = 0.0
 _enter(State.CHARGE)

func _enter(next: State) -> bool:
 if next == state or not TRANSITIONS.get(state,[]).has(next): return false
 var candidate: Enemy
 if next == State.THROW:
  candidate = _pick_thrower()
  if candidate == null: return false
 state = next
 _clock = 0.0
 if next in [State.TRAVEL,State.SPREAD]:
  _generation += 1
  _outside_clock = 0.0
 thrower = candidate
 for member in members:
  if _alive(member): member.clear_action()
 if next == State.THROW: thrower.play_action(&"windup_ranged",true)
 return true

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
 var angle := _spread_angle+(float(index)-2.0)*0.48
 return player.global_position+Vector2.from_angle(angle)*keep_distance

func debug_state_text() -> String:
 return State.keys()[state]
