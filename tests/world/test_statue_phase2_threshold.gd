extends SceneTree
## Statue boss (Sunbound Sanctum) phase 2 trigger threshold.
## Colin's call: phase 2 starts at 75% remaining boss HP (25% damage dealt),
## not the former 50%. Boundary coverage around 75% plus a cross-through hit.

var failures := 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[statue phase2 threshold] ", label, " -> ", "PASS" if ok else "FAIL")

func _initialize() -> void:
	call_deferred("_run")

func _new_arena() -> DesertStatueArena:
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
	arena.set_physics_process(false)
	arena.start_encounter()
	return arena

func _run() -> void:
	# Boundary just above 75%: one HP short of the trigger, still phase 1.
	var above := _new_arena()
	var trigger_hp := above.boss_max_hp*3/4
	above.apply_damage(above.hp - trigger_hp - 1)
	_check(above.hp == trigger_hp + 1, "damage lands boss one HP above the 75% mark")
	_check(above.state != DesertStatueArena.State.PHASE_TWO, "one HP above 75% remaining stays in phase 1")

	# Exactly 75% remaining: the next single point of damage triggers phase 2.
	above.apply_damage(1)
	_check(above.hp == trigger_hp, "boss sits at exactly 75% remaining HP")
	_check(above.state == DesertStatueArena.State.PHASE_TWO, "75% remaining HP enters phase 2")
	var entered_state: int = above.state
	above.apply_damage(1)
	_check(above.state == entered_state, "phase 2 entry happens once, further damage keeps phase 2")
	above.get_parent().get_parent().queue_free()

	# Old threshold no longer applies: between 50% and 75% the boss is already in phase 2.
	var mid := _new_arena()
	mid.apply_damage(mid.hp - (mid.boss_max_hp/2 + mid.boss_max_hp/8)) # 62.5% remaining
	_check(mid.state == DesertStatueArena.State.PHASE_TWO, "62.5% remaining (old 50% rule would wait) is already phase 2")
	mid.get_parent().get_parent().queue_free()

	# A single large hit from full HP through the threshold still triggers phase 2.
	var cross := _new_arena()
	cross.apply_damage(cross.boss_max_hp*2/5) # 60% remaining, crossed 75% in one hit
	_check(cross.state == DesertStatueArena.State.PHASE_TWO, "one big hit crossing 75% still enters phase 2")
	cross.get_parent().get_parent().queue_free()

	await process_frame
	print("[statue phase2 threshold] DONE failures=", failures)
	quit(1 if failures else 0)
