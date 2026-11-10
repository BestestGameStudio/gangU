extends SceneTree
## TEMPORARY equivalence probe: dumps every area's resolved config through Main.

const SCENES := ["dungeon_a", "dungeon_b", "dungeon_c", "dungeon_d", "dungeon_e", "dungeon_maze", "dungeon_generated", "hub", "overworld"]
const ENTRIES := [-1, 0, 1, 2]
var _lines: PackedStringArray = []

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _out(s: String) -> void:
	_lines.append(s)

func _p(r: Resource) -> String:
	return r.resource_path if r != null else "null"

func _set_entry(main: Node, t: int) -> void:
	main._entry_gate_type = t

func _get_entry(main: Node) -> int:
	return main._entry_gate_type

func _set_rolls(main: Node, rolls: Dictionary) -> void:
	main._offering_rolls = rolls

func _music(main: Node) -> String:
	var parts: PackedStringArray = []
	for n in main.find_children("*", "AudioStreamPlayer", true, false):
		var a := n as AudioStreamPlayer
		if not (a.playing or a.stream_paused):
			continue
		var path := _p(a.stream)
		if path.contains("boss1") or path.contains("boss2"):
			path = "BOSS"
		var loop: bool = a.stream is AudioStreamOggVorbis and (a.stream as AudioStreamOggVorbis).loop
		parts.append("%s vol=%.1f paused=%s loop=%s" % [path.get_file(), a.volume_db, a.stream_paused, loop])
	parts.sort()
	return "[" + ", ".join(parts) + "]"

func _dump_area(main: Node, tag: String) -> void:
	var area: Node = main.current_area
	_out("%s area=%s" % [tag, area.name])
	var obj := area.get_node_or_null("DungeonObjective") as DungeonObjective
	if obj == null:
		_out("  objective=none")
	else:
		_out("  objective id=%s type=%d boss=%s spawn=%s waves_enemy=%s table=%s wave_boss=%s boss_waves=%s points=%s nav=%s failed_conns=%d completed_conns=%d boss_conns=%d" % [
			obj.dungeon_id, obj.objective_type, _p(obj.boss_scene), obj.boss_spawn_position,
			_p(obj.wave_enemy_scene), _p(obj.wave_reward_table), _p(obj.wave_boss_scene), obj.boss_waves,
			(obj.wave_spawn_points.size() if area.name == &"DungeonMaze" else obj.wave_spawn_points), obj.wave_nav != null,
			obj.objective_failed.get_connections().size(), obj.objective_completed.get_connections().size(),
			obj.boss_spawned.get_connections().size()])
	var portal := area.get_node_or_null("ExitPortal") as ExitPortal
	if portal == null:
		_out("  portal=none")
	else:
		_out("  portal pos=%s locked=%s objpath=%s red=%s beast=%s" % [portal.position, portal.locked, portal.objective_path, portal.red_portal_look, portal.beast_portal_look])
	var item := area.get_node_or_null("ReviveItem") as Node2D
	_out("  revive=%s" % (str(item.position) if item else "none"))
	_out("  bosses=%d enemies=%d" % [get_nodes_in_group("boss").size(), get_nodes_in_group("enemies").size()])
	_out("  music=%s" % _music(main))

func _initialize() -> void:
	Bestiary.save_path = "user://zz_dump_bestiary.cfg"
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(3)
	var p: Player = main.get_node("Player")
	p.max_hp = 999999
	_out("boot music=%s" % _music(main))
	for s: String in SCENES:
		for e: int in ENTRIES:
			p.hp = p.max_hp
			main._load_hub()
			await _frames(2)
			_set_entry(main, e)
			main._swap((load("res://scenes/%s.tscn" % s) as PackedScene).instantiate())
			await _frames(30)
			_dump_area(main, "%s entry=%d" % [s, e])
			if get_nodes_in_group("boss").size() > 0 and s != "dungeon_e" and s != "dungeon_maze":
				for b in get_nodes_in_group("boss"):
					b.apply_damage(99999)
				await _frames(130)
				_dump_area(main, "%s entry=%d AFTER-KILL" % [s, e])
	for id: StringName in FastTravelRoutes.DUNGEONS:
		_out("route %s label=%s scene=%s" % [id, FastTravelRoutes.label_for(id), FastTravelRoutes.DUNGEONS[id]["scene"]])
	for rolls: Dictionary in [{&"GateNormal": Gate.GateType.NORMAL, &"GateRed": Gate.GateType.RED}, {&"GateNormal": Gate.GateType.RED, &"GateRed": Gate.GateType.NORMAL}]:
		for id: StringName in FastTravelRoutes.DUNGEONS:
			p.hp = p.max_hp
			main._load_hub()
			await _frames(2)
			_set_rolls(main, rolls.duplicate())
			main.cleared_dungeons[id] = true
			main._commit_fast_travel(id)
			await _frames(30)
			_out("fasttravel %s rolls=%s entry=%d" % [id, rolls.values(), _get_entry(main)])
			_dump_area(main, "  ft %s" % id)
	main._load_hub()
	await _frames(2)
	main.enter_overworld()
	await _frames(3)
	var ids: Array = []
	for g: Gate in get_nodes_in_group("gates"):
		var sc := g.target_scene()
		ids.append("%s->%s" % [g.name, FastTravelRoutes.id_for_scene(sc.resource_path) if sc else &"-"])
	ids.sort()
	_out("overworld gates %s" % [ids])
	_out("overworld music=%s" % _music(main))
	var f := FileAccess.open(OS.get_environment("DUMP_OUT"), FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	print("DUMP DONE lines=", _lines.size())
	quit(0)
