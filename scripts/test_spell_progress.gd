extends SceneTree
## Progression provider harness (#33/#36): placeholder upgrade paths resolve
## against the REAL B caster; XP accrual is read-only via spell_cast; and
## apply_upgrade REFUSES (false) while the replace_spell seam is unlanded
## (Mitra post-#63 follow-up). Synthetic headless complement only - browser
## evidence belongs to F's panel proof. Provider mount here is harness-local;
## production mount waits for the lead's E window.
var scene: Node
var p: Player
var prog: SpellProgress
var caster: Node
var phase := 0
var t := 0.0
var ok := true

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	p = scene.get_node("Player")
	caster = p.get_node("SpellCaster")

func _process(delta: float) -> bool:
	t += delta
	match phase:
		0:
			if scene.current_area == null:
				return false
			prog = SpellProgress.new()
			prog.name = "SpellProgress"
			scene.add_child(prog)
			prog.caster_path = NodePath("../Player/SpellCaster") # resolved relative to the provider (ReviveSatchel convention)
			var split: SpellUpgrade = load("res://resources/upgrades/fireball_split.tres")
			var beam: SpellUpgrade = load("res://resources/upgrades/fireball_beam.tres")
			prog.upgrades = [split, beam]
			prog._ready()
			phase = 1; t = 0
		1:
			if t > 0.3:
				var fire: Spell = load("res://resources/spells/fire_ball.tres")
				var paths := prog.get_upgrade_paths(fire)
				if paths.size() != 2 or paths[0].id != &"fireball_split" or paths[1].id != &"fireball_beam":
					print("[PROG] FAIL upgrade paths: ", paths.map(func(u): return u.id)); ok = false
				else:
					print("[PROG] placeholder upgrade paths resolve OK (split + beam, result_spell set)")
				if paths[0].result_spell == null or paths[0].result_spell.spell_name != "Fire Ball Split [placeholder]":
					print("[PROG] FAIL split result_spell placeholder"); ok = false
				# Real B: production starts with EMPTY unlocked[] (no prefill) -
				# unlock + assign through the real B API first.
				caster.unlock_spell(fire)
				if not caster.assign_slot(0, fire):
					print("[PROG] FAIL assign_slot(0, fire) refused"); ok = false
				if not prog.can_upgrade(fire):
					print("[PROG] FAIL can_upgrade(fire_ball) false on real caster"); ok = false
				else:
					print("[PROG] can_upgrade(fire_ball) true on real B caster OK")
				# Refusal while the seam is unlanded:
				if caster.has_method("replace_spell"):
					print("[PROG] NOTE: replace_spell seam detected - refusal expectation no longer applies")
				elif prog.apply_upgrade(fire, &"fireball_split") != false:
					print("[PROG] FAIL apply_upgrade did not refuse pre-seam"); ok = false
				else:
					print("[PROG] apply_upgrade refuses pre-seam (replace_spell unlanded) OK")
				if prog.apply_upgrade(fire, &"nonexistent") != false:
					print("[PROG] FAIL unknown id accepted"); ok = false
				# XP read-only accrual: fire a cast through the real caster.
				caster.cast_slot(0)
				phase = 2; t = 0
		2:
			if t > 0.3:
				var fire: Spell = load("res://resources/spells/fire_ball.tres")
				if prog.cast_count(fire) != 1:
					print("[PROG] FAIL cast_count after one real cast: ", prog.cast_count(fire)); ok = false
				else:
					print("[PROG] XP read-only accrual via spell_cast OK (count=1)")
				print("[PROG] ", "PASS" if ok else "FAIL")
				return true
		_:
			return true
	if t > 6.0:
		print("[PROG] FAIL timeout in phase ", phase)
		return true
	return false
