extends TerrainPath
static var elapsed_us: int=0
static var calls: int=0
func steer(map: TerrainMap, pos: Vector2, previous: Vector2, desired: Vector2, dest: Vector2, speed: float, delta: float, can_swim: bool = false, detour_unwalkable: bool = false) -> Vector2:
 var start:=Time.get_ticks_usec()
 var result:=super(map,pos,previous,desired,dest,speed,delta,can_swim,detour_unwalkable)
 elapsed_us+=Time.get_ticks_usec()-start;calls+=1
 return result
