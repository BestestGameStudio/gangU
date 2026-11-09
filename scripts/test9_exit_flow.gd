extends SceneTree
## #9 acceptance driver (headless, local composition).
## PRODUCTION (main.tscn composition): normal-dungeon DungeonA mounts an
## UNLOCKED exit portal (retreat anytime); using it returns to the hub in the
## same run (HP + SpellCaster instance retained); death restarts the run.
## FIXTURE (clearly labeled): red-dungeon lock-in regression - a LOCKED
## ExitPortal wired to a DungeonObjective in the #8 fixture scene
## test_dungeon_clear.tscn; unlocks exactly on objective completion.
## Enemy kills are synthetic apply_damage calls - NOT player combat proof
## (the PR's browser video carries the real-input proof).
var scene: Node
var p: Player
var caster: SpellCaster
var phase := 0
var t := 0.0
var fixture: Node
var fixture_portal: ExitPortal
var fixture_entered := false

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	p = scene.get_node("Player")
	caster = p.get_node("SpellCaster")

func _enter_gate(gate_name: String) -> void:
	if scene.current_area.get_node_or_null(gate_name) == null:
		scene.enter_overworld() # #346: dungeon entrances live in the overworld
	var g: Gate = scene.current_area.get_node(gate_name)
	g._on_body_entered(p)

func _process(delta: float) -> bool:
	t += delta
	match phase:
		0:
			if t > 0.3:
				p.apply_damage(58) # HP 42 as retention probe
				_enter_gate("GateNormal")
				phase = 1; t = 0
		1:
			if t > 0.4:
				var area = scene.current_area
				var portal: ExitPortal = area.get_node_or_null("ExitPortal")
				var obj = area.get_node_or_null("DungeonObjective")
				print("[9] PROD after NORMAL gate area=", area.name, " portal=", portal != null,
					" locked=", portal.locked if portal else "?", " objective=", obj.progress() if obj else "?",
					" -> ", "PASS" if area.name == "DungeonA" and portal and not portal.locked and obj and obj.progress() == Vector2i(0, 3) else "FAIL")
				portal._on_body_entered(p)
				phase = 2; t = 0
		2:
			if t > 0.4:
				print("[9] PROD normal retreat area=", scene.current_area.name, " hp=", p.hp,
					" same_caster=", p.get_node("SpellCaster") == caster,
					" -> ", "PASS" if scene.current_area.name == "Hub" and p.hp == 42 and p.get_node("SpellCaster") == caster else "FAIL")
				# --- labeled FIXTURE: red lock-in regression (not production config) ---
				fixture = load("res://scenes/test_dungeon_clear.tscn").instantiate()
				fixture_portal = load("res://scenes/exit_portal.tscn").instantiate()
				fixture_portal.locked = true
				fixture_portal.objective_path = NodePath("../DungeonObjective")
				fixture_portal.entered.connect(func(_pt): fixture_entered = true)
				fixture.add_child(fixture_portal)
				root.add_child(fixture)
				phase = 3; t = 0
		3:
			if t > 0.4:
				var obj = fixture.get_node_or_null("DungeonObjective")
				print("[9] FIXTURE red lock-in: portal locked=", fixture_portal.locked, " objective=", obj.progress() if obj else "?",
					" -> ", "PASS" if fixture_portal.locked and obj and obj.progress() == Vector2i(0, 3) else "FAIL")
				var fp: Player = fixture.get_node_or_null("Player")
				if fp:
					fixture_portal._on_body_entered(fp) # must be ignored while locked
				print("[9] FIXTURE locked entry ignored -> ", "PASS" if not fixture_entered else "FAIL")
				for e in fixture.get_tree().get_nodes_in_group("enemies"):
					e.apply_damage(999) # synthetic fixture kills
				phase = 4; t = 0
		4:
			if t > 0.4:
				var obj = fixture.get_node("DungeonObjective")
				print("[9] FIXTURE cleared=", obj.is_cleared(), " portal locked=", fixture_portal.locked,
					" -> ", "PASS" if obj.is_cleared() and not fixture_portal.locked else "FAIL")
				var fp: Player = fixture.get_node_or_null("Player")
				if fp:
					fixture_portal._on_body_entered(fp)
				print("[9] FIXTURE unlocked entry emits -> ", "PASS" if fixture_entered else "FAIL")
				fixture.queue_free()
				# back to production: death restarts the run
				p.apply_damage(999)
				phase = 5; t = 0
		5:
			if current_scene != null and current_scene != scene and t > 0.4:
				scene = current_scene
				p = scene.get_node("Player")
				caster = p.get_node("SpellCaster")
				print("[9] PROD death restart area=", scene.current_area.name, " hp=", p.hp,
					" -> ", "PASS" if scene.current_area.name == "Hub" and p.hp == 100 else "FAIL")
				_enter_gate("GateRed")
				phase = 6; t = 0
		6:
			if t > 0.4:
				var area = scene.current_area
				var portal: ExitPortal = area.get_node_or_null("ExitPortal")
				# #177 / O1 (2026-11-08): DungeonB now has an ELIMINATION objective,
				# so its portal is LOCKED (D12 clear-or-die) until the Warlord dies.
				print("[9] PROD after RED gate area=", area.name, " portal=", portal != null,
					" locked=", portal.locked if portal else "?",
					" -> ", "PASS" if area.name == "DungeonB" and portal and portal.locked else "FAIL")
				if portal:
					portal._on_body_entered(p) # must be ignored while locked
				for e in get_nodes_in_group("enemies"):
					e.apply_damage(999) # synthetic kills: mobs -> boss spawns
				phase = 61; t = 0
		61:
			if t > 0.3:
				print("[9] PROD red locked entry ignored -> ", "PASS" if scene.current_area.name == "DungeonB" else "FAIL")
				for b in get_nodes_in_group("boss"):
					b.apply_damage(9999) # synthetic Warlord kill
				phase = 62; t = 0
		62:
			if t > 0.3:
				var portal2: ExitPortal = scene.current_area.get_node_or_null("ExitPortal")
				print("[9] PROD red cleared -> portal unlocked -> ", "PASS" if portal2 and not portal2.locked else "FAIL")
				if portal2:
					portal2._on_body_entered(p)
				phase = 7; t = 0
		7:
			if t > 0.4:
				print("[9] PROD red retreat area=", scene.current_area.name, " hp=", p.hp,
					" same_caster=", p.get_node("SpellCaster") == caster,
					" -> ", "PASS" if scene.current_area.name == "Hub" and p.hp == 100 and p.get_node("SpellCaster") == caster else "FAIL")
				print("[9] DONE")
				quit()
	return false
