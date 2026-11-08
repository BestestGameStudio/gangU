extends SceneTree
## Progression provider harness (#33/#36), post-#67: placeholder upgrade paths
## resolve against the REAL B caster; apply_upgrade now EXECUTES through the
## landed replace_spell seam (atomic own-index swap, slot preserved, cooldown
## transfer); XP accrual stays read-only via spell_cast. Synthetic headless
## complement only - browser evidence belongs to F's panel proof. Provider
## mount here is harness-local; production mount waits for the E window.
var scene: Node
var p: Player
var prog: SpellProgress
var caster: Node
var phase := 0
var t := 0.0
var ok := true
var replaced_seen: Array = []
var upsig_seen: Array = []
var slot_assigned_seen: Array = []

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
			prog.upgrades_changed.connect(func(sp): upsig_seen.append(sp))
			caster.spell_replaced.connect(func(o, n): replaced_seen.append([o, n]))
			caster.slot_assigned.connect(func(i, s): slot_assigned_seen.append([i, s]))
			phase = 1; t = 0
		1:
			if t > 0.3:
				var fire: Spell = load("res://resources/spells/fire_ball.tres")
				var split: Spell = load("res://resources/spells/fire_ball_split.tres")
				var paths := prog.get_upgrade_paths(fire)
				if paths.size() != 2 or paths[0].id != &"fireball_split" or paths[1].id != &"fireball_beam":
					print("[PROG] FAIL upgrade paths: ", paths.map(func(u): return u.id)); ok = false
				else:
					print("[PROG] placeholder upgrade paths resolve OK (split + beam)")
				# Real B starting loadout pre-unlocks fire+mana via add_spell.
				if not caster.get_unlocked().has(fire):
					caster.unlock_spell(fire)
				if not caster.assign_slot(0, fire):
					print("[PROG] FAIL assign_slot(0, fire) refused"); ok = false
				if prog.can_upgrade(fire):
					print("[PROG] FAIL can_upgrade at 0 casts"); ok = false
				if prog.apply_upgrade(fire, &"nonexistent") != false:
					print("[PROG] FAIL unknown id accepted"); ok = false
				# Approved threshold is 10: TEN REAL casts through cast_slot, each
				# gated by the actual 1.2s cooldown. Gate checked at 9, opens at 10.
				phase = 15; t = 0
		15:
			# Real-cast loop: one cast_slot(0) per cooldown cycle until 10 casts.
			var fire15: Spell = load("res://resources/spells/fire_ball.tres")
			var n: int = prog.cast_count(fire15)
			if n >= 10:
				if not prog.can_upgrade(fire15):
					print("[PROG] FAIL can_upgrade false at 10 real casts"); ok = false
				else:
					print("[PROG] can_upgrade true at exactly 10 real cooldown casts OK")
				phase = 2; t = 0
				return false
			if caster.cooldown_remaining(fire15) <= 0.0:
				caster.cast_slot(0)
				var m: int = prog.cast_count(fire15)
				if m == 9 and prog.can_upgrade(fire15):
					print("[PROG] FAIL can_upgrade below 10 casts (at 9)"); ok = false
				elif m == 9:
					print("[PROG] gate holds at 9 real casts OK")
		2:
			if t > 0.3:
				var fire: Spell = load("res://resources/spells/fire_ball.tres")
				if prog.cast_count(fire) != 10:
					print("[PROG] FAIL cast_count after real-cast loop: ", prog.cast_count(fire)); ok = false
				else:
					print("[PROG] XP read-only accrual via spell_cast OK (count=10, real casts)")
				if not caster.has_method("replace_spell"):
					print("[PROG] FAIL replace_spell seam expected landed (#67 merged)"); ok = false
					print("[PROG] ", "PASS" if ok else "FAIL")
					return true
				var fire_cd: float = caster.cooldown_remaining(fire)
				if prog.apply_upgrade(fire, &"fireball_split") != true:
					print("[PROG] FAIL apply_upgrade refused post-seam"); ok = false
				else:
					print("[PROG] apply_upgrade executes via replace_spell OK")
				phase = 3; t = 0
				set_meta("fire_cd", fire_cd)
		3:
			if t > 0.2:
				var fire: Spell = load("res://resources/spells/fire_ball.tres")
				var split: Spell = load("res://resources/spells/fire_ball_split.tres")
				var unl: Array = caster.get_unlocked()
				if unl.size() != 2 or unl[0] != split or unl[1].spell_name != "Mana Shot":
					print("[PROG] FAIL unlocked own-index swap: ", unl.map(func(s): return s.spell_name)); ok = false
				elif caster.get_slots()[0] != split:
					print("[PROG] FAIL slot 0 not preserved with split"); ok = false
				elif replaced_seen.size() != 1 or replaced_seen[0][0] != fire or replaced_seen[0][1] != split:
					print("[PROG] FAIL spell_replaced signal: ", replaced_seen.size()); ok = false
				elif slot_assigned_seen.size() != 2 or slot_assigned_seen[1][0] != 0 or slot_assigned_seen[1][1] != split:
					print("[PROG] FAIL slot_assigned re-emit: ", slot_assigned_seen.size()); ok = false
				elif caster.cooldown_remaining(fire) != 0.0 or caster.cooldown_remaining(split) <= 0.0:
					print("[PROG] FAIL cooldown transfer: old=", caster.cooldown_remaining(fire), " new=", caster.cooldown_remaining(split)); ok = false
				else:
					print("[PROG] edge semantics OK: unlocked own-index, slot preserved+re-emitted, spell_replaced once, CD transferred (old cleared)")
				# #36 tier delta legs (clean FAIL on old base: no accessor/field)
				if not prog.has_method("get_tier") or prog.get_tier(split) != 1:
					print("[PROG] FAIL tier: split not recorded Specialization on apply"); ok = false
				elif prog.get_tier(fire) != 0:
					print("[PROG] FAIL tier: consumed source not back to Base/0"); ok = false
				elif load("res://resources/upgrades/fireball_split.tres").get("tier") != 1 or load("res://resources/upgrades/fireball_beam.tres").get("tier") != 1:
					print("[PROG] FAIL tier: spec resources missing tier=1"); ok = false
				else:
					print("[PROG] tier recorded on apply (result=1, consumed source=0, spec resources tier=1) OK")
				if upsig_seen.size() != 1 or upsig_seen[0] != fire:
					print("[PROG] FAIL upgrades_changed: ", upsig_seen.size(), " calls, payload=", upsig_seen[0] if upsig_seen.size() > 0 else "none"); ok = false
				else:
					print("[PROG] upgrades_changed fired once with source-spell payload OK")
				if caster.replace_spell(fire, split) != false:
					print("[PROG] FAIL re-replace of consumed source accepted"); ok = false
				else:
					print("[PROG] refusal: consumed source re-replace refused OK")
				print("[PROG] ", "PASS" if ok else "FAIL")
				return true
		_:
			return true
	if t > 30.0:
		print("[PROG] FAIL timeout in phase ", phase)
		return true
	return false
