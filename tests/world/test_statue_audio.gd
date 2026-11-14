extends SceneTree
## Sunbound Sanctum statue audio: the arena plays Colin's approved cues at real
## events (possession, spear volley, statue hit, statue break) and nothing else.
## One spear cue per volley, not one per lane.

var failures := 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[statue audio] ", label, " -> ", "PASS" if ok else "FAIL")

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
	arena.set_physics_process(false)

	_check(arena.statues.size() == 12, "arena spawns 12 statues")
	_check(arena.audio != null and arena.audio.is_inside_tree(), "arena creates its audio node")
	_check(arena.audio._spear is AudioStreamPlayer2D and arena.audio._spear.stream != null, "spear voice is positional with a stream")

	# Encounter start possesses a statue: possession cue.
	arena.start_encounter()
	_check(arena.state == DesertStatueArena.State.POSSESSED, "encounter starts possessed")
	_check(arena.audio.possess_count == 1, "possession plays once on encounter start")

	arena.visiting = true
	var target: DesertStatue = null
	for s in arena.statues:
		if s != arena.possessed:
			target = s
			break
	_check(target != null, "found a non-possessed statue")

	# Hit cue on an ordinary statue.
	arena.damage_statue(target, 10, 0)
	_check(target.hp == arena.statue_max_hp - 10, "hit statue loses hp")
	_check(arena.audio.damage_count == 1, "statue hit plays the damage cue")
	_check(arena.audio.death_count == 0, "no crumble before a break")

	# Breaking the statue plays the crumble once.
	arena.damage_statue(target, 999, 0)
	_check(target.broken, "statue breaks at 0 hp")
	_check(arena.audio.damage_count == 2, "breaking hit also plays the damage cue")
	_check(arena.audio.death_count == 1, "statue break plays the crumble")

	# Hitting the possessed statue damages the boss and stuns possession.
	arena.damage_statue(arena.possessed, 10, 0)
	_check(arena.hp == arena.boss_max_hp - 10, "possessed statue routes damage to the boss")
	_check(arena.state == DesertStatueArena.State.STUNNED, "hitting the host stuns possession")
	_check(arena.audio.damage_count == 3, "host hit plays the damage cue")

	# One spear cue per volley even though a volley has many lanes.
	var volley := arena.SpearVolley.new()
	for i in 3:
		var lane := arena.SpearLane.new()
		lane.shooter = arena.statues[i + 1]
		lane.start = lane.shooter.position
		lane.end = Vector2(100, 0)
		volley.lanes.append(lane)
	for lane in volley.lanes:
		arena._fire_lane(lane, volley)
	_check(arena.audio.spear_count == 1, "volley of %d spears plays one throw cue" % volley.lanes.size())
	_check(arena.audio._spear.playing, "throw cue is actually playing")

	var volley2 := arena.SpearVolley.new()
	var lane2 := arena.SpearLane.new()
	lane2.shooter = arena.statues[4]
	lane2.end = Vector2(100, 0)
	volley2.lanes.append(lane2)
	arena._fire_lane(lane2, volley2)
	_check(arena.audio.spear_count == 2, "next volley plays the next throw cue")

	# A broken statue's lane never fires, so no cue.
	var volley3 := arena.SpearVolley.new()
	var lane3 := arena.SpearLane.new()
	lane3.shooter = target
	lane3.end = Vector2(100, 0)
	volley3.lanes.append(lane3)
	arena._fire_lane(lane3, volley3)
	_check(arena.audio.spear_count == 2, "broken statue lane stays silent")

	area.free()
	print("[statue audio] DONE failures=", failures)
	quit(1 if failures else 0)
