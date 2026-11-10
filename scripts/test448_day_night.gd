extends SceneTree
## #448 acceptance harness: a root-parked day/night clock (keeps running in
## dungeons and across reloads), ~10 minute cycle, overworld CanvasModulate
## tint follows it, gate PointLight2D untouched. Run:
## godot --headless --path . -s scripts/test448_day_night.gd

var failures := 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("[448] ", label, " -> PASS")
	else:
		failures += 1
		print("[448] ", label, " -> FAIL")

func _initialize() -> void:
	# (1) Cycle and wrapping.
	_check(DayNightClock.CYCLE_SECONDS == 600.0, "(1) full cycle is 600s (~10 minutes)")
	var clock := DayNightClock.new()
	clock.time_of_day = 0.35
	clock.advance(300.0) # half a cycle
	_check(is_equal_approx(clock.time_of_day, 0.85), "(1) advance half a cycle (got %.3f)" % clock.time_of_day)
	clock.advance(300.0) # wraps
	_check(is_equal_approx(clock.time_of_day, 0.35), "(1) wraps at the end of the cycle (got %.3f)" % clock.time_of_day)
	clock.advance(-700.0) # negative deltas stay in range too
	_check(is_equal_approx(clock.time_of_day, 0.35 - 700.0 / 600.0 + 2.0) or (clock.time_of_day >= 0.0 and clock.time_of_day < 1.0), "(1) time stays in [0,1)")

	# (2) Tint ramp: noon is unmodified daylight, midnight is a dark blue,
	# sunrise/sunset warm, and the ramp has no jumps.
	var noon := DayNightClock._sample_tint(0.5)
	_check(noon.r > 0.95 and noon.g > 0.95 and noon.b > 0.95, "(2) noon tint is white (got %s)" % noon)
	var midnight := DayNightClock._sample_tint(0.0)
	_check(midnight.r < 0.5 and midnight.b > midnight.r, "(2) midnight tint is dark blue (got %s)" % midnight)
	var sunrise := DayNightClock._sample_tint(0.29)
	_check(sunrise.r > sunrise.b, "(2) sunrise tint is warm (got %s)" % sunrise)
	var sunset := DayNightClock._sample_tint(0.72)
	_check(sunset.r > sunset.b, "(2) sunset tint is warm (got %s)" % sunset)
	var prev := DayNightClock._sample_tint(0.0)
	var max_step := 0.0
	for i in range(1, 400):
		var c := DayNightClock._sample_tint(float(i) / 400.0)
		max_step = maxf(max_step, absf(c.r - prev.r) + absf(c.g - prev.g) + absf(c.b - prev.b))
		prev = c
	_check(max_step < 0.05, "(2) tint ramp is continuous (max step %.4f)" % max_step)

	# (3) Parking: ensure() is idempotent, root-parked, and the clock
	# survives reload_current_scene (keeps running through death/dungeons).
	var c1 := DayNightClock.ensure(self)
	await process_frame
	await process_frame
	var c2 := DayNightClock.ensure(self)
	_check(c1 == c2, "(3) ensure() returns the one shared clock")
	_check(c1.get_parent() == root, "(3) clock is parked on the tree root")
	c1.time_of_day = 0.9
	_check(not c1.is_in_group(RunManager.RUN_STATE_GROUP), "(3) clock is NOT run state (does not reset on death - flagged for Daniel)")
	RunManager.reset_persistent_run_state(self)
	_check(is_equal_approx(c1.time_of_day, 0.9), "(3) run-state reset leaves the clock alone")
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	reload_current_scene()
	await process_frame
	await process_frame
	var c3 := DayNightClock.find_clock(self)
	_check(c3 == c1, "(3) same clock instance survives a scene reload")
	_check(c3 != null and c3.time_of_day > 0.89, "(3) time kept (and kept advancing) across the reload")
	current_scene = null
	scene.queue_free()

	# (4) The overworld scene carries a CanvasModulate tint driver that
	# follows the clock.
	var area: Node = load("res://scenes/overworld.tscn").instantiate()
	root.add_child(area)
	await process_frame
	await process_frame
	var mod: CanvasModulate = null
	for n in area.find_children("*", "CanvasModulate", true, false):
		mod = n
	_check(mod != null, "(4) overworld has a CanvasModulate")
	if mod != null:
		_check(mod is DayNightTint, "(4) it is driven by the day/night tint script")
		c1.time_of_day = 0.0
		await process_frame
		await process_frame
		_check(mod.color.is_equal_approx(DayNightClock._sample_tint(0.0)), "(4) tint follows the clock at midnight (got %s)" % mod.color)
		c1.time_of_day = 0.5
		await process_frame
		await process_frame
		_check(mod.color.is_equal_approx(Color.WHITE), "(4) tint is unmodified daylight at noon")

	# (5) Gate/portal lighting untouched by the tint work: the gate still
	# carries its PointLight2D with its authored energy.
	var gate: Node = load("res://scenes/gate.tscn").instantiate()
	root.add_child(gate)
	var light: PointLight2D = null
	for n in gate.find_children("*", "PointLight2D", true, false):
		light = n
	_check(light != null and light.energy > 0.0, "(5) gate PointLight2D present and lit")
	gate.queue_free()
	area.queue_free()
	c1.queue_free()

	print("[448] failures=%d" % failures)
	if failures > 0:
		print("[448] FAILURES PRESENT")
	else:
		print("[448] ALL PASS")
	quit(failures)
