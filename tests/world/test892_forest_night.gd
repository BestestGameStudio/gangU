extends SceneTree
var failures := 0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, label: String) -> void:
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures += 1
func run() -> void:
 var main: Node=load("res://game/core/main.tscn").instantiate()
 root.add_child(main)
 current_scene=main
 for i in 10:await process_frame
 var loader: AreaLoader=main.area_loader
 var world := loader.current_area
 var clock := DayNightClock.find_clock(self)
 clock.set_process(false)
 clock.time_of_day = 0.5
 var passage: ForestPassage=world.get_node("ForestEntrance/Opening")
 loader._on_forest_passage(passage)
 for i in 5:await process_frame
 var forest := loader.current_area
 check(forest.name==&"ForestPlaceholder","forest entered")
 var night := forest.get_node("PermanentNight") as CanvasModulate
 check(night.get_script()==null,"night tint has no cycle driver")
 check(night.visible,"forest night tint visible")
 var floor: Node2D=forest.get_node("Floor")
 var mat := floor.material as ShaderMaterial
 check(mat.shader.resource_path=="res://game/world/terrain/ground_paint.gdshader","exact overworld ground shader reused")
 check(mat.get_shader_parameter("types").get_image().get_pixel(0,0).r==0.0,"grass-only lattice")
 check(floor.PAINT_RECT.encloses(Rect2(-2000,-2000,4000,4000)),"grass covers beyond walk bounds without panel edge")
 for time in [0.0,0.18,0.29,0.5,0.72,0.9]:
  clock.time_of_day=time
  await process_frame
  check(night.color.is_equal_approx(DayNightClock._sample_tint(0.0)),"forest stays midnight at clock "+str(time))
 check(is_equal_approx(clock.time_of_day,0.9),"scene did not rewrite shared clock")
 clock.advance(60.0)
 check(is_zero_approx(clock.time_of_day),"shared clock can still advance in forest")
 var exit: ForestPassage=forest.get_node("Return")
 loader._on_forest_passage(exit)
 for i in 5:await process_frame
 check(loader.current_area==world,"same overworld resumed")
 check(not is_instance_valid(forest),"forest and local night tint freed on return")
 check(world.get_node("DayNightTint").color.is_equal_approx(clock.tint_color()),"overworld follows shared clock after return")
 main.queue_free()
 for i in 5:await process_frame
 quit(failures)
