extends SceneTree
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures += 1
func run() -> void:
 var main: Node = load("res://game/core/main.tscn").instantiate()
 root.add_child(main)
 current_scene = main
 for i in 10:await physics_frame
 var loader: AreaLoader = main.area_loader
 var world := loader.current_area
 var terrain: TerrainMap = world.get_node("Terrain")
 var entrance: Node2D = world.get_node("ForestEntrance")
 var passage: ForestPassage = entrance.get_node("Opening")
 print("FOREST at ",entrance.position)
 for y in range(-1510,-1650,-16):
  check(terrain.is_walkable_at(Vector2(576,y)),"approach "+str(y))
 check(not terrain.is_walkable_at(Vector2(400,-1640)),"left wall solid")
 check(not terrain.is_walkable_at(Vector2(750,-1640)),"right wall solid")
 check(not terrain.is_walkable_at(Vector2(576,-1700)),"back row solid")
 var ground: OverworldGround = world.get_node("Ground")
 for x in range(240,913,24):
  check(ground.covers(Vector2(x,-1840)),"back trees on island "+str(x))
 var trunks := terrain.trunk_blockers().size()
 var hp: int = loader.player.hp
 var arena: DesertStatueArena = world.get_node("DesertStatueArena")
 arena.state = DesertStatueArena.State.POSSESSED
 loader._on_forest_passage(passage)
 for i in 3:await physics_frame
 check(loader.current_area == world,"active encounter blocks passage")
 arena.state = DesertStatueArena.State.DORMANT
 loader._on_forest_passage(passage)
 for i in 5:await physics_frame
 check(loader.current_area.name == &"ForestPlaceholder","entered placeholder")
 check(loader.player.global_position.is_equal_approx(Vector2(0,96)),"safe placeholder spawn")
 check(world.get_parent()==main and not world.visible,"overworld retained hidden")
 loader._on_forest_passage(passage)
 for i in 3:await physics_frame
 check(loader.current_area.name == &"ForestPlaceholder","hidden origin ignored")
 var exit: ForestPassage = loader.current_area.get_node("Return")
 loader._on_forest_passage(exit)
 for i in 5:await physics_frame
 check(loader.current_area==world,"returned same cached overworld")
 check(loader.player.global_position.is_equal_approx(Vector2(576,-1510)),"return below opening")
 check(world.visible and world.process_mode==Node.PROCESS_MODE_INHERIT,"overworld resumed")
 check(terrain.trunk_blockers().size()==trunks,"no duplicate wall collision")
 check(loader.player.hp==hp,"player health retained")
 main.queue_free()
 for i in 5:await process_frame
 quit(failures)
