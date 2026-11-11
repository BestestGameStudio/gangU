extends SceneTree
## #365 harness: foundations for location-triggered events.
##   (A) LocationTrigger policy seam: only an armed trigger and a Player
##       body fire it; fire_count counts accepted fires; id() falls back to
##       the node name.
##   (B) production overworld places the village trigger away from arrival, so
##       entering it fires nothing.
##   (C) PRODUCTION flow: an overworld carrying a trigger + AmbushEvent is
##       mounted through Main._swap; walking the player into the trigger
##       shape (real physics body_entered) fires it once, Main emits
##       location_event_triggered, records the run fire count and the ambush
##       spawns its entries through an EventSpawner, positioned relative to
##       the trigger.
##   (D) default rule: leaving and re-entering fires again (no repeat rule
##       is assumed); a host can impose one by disarming.
##   (E) leaving the area frees the ambushers; the run-scoped fire history
##       survives the area swap.
##   (F) a trigger with no event only signals.

var failures := 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[365] ", label, " -> ", "PASS" if ok else "FAIL")

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _initialize() -> void:
	_unit_legs()
	await _flow_legs()
	print("[365] DONE failures=", failures)
	if failures == 0:
		print("RESULT: ALL PASS")
	quit(1 if failures > 0 else 0)

func _make_trigger(at: Vector2, radius: float, event: OverworldEvent, id: StringName) -> LocationTrigger:
	var t := LocationTrigger.new()
	t.name = "AmbushSpot"
	t.trigger_id = id
	t.position = at
	t.event = event
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	cs.shape = circle
	t.add_child(cs)
	return t

func _ambush() -> AmbushEvent:
	var a := AmbushEvent.new()
	a.display_name = "Test ambush"
	a.relative_to_trigger = true
	var enemy: PackedScene = load("res://scenes/enemy.tscn")
	var table: RewardTable = load("res://resources/rewards/demo_table.tres")
	a.entries = [
		SpawnEntry.new(Vector2(-140, -100), enemy, table),
		SpawnEntry.new(Vector2(140, -100), enemy, table),
	]
	return a

func _unit_legs() -> void:
	var t := LocationTrigger.new()
	t.name = "Spot"
	_check(t.id() == &"Spot", "(A) id() falls back to the node name")
	t.trigger_id = &"spot_a"
	_check(t.id() == &"spot_a", "(A) id() uses trigger_id when set")
	var fired := [0]
	t.triggered.connect(func(_t, _b): fired[0] += 1)
	var not_player := Node2D.new()
	_check(not t.try_fire(not_player), "(A) a non-Player body does not fire it")
	var p: Player = (load("res://scenes/player.tscn") as PackedScene).instantiate()
	_check(t.try_fire(p), "(A) a Player body fires an armed trigger")
	t.disarm()
	_check(not t.try_fire(p), "(A) a disarmed trigger ignores the Player")
	t.arm()
	_check(t.try_fire(p), "(A) arm() re-enables it")
	_check(t.fire_count == 2 and fired[0] == 2, "(A) fire_count and triggered count accepted fires only (%d/%d)" % [t.fire_count, fired[0]])
	not_player.free()
	p.free()
	t.free()

func _event_enemies(area: Node) -> Array:
	var sp := area.get_node_or_null("EventSpawner")
	var out: Array = []
	if sp == null:
		return out
	for n in area.get_children():
		if n is Enemy and is_instance_valid(n) and not n.is_queued_for_deletion() and n.get_meta("event", false):
			out.append(n)
	return out

