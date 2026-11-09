extends SceneTree
## #100 acceptance driver (headless, production composition via main.tscn).
## Proves the generic data-driven per-area spawn carrier:
##   DA carrier  - DungeonA has ONE "SpawnData" child carrying exactly THREE
##                 entries at (250,280)/(576,220)/(900,280), each pairing
##                 enemy.tscn with demo_table.tres, player_path "../../Player"
##   DA mount    - the generic mounter spawns exactly those 3 enemies as
##                 children of the area at the carrier's positions
##   wiring      - each enemy's reward_table IS the demo table and its
##                 player_path resolved to Main/Player (set BEFORE add_child)
##   ordering    - enemies mount BEFORE DungeonObjective._ready scans the
##                 "enemies" group, so the objective target is 3, not 0
##   completion  - three real apply_damage kills complete dungeon_a
##   DB carrier  - #177 / O1 (human decision 2026-11-08): DungeonB carries
##                 3 mob entries and mounts them (data-driven mounter)
##   DB boss     - DungeonB's ELIMINATION objective: killing the 3 mobs
##                 spawns the Mustache Warlord (boss group, wired to the
##                 production Player); its kill clears dungeon_b and opens
##                 the LOCKED red-gate portal
## The harness duck-types the carrier (no AreaSpawnData reference) so the
## carrier legs FAIL on the old base instead of erroring at parse time.
## Gate/portal use follows the test9 direct _on_body_entered idiom - NOT
## real-input movement proof.

const EXPECTED_POSITIONS: Array[Vector2] = [Vector2(250, 280), Vector2(576, 220), Vector2(900, 280)]

var scene: Node
var p: Player
var phase := 0
var t := 0.0
var fails := 0
var mounted_positions: Array = []

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	# Enemies chase the player from their first physics frame, so the exact
	# spawn positions are captured AT MOUNT TIME via node_added (position is
	# assigned before add_child in the mounter); live positions legitimately
	# drift afterwards and are not the assertion target.
	node_added.connect(_on_node_added)

func _on_node_added(n: Node) -> void:
	if n is Enemy and scene != null and n.get_parent() == scene.current_area:
		mounted_positions.append(n.position)

func _check(label: String, ok: bool) -> void:
	if not ok:
		fails += 1
	print("[100] ", label, " -> ", "PASS" if ok else "FAIL")

func _enter_gate(gate_name: String) -> void:
	if scene.current_area.get_node_or_null(gate_name) == null:
		scene.enter_overworld() # #346: dungeon entrances live in the overworld
		mounted_positions.clear() # drop the overworld guards; the legs measure the dungeon mount
	var g: Gate = scene.current_area.get_node(gate_name)
	g._on_body_entered(p)

func _area_enemies() -> Array:
	var out: Array = []
	for e in get_nodes_in_group("enemies"):
		if scene.current_area != null and e.get_parent() == scene.current_area:
			out.append(e)
	return out

