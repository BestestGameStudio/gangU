extends SceneTree
## #512 harness: the abandoned village's run-once guard reads the run-scoped
## location-event history on Main's AreaLoader (moved off Main by the split).
##   (A) a bare village outside a Main has no history and may fire.
##   (B) in a real run the first entry fires and AreaLoader records it.
##   (C) re-arming the same village instance does not let it fire again.
##   (D) a fresh overworld instance in the same run does not fire it again.

var failures := 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[512v] ", label, " -> ", "PASS" if ok else "FAIL")

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _initialize() -> void:
	await _run()
	print("[512v] DONE failures=", failures)
	if failures == 0:
		print("RESULT: ALL PASS")
	quit(1 if failures > 0 else 0)

func _village(area: Node) -> AbandonedVillage:
	for n in get_nodes_in_group("location_triggers"):
		if n is AbandonedVillage and area.is_ancestor_of(n):
			return n
	return null

func _run() -> void:
	Bestiary.save_path = "user://test512_village_bestiary.cfg"
	var p: Player = (load("res://scenes/player.tscn") as PackedScene).instantiate()

	# (A) bare village, no Main above it
	var holder := Node2D.new()
	root.add_child(holder)
	var bare := AbandonedVillage.new()
	holder.add_child(bare)
	_check(bare.should_fire(p), "(A) a bare village with no run history may fire")
	holder.queue_free()
	p.free()
	await _frames(1)

	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(3)
	var player: Player = main.get_node("Player")
	var loader: AreaLoader = main.area_loader

	# (B) first entry fires and is recorded on AreaLoader
	loader.enter_overworld()
	await _frames(3)
	var v := _village(loader.current_area)
	_check(v != null, "(B) the production overworld mounts the village")
	if v == null:
		return
	_check(v.should_fire(player), "(B) the village may fire before any run fire")
	_check(v.try_fire(player), "(B) the first entry fires the village")
	_check(loader.location_event_fire_count(&"abandoned_village") == 1, "(B) AreaLoader recorded one run fire")
	await _frames(3)

	# (C) same instance, re-armed (leave and re-enter)
	v.arm()
	_check(not v.should_fire(player), "(C) a re-armed village does not fire again this run")
	_check(not v.try_fire(player), "(C) try_fire is rejected")

	# (D) a fresh overworld instance in the same run
	loader.enter_overworld()
	await _frames(3)
	var v2 := _village(loader.current_area)
	_check(v2 != null and v2 != v, "(D) a fresh overworld mounts a new village instance")
	if v2 != null:
		_check(not v2.should_fire(player), "(D) the fresh village does not fire again this run")
	_check(loader.location_event_fire_count(&"abandoned_village") == 1, "(D) the run fire count stayed at one")