func _flow_legs() -> void:
	Bestiary.save_path = "user://test365_bestiary.cfg"
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(3)
	var p: Player = main.get_node("Player")

	# (B) production village trigger does not fire at the arrival point
	var heard: Array = []
	main.area_loader.location_event_triggered.connect(func(id, _t): heard.append(id))
	main.area_loader.enter_overworld()
	await _frames(3)
	var placed := get_nodes_in_group("location_triggers").filter(func(n): return main.area_loader.current_area.is_ancestor_of(n))
	_check(placed.size() == 1 and placed[0].id() == &"abandoned_village", "(B) production overworld places the abandoned village trigger")
	_check(main.area_loader.current_area.get_node_or_null("EventSpawner") == null and heard.is_empty(), "(B) entering it fires no event")

	# (C) overworld with an authored ambush trigger, mounted the production way
	var ow: Node2D = (load("res://scenes/overworld.tscn") as PackedScene).instantiate()
	var spot := Vector2(760, 480) # east of the arrival point, clear of gates/guards
	var ambush := _ambush()
	var started: Array = []
	ambush.ambush_started.connect(func(_ctx, enemies): started.append(enemies))
	ow.add_child(_make_trigger(spot, 40.0, ambush, &"test_ambush"))
	main.area_loader._swap(ow)
	await _frames(3)
	var trig: LocationTrigger = ow.get_node("AmbushSpot")
	_check(trig.triggered.is_connected(main.area_loader._on_location_triggered), "(C) Main wired the area's trigger on mount")
	_check(trig.fire_count == 0 and heard.is_empty(), "(C) nothing fires while the player stands at the arrival point")
	p.global_position = ow.to_global(spot)
	await _frames(4)
	_check(trig.fire_count == 1, "(C) walking into the trigger shape fires it once (got %d)" % trig.fire_count)
	_check(heard == [&"test_ambush"], "(C) Main emitted location_event_triggered with the trigger id (%s)" % [heard])
	_check(main.area_loader.location_event_fire_count(&"test_ambush") == 1, "(C) Main recorded one run fire")
	var spawner := ow.get_node_or_null("EventSpawner") as EnemySpawner
	_check(spawner != null, "(C) the event spawned through an EventSpawner in the area")
	_check(started.size() == 1 and (started[0] as Array).size() == 2, "(C) the ambush started once with its 2 entries")
	var ambushers: Array = started[0] if started.size() == 1 else []
	var placed_ok := ambushers.size() == 2
	var wired_ok := true
	for e: Enemy in ambushers:
		e.set_meta("event", true)
		if e.get_parent() != ow:
			wired_ok = false
		if e._player != p:
			wired_ok = false
	if placed_ok:
		placed_ok = (ambushers[0] as Enemy).global_position.distance_to(ow.to_global(spot + Vector2(-140, -100))) < 30.0 \
			and (ambushers[1] as Enemy).global_position.distance_to(ow.to_global(spot + Vector2(140, -100))) < 30.0
	_check(placed_ok, "(C) relative_to_trigger places the ambushers around the trigger")
	_check(wired_ok, "(C) ambushers are area children and target the player")
	_check(spawner != null and spawner.total_alive() == 2, "(C) the spawner tracks both ambushers")

	# (D) default rule: no repeat rule assumed; host can impose one
	p.global_position = ow.to_global(spot + Vector2(0, 300))
	await _frames(3)
	p.global_position = ow.to_global(spot)
	await _frames(4)
	_check(trig.fire_count == 2 and main.area_loader.location_event_fire_count(&"test_ambush") == 2, "(D) re-entering fires again by default (%d)" % trig.fire_count)
	_check(started.size() == 2, "(D) and starts the event again")
	trig.disarm()
	p.global_position = ow.to_global(spot + Vector2(0, 300))
	await _frames(3)
	p.global_position = ow.to_global(spot)
	await _frames(4)
	_check(trig.fire_count == 2 and started.size() == 2, "(D) a disarmed trigger (host-imposed rule) stays quiet")

	# (E) leaving frees ambushers; run history persists
	var all_ambushers: Array = []
	for batch in started:
		all_ambushers.append_array(batch)
	p.global_position = (ow.get_node("PlayerSpawn") as Node2D).global_position
	await _frames(2)
	(ow.get_node("GateHub") as Gate)._on_body_entered(p)
	await _frames(3)
	_check(main.area_loader.current_area.name == "Hub", "(E) left through GateHub")
	_check(all_ambushers.all(func(e): return not is_instance_valid(e)), "(E) leaving the area frees every ambusher")
	_check(main.area_loader.location_event_fire_count(&"test_ambush") == 2, "(E) the run-scoped fire history survives the area swap")

	# (F) trigger with no event only signals
	var ow2: Node2D = (load("res://scenes/overworld.tscn") as PackedScene).instantiate()
	ow2.add_child(_make_trigger(spot, 40.0, null, &"bare_spot"))
	main.area_loader._swap(ow2)
	await _frames(3)
	p.global_position = ow2.to_global(spot)
	await _frames(4)
	_check(main.area_loader.location_event_fire_count(&"bare_spot") == 1 and heard.has(&"bare_spot"), "(F) an event-less trigger still signals and is recorded")
	_check(ow2.get_node_or_null("EventSpawner") == null, "(F) and spawns nothing")
