extends Node2D
## One run-owned group, sampled on northern desert sand after terrain mounts.
## No respawn: area caching retains casualties and death reload rebuilds it.
@export var group_scene: PackedScene
var group: DesertMustacheGroup
func _ready() -> void:
 call_deferred("_place")
func _place() -> void:
 var area := get_parent() as Node2D
 var ground := area.get_node("Ground") as OverworldGround
 var terrain := area.get_node("Terrain") as TerrainMap
 var arena := area.get_node("DesertStatueArena") as DesertStatueArena
 arena.configure_size()
 # Prefer the west/northwest approach outside the boss barrier, not its fight.
 for angle in [PI,PI*1.16,PI*0.84,PI*1.32,PI*0.68]:
  for extra in [340.0,420.0,500.0,580.0]:
   var at: Vector2 = arena.position+Vector2.from_angle(angle)*(arena.barrier_radius+extra)
   if not _clear_patch(at,area,ground,terrain,arena):continue
   group = group_scene.instantiate() as DesertMustacheGroup
   group.position = to_local(area.to_global(at))
   group.player_path = NodePath("../../../Player")
   group.terrain_path = NodePath("../../Terrain")
   group.travel_points = PackedVector2Array([Vector2(-55,-20),Vector2(55,20)])
   for member in group.get_children():
    if member is Enemy:member.player_path = NodePath("../../../../Player")
   add_child(group)
   print("Desert squad placed:1group/5members at ",at)
   return
 push_error("Desert squad: no clear sand patch outside boss/scorpion envelope")
func _clear_patch(at: Vector2, area: Node2D, ground: OverworldGround, terrain: TerrainMap, arena: DesertStatueArena) -> bool:
 # Footprint includes loose formation and authored short patrol. Check all cells,
 # not just the center, so a sandy center cannot hide a water/ruin-edge spawn.
 for y in range(-128,129,32):
  for x in range(-160,161,32):
   var p := at+Vector2(x,y)
   if p.distance_to(arena.position) < arena.barrier_radius+160.0:return false
   if ground._compute_lattice_type(p) != DualGrid.T.SAND:return false
   if not terrain.is_walkable_at(area.to_global(p)):return false
 var scorpions := area.get_node_or_null("Scorpions") as AreaSpawnData
 if scorpions != null:
  for entry in scorpions.entries:
   if entry.position.distance_to(at)<320.0:return false
 return true
