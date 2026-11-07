extends SceneTree
## #9 acceptance driver (headless, local composition).
## Proves: normal-dungeon retreat anytime; red-dungeon lock-in until objective
## completion; exit portal returns to hub with run state retained (same Player
## instance, HP kept); death restarts the run.
## Kills are synthetic apply_damage calls - NOT player combat proof.
var scene: Node
var p: Player
var caster: SpellCaster
var phase := 0
var t := 0.0

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	p = scene.get_node("Player")
	caster = p.get_node("SpellCaster")

func _enter_gate(name: String) -> void:
	var g: Gate = scene.current_area.get_node(name)
	g._on_body_entered(p)

func _portal() -> ExitPortal:
	return scene.current_area.get_node_or_null("ExitPortal")

func _process(delta: float) -> bool:
	t += delta
	match phase:
		0:
			if t > 0.3:
				p.apply_damage(58) # HP 42 as retention probe
				print("[9] hub area=", scene.current_area.name, " hp=", p.hp, " spells=", caster.spells.size())
				_enter_gate("GateNormal")
				phase = 1; t = 0
		1:
			if t > 0.3:
				var area = scene.current_area
				var portal = _portal()
				print("[9] after NORMAL gate area=", area.name, " portal=", portal != null, " locked=", portal.locked if portal else "?",
					" -> ", "PASS" if area.name == "DungeonA" and portal and not portal.locked else "FAIL")
				portal._on_body_entered(p)
				phase = 2; t = 0
		2:
			if t > 0.3:
				print("[9] normal retreat area=", scene.current_area.name, " hp=", p.hp, " same_caster=", p.get_node("SpellCaster") == caster,
					" -> ", "PASS" if scene.current_area.name == "Hub" and p.hp == 42 and p.get_node("SpellCaster") == caster else "FAIL")
				_enter_gate("GateRed")
				phase = 3; t = 0
		3:
			if t > 0.3:
				var portal = _portal()
				print("[9] after RED gate area=", scene.current_area.name, " portal locked=", portal.locked if portal else "?",
					" -> ", "PASS" if scene.current_area.name == "DungeonB" and portal and portal.locked else "FAIL")
				portal._on_body_entered(p) # must be ignored while locked
				phase = 4; t = 0
		4:
			if t > 0.3:
				print("[9] red lock-in area=", scene.current_area.name, " -> ", "PASS" if scene.current_area.name == "DungeonB" else "FAIL")
				var enemies = get_nodes_in_group("enemies")
				print("[9] killing ", enemies.size(), " enemies (synthetic)")
				for e in enemies:
					e.apply_damage(999)
				phase = 5; t = 0
		5:
			if t > 0.3:
				var obj = scene.current_area.get_node("DungeonObjective")
				var portal = _portal()
				print("[9] objective cleared=", obj.is_cleared(), " portal locked=", portal.locked,
					" -> ", "PASS" if obj.is_cleared() and not portal.locked else "FAIL")
				portal._on_body_entered(p)
				phase = 6; t = 0
		6:
			if t > 0.3:
				print("[9] red clear exit area=", scene.current_area.name, " hp=", p.hp, " same_caster=", p.get_node("SpellCaster") == caster,
					" -> ", "PASS" if scene.current_area.name == "Hub" and p.hp == 42 and p.get_node("SpellCaster") == caster else "FAIL")
				p.apply_damage(999) # death -> RunManager reload
				phase = 7; t = 0
		7:
			if current_scene != null and current_scene != scene and t > 0.3:
				scene = current_scene
				p = scene.get_node("Player")
				print("[9] death restart area=", scene.current_area.name, " hp=", p.hp, " pos=", p.global_position,
					" -> ", "PASS" if scene.current_area.name == "Hub" and p.hp == 100 else "FAIL")
				print("[9] DONE")
				quit()
	return false