func _process(delta: float) -> bool:
	t += delta
	match phase:
		0:
			if scene.get_node_or_null("Player") != null and t > 0.3:
				p = scene.get_node("Player")
				_enter_gate("GateNormal")
				phase = 1; t = 0
		1:
			if t > 0.4:
				var area: Node = scene.current_area
				_check("DA: gate swap entered DungeonA", area.name == "DungeonA")
				var sd: Node = area.get_node_or_null("SpawnData")
				_check("DA carrier: SpawnData child present", sd != null)
				if sd != null:
					var entries: Array = sd.get("entries")
					_check("DA carrier: exactly 3 entries", entries != null and entries.size() == 3)
					_check("DA carrier: player_path header is ../../Player",
						sd.get("player_path") == NodePath("../../Player"))
					if entries != null and entries.size() == 3:
						var positions_ok := true
						var resources_ok := true
						for i in 3:
							var entry: Dictionary = entries[i]
							if entry.get("position") != EXPECTED_POSITIONS[i]:
								positions_ok = false
							var escene: PackedScene = entry.get("enemy")
							var rtable: Resource = entry.get("reward_table")
							if escene == null or escene.resource_path != "res://scenes/enemy.tscn":
								resources_ok = false
							if rtable == null or rtable.resource_path != "res://resources/rewards/demo_table.tres":
								resources_ok = false
						_check("DA carrier: exact positions (250,280)/(576,220)/(900,280)", positions_ok)
						_check("DA carrier: every entry pairs enemy.tscn with demo_table.tres", resources_ok)
				var enemies := _area_enemies()
				_check("DA mount: exactly 3 enemies as area children", enemies.size() == 3)
				var positions_ok: bool = mounted_positions.size() == 3
				for expected in EXPECTED_POSITIONS:
					if not (expected in mounted_positions):
						positions_ok = false
				var wiring_ok := true
				for e in enemies:
					if e.reward_table == null or e.reward_table.resource_path != "res://resources/rewards/demo_table.tres":
						wiring_ok = false
					if e._player != p:
						wiring_ok = false
				_check("DA mount: enemies mounted at the carrier's exact positions (captured at mount time)", positions_ok)
				_check("DA wiring: reward_table is demo_table and player_path resolved to Main/Player", wiring_ok)
				var obj: DungeonObjective = area.get_node_or_null("DungeonObjective")
				_check("ordering: objective present and targets 3 (mounted after enemies)",
					obj != null and obj.progress() == Vector2i(0, 3))
				for e in enemies:
					e.apply_damage(999) # three real kills through the damage path
				phase = 2; t = 0
		2:
			if t > 0.4:
				var obj: DungeonObjective = scene.current_area.get_node("DungeonObjective")
				_check("completion: progress 3/3 after three kills", obj.progress() == Vector2i(3, 3))
				_check("completion: dungeon_a cleared", obj.is_cleared())
				_check("completion: killed enemies freed", _area_enemies().size() == 0)
				var portal: ExitPortal = scene.current_area.get_node("ExitPortal")
				portal._on_body_entered(p) # retreat to hub
				phase = 3; t = 0
		3:
			if t > 0.4:
				_check("retreat: back in hub, same run", scene.current_area.name == "Hub")
				_enter_gate("GateRed")
				phase = 4; t = 0
		4:
			if t > 0.4:
				var area: Node = scene.current_area
				_check("DB: red gate entered DungeonB", area.name == "DungeonB")
				var sd: Node = area.get_node_or_null("SpawnData")
				_check("DB carrier: SpawnData child present", sd != null)
				if sd != null:
					var entries: Array = sd.get("entries")
					_check("DB carrier: 3 mob entries", entries != null and entries.size() == 3)
				_check("DB mount: 3 mobs", _area_enemies().size() == 3)
				var obj: DungeonObjective = area.get_node_or_null("DungeonObjective")
				_check("DB objective: ELIMINATION", obj != null and obj.objective_type == DungeonObjective.ObjectiveType.ELIMINATION)
				_check("DB objective: progress 0/4 (3 mobs + boss)", obj != null and obj.progress() == Vector2i(0, 4))
				var portal: ExitPortal = area.get_node_or_null("ExitPortal")
				_check("DB portal: locked (red gate, clear-or-die)", portal != null and portal.locked)
				_check("DB boss: none before the mobs die", get_nodes_in_group("boss").is_empty())
				for e in _area_enemies():
					e.apply_damage(999) # synthetic kills
				phase = 5; t = 0
		5:
			if t > 0.3:
				var bosses := get_nodes_in_group("boss")
				_check("DB boss: exactly one boss after the mobs", bosses.size() == 1)
				if bosses.size() == 1:
					var boss: Enemy = bosses[0] as Enemy
					_check("DB boss: is the Mustache Warlord",
						boss != null and boss.scene_file_path == "res://scenes/mustache_warlord.tscn")
					_check("DB boss: in DungeonB", boss != null and boss.get_parent() == scene.current_area)
					_check("DB boss: targets the production Player", boss != null and boss._player == p)
					if boss != null:
						boss.apply_damage(9999)
				phase = 6; t = 0
		6:
			if t > 0.3:
				var obj: DungeonObjective = scene.current_area.get_node("DungeonObjective")
				_check("DB clear: dungeon_b cleared by the boss kill", obj.is_cleared() and obj.progress() == Vector2i(4, 4))
				var portal: ExitPortal = scene.current_area.get_node("ExitPortal")
				_check("DB clear: red portal unlocked", not portal.locked)
				if fails == 0:
					print("[100] ALL PASS")
				print("[100] DONE fails=", fails)
				quit()
	return false
