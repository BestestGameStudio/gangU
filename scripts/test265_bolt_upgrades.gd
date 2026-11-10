extends SceneTree
## #265 harness: pickup Bolt upgrade paths (Flurry + Heavy) through the REAL
## SpellProgress provider and the #67 replace_spell seam, same shape as
## test211's Mana Shot legs. Also covers the #262 integration: granting the
## pickup Bolt auto-binds the first free slot (2, after boot Fire 0/Mana 1),
## and the upgrade must preserve that binding. Synthetic headless complement
## only - browser panel/gameplay evidence ships on the PR. Provider mount is
## harness-local; production mount is main.gd's SpellProgress wiring.
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

func _projectile_count() -> int:
	var n := 0
	for c in current_scene.get_children():
		if c is Projectile:
			n += 1
	return n

func _process(delta: float) -> bool:
	t += delta
	match phase:
		0:
			if scene.current_area == null:
				return false
			prog = SpellProgress.new()
			prog.name = "SpellProgress265"
			scene.add_child(prog)
			prog.caster_path = NodePath("../Player/SpellCaster")
			var flurry: SpellUpgrade = load("res://resources/upgrades/bolt_flurry.tres")
			var heavy: SpellUpgrade = load("res://resources/upgrades/bolt_heavy.tres")
			prog.upgrades = [flurry, heavy]
			prog._ready()
			prog.upgrades_changed.connect(func(sp): upsig_seen.append(sp))
			caster.spell_replaced.connect(func(o, n): replaced_seen.append([o, n]))
			caster.slot_assigned.connect(func(i, s): slot_assigned_seen.append([i, s]))
			phase = 1; t = 0
		1:
			if t > 0.3:
				var bolt: Spell = load("res://resources/spells/placeholder_bolt.tres")
				var paths := prog.get_upgrade_paths(bolt)
				if paths.size() != 2 or paths[0].id != &"bolt_flurry" or paths[1].id != &"bolt_heavy":
					print("[265] FAIL upgrade paths: ", paths.map(func(u): return u.id)); ok = false
				else:
					print("[265] upgrade paths resolve OK (flurry + heavy)")
				# Resource wiring, both branches (Heavy's runtime apply below;
				# static legs cover both contents).
				var flurry_r: Spell = load("res://resources/spells/bolt_flurry.tres")
				var heavy_r: Spell = load("res://resources/spells/bolt_heavy.tres")
				if flurry_r.cooldown >= bolt.cooldown or flurry_r.damage >= bolt.damage or flurry_r.projectile_speed <= bolt.projectile_speed:
					print("[265] FAIL flurry result not a faster lighter shot"); ok = false
				elif not heavy_r.tags.has(&"piercing") or heavy_r.damage <= bolt.damage or heavy_r.cooldown <= bolt.cooldown:
					print("[265] FAIL heavy result not a slower heavier piercing shot"); ok = false
				elif paths[0].tier != 1 or paths[1].tier != 1 or paths[0].xp_threshold != 10 or paths[1].xp_threshold != 10:
					print("[265] FAIL tier/threshold wiring"); ok = false
				else:
					print("[265] result content OK: flurry fast/light, heavy piercing hitter; both tier 1 @ 10 casts")
				# #262 integration: granting the pickup Bolt auto-binds the
				# first free slot (2 after boot Fire 0 / Mana 1).
				if not caster.get_unlocked().has(bolt):
					caster.unlock_spell(bolt)
				if caster.get_slots()[2] != bolt:
					print("[265] FAIL #262 grant did not auto-bind slot 2: ", caster.get_slots()[2]); ok = false
				elif slot_assigned_seen.is_empty() or slot_assigned_seen[slot_assigned_seen.size() - 1] != [2, bolt]:
					print("[265] FAIL slot_assigned for auto-bound bolt: ", slot_assigned_seen); ok = false
				else:
					print("[265] #262 grant auto-bound Bolt to slot 2 OK")
				if prog.can_upgrade(bolt):
					print("[265] FAIL can_upgrade at 0 casts"); ok = false
				if prog.apply_upgrade(bolt, &"nonexistent") != false:
					print("[265] FAIL unknown id accepted"); ok = false
				phase = 15; t = 0
		15:
			# Real-cast loop: one cast_slot(2) per 0.6s cooldown cycle to 10.
			var bolt15: Spell = load("res://resources/spells/placeholder_bolt.tres")
			var n: int = prog.cast_count(bolt15)
			if n >= 10:
				if not prog.can_upgrade(bolt15):
					print("[265] FAIL can_upgrade false at 10 real casts"); ok = false
				else:
					print("[265] can_upgrade true at exactly 10 real cooldown casts OK")
				phase = 2; t = 0
				return false
			if caster.cooldown_remaining(bolt15) <= 0.0:
				caster.cast_slot(2)
				var m: int = prog.cast_count(bolt15)
				if m == 9 and prog.can_upgrade(bolt15):
					print("[265] FAIL can_upgrade below 10 casts (at 9)"); ok = false
				elif m == 9:
					print("[265] gate holds at 9 real casts OK")
		2:
			if t > 0.3:
				var bolt: Spell = load("res://resources/spells/placeholder_bolt.tres")
				if prog.cast_count(bolt) != 10:
					print("[265] FAIL cast_count after real-cast loop: ", prog.cast_count(bolt)); ok = false
				else:
					print("[265] XP read-only accrual via spell_cast OK (count=10, real casts)")
				if prog.apply_upgrade(bolt, &"bolt_heavy") != true:
					print("[265] FAIL apply_upgrade refused"); ok = false
				else:
					print("[265] apply_upgrade executes via replace_spell OK")
				phase = 3; t = 0
		3:
			if t > 0.2:
				var bolt: Spell = load("res://resources/spells/placeholder_bolt.tres")
				var heavy: Spell = load("res://resources/spells/bolt_heavy.tres")
				var unl: Array = caster.get_unlocked()
				if unl.size() != 3 or unl[0].spell_name != "Fire Ball" or unl[1].spell_name != "Mana Shot" or unl[2] != heavy:
					print("[265] FAIL unlocked own-index swap: ", unl.map(func(s): return s.spell_name)); ok = false
				elif caster.get_slots()[2] != heavy:
					print("[265] FAIL slot 2 not preserved with heavy"); ok = false
				elif replaced_seen.size() != 1 or replaced_seen[0][0] != bolt or replaced_seen[0][1] != heavy:
					print("[265] FAIL spell_replaced signal: ", replaced_seen.size()); ok = false
				elif caster.cooldown_remaining(bolt) != 0.0:
					print("[265] FAIL cooldown transfer: old not cleared"); ok = false
				else:
					print("[265] edge semantics OK: unlocked own-index, auto-bound slot 2 preserved, spell_replaced once, CD old cleared")
				if not prog.has_method("get_tier") or prog.get_tier(heavy) != 1:
					print("[265] FAIL tier: heavy not recorded Specialization on apply"); ok = false
				elif prog.get_tier(bolt) != 0:
					print("[265] FAIL tier: consumed source not back to Base/0"); ok = false
				else:
					print("[265] tier recorded on apply (result=1, consumed source=0) OK")
				if upsig_seen.size() != 1 or upsig_seen[0] != bolt:
					print("[265] FAIL upgrades_changed: ", upsig_seen.size()); ok = false
				else:
					print("[265] upgrades_changed fired once with source-spell payload OK")
				if caster.replace_spell(bolt, heavy) != false:
					print("[265] FAIL re-replace of consumed source accepted"); ok = false
				else:
					print("[265] refusal: consumed source re-replace refused OK")
				phase = 4; t = 0
		4:
			var heavy4: Spell = load("res://resources/spells/bolt_heavy.tres")
			if caster.cooldown_remaining(heavy4) > 0.0:
				return false
			var before := _projectile_count()
			caster.cast_slot(2)
			var after := _projectile_count()
			if after - before != 1:
				print("[265] FAIL heavy cast spawned ", after - before, " projectiles, want 1"); ok = false
			elif caster.cooldown_remaining(heavy4) <= 0.6:
				print("[265] FAIL heavy cast cooldown not its own slower cycle: ", caster.cooldown_remaining(heavy4)); ok = false
			else:
				print("[265] heavy cast spawns a single piercing bolt on its own 1.0s cycle OK")
			print("[265] ", "PASS" if ok else "FAIL")
			quit(0 if ok else 1)
			return true
		_:
			quit(0 if ok else 1)
			return true
	if t > 30.0:
		print("[265] FAIL timeout in phase ", phase); ok = false
		quit(0 if ok else 1)
		return true
	return false
