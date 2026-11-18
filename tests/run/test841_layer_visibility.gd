extends SceneTree
## #841: parking must preserve each layer's authored/runtime visibility.
var failures := 0
func check(value: bool, message: String) -> void:
 print('[841] ', 'PASS ' if value else 'FAIL ', message)
 if not value: failures += 1
func _initialize() -> void: run.call_deferred()
func run() -> void:
 var loader := AreaLoader.new()
 root.add_child(loader)
 var area := Node2D.new()
 root.add_child(area)
 loader._run_overworld = area
 var shown := CanvasLayer.new()
 var hidden := CanvasLayer.new()
 area.add_child(shown);area.add_child(hidden);hidden.hide()
 loader._set_overworld_layers(true)
 check(shown.visible and not hidden.visible, 'first mount leaves visible and hidden layers unchanged')
 for trip in 3:
  loader._set_overworld_layers(false)
  check(not shown.visible and not hidden.visible, 'all parked layers hidden trip%d'%trip)
  loader._set_overworld_layers(false)
  loader._set_overworld_layers(true)
  check(shown.visible and not hidden.visible, 'restore original states after repeated park trip%d'%trip)
  check(loader._parked_layers.is_empty(), 'snapshot cleared after restore')
 shown.hide();hidden.show()
 loader._set_overworld_layers(false)
 shown.free()
 var fresh := CanvasLayer.new();area.add_child(fresh);fresh.hide()
 loader._set_overworld_layers(true)
 check(hidden.visible and not fresh.visible, 'freed layer safe, newly added hidden layer not forced visible')
 area.free();loader.free()
 var main = load('res://game/core/main.tscn').instantiate()
 root.add_child(main);current_scene=main
 await process_frame
 main.area_loader.enter_overworld()
 await process_frame
 var arena=main.area_loader.current_area.get_node('DesertStatueArena')
 check(not arena.is_active() and not arena._ui.visible, 'production dormant arena starts hidden')
 for trip in 2:
  main.area_loader._swap(load('res://game/world/dungeon_a.tscn').instantiate())
  await process_frame
  main.area_loader.enter_overworld()
  await process_frame
  check(not arena.is_active() and not arena._ui.visible, 'production dormant arena stays hidden after area trip%d'%trip)
 main.queue_free()
 await process_frame
 print('[841] DONE failures=',failures)
 quit(1 if failures else 0)
