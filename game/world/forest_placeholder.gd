extends Node2D
## Same painted grass shader as the overworld, under a scene-local night tint.
const GROUND_SHADER := preload("res://game/world/terrain/ground_paint.gdshader")
const NIGHT := Color(0.30, 0.33, 0.55) # Existing DayNightClock midnight key.
# Extends well past the unchanged walk bounds so no floor-panel edge is visible.
const PAINT_RECT := Rect2(-8192, -8192, 16384, 16384)
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
 var mat := ShaderMaterial.new()
 mat.shader = GROUND_SHADER
 # The shared shader clamps type samples. A grass-only lattice keeps its
 # original palette/noise/art-pixel scale without importing other biomes.
 var grass := Image.create(1,1,false,Image.FORMAT_R8)
 grass.fill(Color8(DualGrid.T.GRASS,0,0))
 mat.set_shader_parameter("types",ImageTexture.create_from_image(grass))
 mat.set_shader_parameter("cliff_edges",preload("res://assets/sprites/terrain/terrace_ground_edges.png"))
 var flat := Image.create(1,1,false,Image.FORMAT_RGB8)
 flat.fill(Color.BLACK)
 mat.set_shader_parameter("relief",ImageTexture.create_from_image(flat))
 material = mat
 queue_redraw()
func _draw() -> void:
 draw_rect(PAINT_RECT,Color.WHITE)
