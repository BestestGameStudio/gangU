extends TerrainPath
class ReferencePath extends TerrainPath:
 func _find_path(map:TerrainMap,from:Vector2,to:Vector2,swim:bool=false)->Array[Vector2i]:return _find_path_uncached(map,from,to,swim)
 func _passable(map:TerrainMap,cell:Vector2i,swim:bool)->bool:return not map.trunk_nav_blocked(cell) and map.can_enter_cell(cell,swim)
 func _hard_obstacle(map:TerrainMap,cell:Vector2i)->bool:return map.trunk_nav_blocked(cell) or map.is_hard_obstacle_cell(cell)
static var elapsed_us:int=0
static var calls:int=0
static var reference_us:int=0
static var mismatches:int=0
var reference:=ReferencePath.new()
func steer(map:TerrainMap,pos:Vector2,previous:Vector2,desired:Vector2,dest:Vector2,speed:float,delta:float,can_swim:bool=false,detour_unwalkable:bool=false)->Vector2:
 var start:=Time.get_ticks_usec()
 var result:=super(map,pos,previous,desired,dest,speed,delta,can_swim,detour_unwalkable)
 elapsed_us+=Time.get_ticks_usec()-start;calls+=1
 start=Time.get_ticks_usec()
 var expected:=reference.steer(map,pos,previous,desired,dest,speed,delta,can_swim,detour_unwalkable)
 reference_us+=Time.get_ticks_usec()-start
 if result!=expected or _path!=reference._path or _path_index!=reference._path_index or _replan_timer!=reference._replan_timer or plans!=reference.plans:mismatches+=1
 return result
