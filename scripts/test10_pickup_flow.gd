extends SceneTree
## #10 stage-1 harness (local composition). PROVISIONAL HARNESS DEFAULTS,
## not settled production behavior: duplicate-ignore and consume-on-grant.
## pickup grants spell (spell_added
## fires), duplicate ignored, switching cycles, the HUD grid stays six slots
## (#238), new run resets.
var scene: Node
var p: Player
var caster: SpellCaster
var hud: Node
var phase := 0
var t := 0.0
var p2: Player
var ok := true

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	p = scene.get_node("Player")
	caster = p.get_node("SpellCaster")
	hud = null # resolved in phase 1 (runtime-added, scene-named "Hud")

func _process(delta: float) -> bool:
	t += delta
	match phase:
		0:
			if t > 0.4:
				if caster.spells.size() != 2:
					print("[10] FAIL starting spells: ", caster.spells.size()); ok = false
				var pickup: SpellPickup = load("res://scenes/spell_pickup.tscn").instantiate()
				pickup.spell_path = "res://resources/spells/placeholder_bolt.tres"
				scene.current_area.add_child(pickup)
				phase = 1; t = 0
		1:
			if t > 0.4:
				if hud == null:
					for c in scene.get_children():
						if c is HUD:
							hud = c
				var pickup: SpellPickup = scene.current_area.get_node("SpellPickup")
				pickup._on_body_entered(p)
				if caster.spells.size() != 3 or caster.spells[2].spell_name != "Placeholder Bolt":
					print("[10] FAIL pickup grant: ", caster.spells.size()); ok = false
				else:
					print("[10] pickup grants Placeholder Bolt -> PASS")
				pickup._on_body_entered(p)
				if caster.spells.size() != 3:
					print("[10] FAIL duplicate added"); ok = false
				else:
					print("[10] duplicate pickup ignored -> PASS")
				# #262 (Daniel, 2026-11-08): a new pickup auto-binds to the FIRST
				# EMPTY slot; the HUD keeps mirroring the six slots (#238).
				var grid: GridContainer = hud.get_node("Root/SpellGrid")
				if grid.get_child_count() != 6 or caster.get_slots()[2] != caster.spells[2]:
					print("[10] FAIL auto-bind after pickup: grid=", grid.get_child_count(), " slot3=", caster.get_slots()[2]); ok = false
				else:
					print("[10] pickup auto-binds to first empty slot (3), HUD grid stays six -> PASS")
				caster.next_spell()
				var s1 := caster.equipped_spell.spell_name
				caster.next_spell()
				var s2 := caster.equipped_spell.spell_name
				caster.next_spell()
				var s3 := caster.equipped_spell.spell_name
				if s1 != "Mana Shot" or s2 != "Placeholder Bolt" or s3 != "Fire Ball":
					print("[10] FAIL switching: ", s1, "/", s2, "/", s3); ok = false
				else:
					print("[10] switching cycles Fire->Mana->Bolt->Fire -> PASS")
				phase = 2; t = 0
		2:
			if t > 0.2:
				# new run: RunManager reloads the whole scene -> fresh caster
				p2 = load("res://scenes/player.tscn").instantiate()
				root.add_child(p2)
				phase = 3; t = 0
		3:
			if t > 0.3:
				var caster2: SpellCaster = p2.get_node("SpellCaster")
				if caster2.spells.size() != 2:
					print("[10] FAIL run reset: ", caster2.spells.size()); ok = false
				else:
					print("[10] new-run caster rebuilds from starting_spells (reset) -> PASS")
				print("[10] RESULT: ", "ALL PASS" if ok else "FAILURES")
				quit(0 if ok else 1)
	return not ok
