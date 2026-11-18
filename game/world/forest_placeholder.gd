extends Node2D
## Deliberately empty destination, with a visible, reachable south exit.
func _ready() -> void:
 var terrain := get_parent().get_node("Terrain") as TerrainMap
 var cells := {}
 for y in range(-12,13):
  for x in range(-16,17):
   if abs(x)==16 or abs(y)==12:cells[Vector2i(x,y)]=TerrainTypes.OBSTACLE
 terrain.set_cells(cells)
 queue_redraw()
func _draw() -> void:
 draw_rect(Rect2(-512,-384,1056,800),Color("132016"))
 draw_rect(Rect2(-480,-352,992,736),Color("304930"))
 draw_rect(Rect2(-48,80,96,240),Color("48643b"))
 draw_rect(Rect2(-48,288,96,32),Color("8cc057"))
