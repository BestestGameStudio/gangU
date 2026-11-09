extends SceneTree
## #369 harness: DEFENSE wave progress bar - top-center bar with one icon per
## wave (skull for boss waves), fill tracks cleared waves, countdown under the
## bar shows when the next wave is about to spawn.
## Run: godot --headless --path . -s scripts/test369_defense_wave_bar.gd
##
## Legs:
##   (A) hud.tscn mounts a hidden DefenseWaveBar; it stays hidden in the hub.
##   (B) production flow: entering the defense shows the bar with one icon
##       per wave, fill 0, and the countdown running from first_wave_delay.
##   (C) clearing wave 1 fills one segment; boss_waves marks skulls (#368
##       hook) without changing wave composition.
##   (D) the countdown runs while the next wave is pending (clear break and
##       the periodic interval) and hides once no wave is pending; a cleared
##       defense leaves the bar full and visible.
##   (E) failure: core destroyed -> countdown hides, bar stays.
##   (F) leaving the dungeon hides the bar again.

var failures := 0

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[369] ", name, " -> PASS")
	else:
		failures += 1
		print("[369] ", name, " -> FAIL")

func _physics(n: int) -> void:
	for i in n:
		await physics_frame

func _initialize() -> void:
	Bestiary.save_path = "user://test369_bestiary.cfg"
	_leg_scene()
	await _leg_flow()
	await _leg_failure()
	print("[369] DONE failures=", failures)
	print("RESULT: ALL PASS" if failures == 0 else "RESULT: FAIL")
	quit(failures)

func _leg_scene() -> void:
	var hud: Node = (load("res://scenes/hud.tscn") as PackedScene).instantiate()
	var bar := hud.get_node_or_null("DefenseWaveBar") as DefenseWaveBar
	_check(bar != null, "(A) hud.tscn mounts a DefenseWaveBar")
	if bar != null:
		_check(not bar.visible, "(A) bar hidden by default")
		_check(bar.get_node_or_null("Countdown") == null, "(A) countdown label is built on ready, not instanced")
	hud.free()

func _wave_enemies(area: Node) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for e in get_nodes_in_group(&"enemies"):
		if e.get_parent() == area and (e as Enemy).hp > 0:
			out.append(e)
	return out

func _kill_all(area: Node) -> void:
	for e in _wave_enemies(area):
		e.apply_damage(99999)
	await _physics(2)

func _countdown_secs(bar: DefenseWaveBar) -> int:
	var label := bar.get_node("Countdown") as Label
	if not label.visible or not label.text.begins_with("Next wave in "):
		return -1
	return label.text.trim_prefix("Next wave in ").trim_suffix("s").to_int()

func _enter_defense(main: Node) -> void:
	main.enter_overworld()
	await _physics(4)
	var gate := main.current_area.get_node("GateDefense") as Gate
	gate._on_body_entered(main.get_node("Player"))
	await _physics(4)

func _leg_flow() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	var p: Player = main.get_node("Player")
	p.max_hp = 100000
	p.hp = 100000
	await _physics(30)
	var hud := main.find_child("HUD", true, false)
	var bar := hud.get_node("DefenseWaveBar") as DefenseWaveBar
	_check(not bar.visible, "(A) bar hidden in the overworld (no defense objective)")
	await _enter_defense(main)
	var area: Node = main.current_area
	_check(area.name == "DungeonE", "(B) GateDefense enters DungeonE (got %s)" % area.name)
	var obj := area.get_node_or_null("DungeonObjective") as DungeonObjective
	if obj == null:
		main.queue_free()
		current_scene = null
		return
	await _physics(30) # HUD discovery is throttled at 0.25s
	_check(bar.visible, "(B) bar visible in a defense mission")
	_check(obj.total_waves() == obj.wave_count and obj.total_waves() >= 3, "(B) total waves = %d" % obj.total_waves())
	_check(bar.fill_fraction() == 0.0, "(B) fill starts empty")
	var s0 := _countdown_secs(bar)
	_check(s0 >= 1 and s0 <= int(obj.first_wave_delay) + 1, "(B) countdown running before wave 1 (%ds)" % s0)
	await _physics(45)
	var s1 := _countdown_secs(bar)
	_check(s1 >= 0 and s1 < s0, "(B) countdown ticks down (%ds -> %ds)" % [s0, s1])
	for wave in range(1, obj.total_waves() + 1):
		_check(bar.icon_kind(wave) == "enemy", "(B) wave %d icon is an enemy glyph" % wave)

	# (C) fill tracks cleared waves; boss_waves marks skulls (#368 hook).
	await _physics(int(obj.first_wave_delay * 60.0) + 10)
	_check(obj.waves_spawned() == 1, "(C) wave 1 spawned on its own")
	await _kill_all(area)
	_check(obj.progress().x == 1, "(C) wave 1 cleared counts")
	await _physics(2)
	var frac := bar.fill_fraction()
	_check(frac > 0.19 and frac < 0.21, "(C) fill is one of %d segments (%.2f)" % [obj.total_waves(), frac])
	obj.boss_waves = [3]
	_check(bar.icon_kind(3) == "skull" and bar.icon_kind(2) == "enemy", "(C) boss_waves=[3] marks only wave 3 as a skull")
	_check(obj.wave_size(3) == obj.wave_base_size + 2 * obj.wave_size_growth, "(C) marking a boss wave changes no wave sizes")

	# (D) countdown while pending; full bar on completion.
	var s2 := _countdown_secs(bar)
	_check(s2 >= 1 and s2 <= int(obj.clear_break) + 1, "(D) countdown shows the clear break (%ds)" % s2)
	await _physics(int(obj.clear_break * 60.0) + 10)
	_check(obj.waves_spawned() == 2, "(D) wave 2 arrived after the break")
	_check(_countdown_secs(bar) >= 1, "(D) countdown keeps running toward wave 3 while wave 2 lives")
	while obj.waves_spawned() < obj.total_waves():
		obj.spawn_next_wave()
	await _physics(2)
	_check(_countdown_secs(bar) == -1, "(D) countdown hidden once every wave has spawned")
	await _kill_all(area)
	_check(obj.is_cleared(), "(D) defense complete")
	await _physics(2)
	_check(bar.visible and bar.fill_fraction() == 1.0, "(D) bar stays, full, after completion")
	_check(_countdown_secs(bar) == -1, "(D) no countdown after completion")

	# (F) leaving the dungeon hides the bar.
	main.enter_overworld()
	await _physics(30)
	_check(not bar.visible, "(F) bar hidden again after leaving the defense")
	main.queue_free()
	current_scene = null
	await process_frame

func _leg_failure() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	var p: Player = main.get_node("Player")
	p.max_hp = 100000
	p.hp = 100000
	await _enter_defense(main)
	var area: Node = main.current_area
	var obj := area.get_node("DungeonObjective") as DungeonObjective
	var hud := main.find_child("HUD", true, false)
	var bar := hud.get_node("DefenseWaveBar") as DefenseWaveBar
	await _physics(30)
	_check(bar.visible and _countdown_secs(bar) >= 1, "(E) countdown running before the failure")
	obj.spawn_next_wave()
	await _physics(2)
	obj.core().apply_damage(999999)
	await _physics(30)
	_check(obj.is_failed(), "(E) core destroyed -> failed")
	_check(bar.visible, "(E) bar stays up after the failure")
	_check(_countdown_secs(bar) == -1, "(E) no countdown once the defense has failed")
	main.queue_free()
	current_scene = null
	await process_frame
