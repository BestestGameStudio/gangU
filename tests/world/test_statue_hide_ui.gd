extends SceneTree
## #684: after the Sand General falls, the boss panel (title, HP bar,
## details) and the world-space bar over the kneeling sprite hide; the
## death pose and the player's own HUD are untouched.

var failures := 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[statue hide ui] ", label, " -> ", "PASS" if ok else "FAIL")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var area := Node2D.new()
	root.add_child(area)
	var player: Player = load("res://game/player/player.tscn").instantiate()
	player.name = "Player"
	area.add_child(player)
	player.set_physics_process(false)
	var region := Node2D.new()
	area.add_child(region)
	var arena := DesertStatueArena.new()
	region.add_child(arena)
	arena.start_encounter()
	await process_frame

	# Mid-fight the boss panel shows for a visiting player.
	arena._physics_process(0.016)
	_check(arena._ui.visible, "boss panel visible while the fight runs")

	# Win the fight; the whole fight UI hides on the next tick.
	arena.apply_damage(arena.hp)
	_check(arena.hp == 0, "boss HP reaches 0")
	arena._physics_process(0.016)
	_check(not arena._ui.visible, "boss panel (title + HP bar + details) hidden after the win")
	_check(arena.visiting, "player still counts as visiting - player HUD untouched")

	# The kneeling general keeps its death pose: statue stays, not broken,
	# and the world-space bar's draw condition is off.
	var general := arena.possessed
	_check(is_instance_valid(general), "defeated general remains in the arena")
	if is_instance_valid(general):
		_check(not general.broken, "death pose kept (statue not broken/crumbled)")
		var bar_shown: bool = general.hp < general.max_hp \
			and not (general.arena is DesertStatueArena and (general.arena as DesertStatueArena)._won) \
			and (not general._phase_two() or (general.arena as DesertStatueArena).general_height <= 120.0)
		_check(not bar_shown, "world-space bar over the fallen sprite hidden")
	area.queue_free()

	await process_frame
	print("[statue hide ui] DONE failures=", failures)
	quit(1 if failures else 0)
