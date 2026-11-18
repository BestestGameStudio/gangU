extends Node2D
## Empty destination with existing game grass and a permanent midnight tint.
## Scene-local CanvasModulate is static, never drives the shared clock.
const GRASS: Texture2D = preload("res://assets/sprites/terrain/dualgrid_variants_grass.png")
const NIGHT := Color(0.30, 0.33, 0.55) # Existing DayNightClock midnight key.
var grass_tiles: Array[Rect2] = []
func _ready() -> void:
 texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
 var night := get_parent().get_node("PermanentNight") as CanvasModulate
 night.color = NIGHT
 var terrain := get_parent().get_node("Terrain") as TerrainMap
 var cells := {}
 for y in range(-12,13):
  for x in range(-16,17):
   if abs(x)==16 or abs(y)==12:cells[Vector2i(x,y)]=TerrainTypes.OBSTACLE
 terrain.set_cells(cells)
 for y in range(-352,384,64):
  for x in range(-480,512,64):
   grass_tiles.append(Rect2(x,y,min(64,512-x),min(64,384-y)))
 queue_redraw()
func _draw() -> void:
 draw_rect(Rect2(-512,-384,1056,800),Color("132016"))
 for i in grass_tiles.size():
  var tile := grass_tiles[i]
  var variant := (int(tile.position.x/64)*13+int(tile.position.y/64)*7)&7
  draw_texture_rect_region(GRASS,tile,Rect2(variant*64,0,tile.size.x,tile.size.y))
 draw_rect(Rect2(-48,80,96,240),Color("48643b"))
 draw_rect(Rect2(-48,288,96,32),Color("8cc057"))
