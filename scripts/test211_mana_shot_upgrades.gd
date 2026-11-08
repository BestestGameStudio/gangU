extends SceneTree
## #211 harness: Mana Shot upgrade paths (Volley + Lance) through the REAL
## SpellProgress provider and the landed #67 replace_spell seam, same shape
## as test_spell_progress.gd's Fire Ball legs. Synthetic headless complement
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
			prog.name = "SpellProgress211"
			scene.add_child(prog)
			prog.caster_path = NodePath("../Player/SpellCaster")
			var volley: SpellUpgrade = load("res://resources/upgrades/manashot_volley.tres")
			var lance: SpellUpgrade = load("res://resources/upgrades/manashot_lance.tres")
			prog.upgrades = [volley, lance]
			prog._ready()
			prog.upgrades_changed.connect(func(sp): upsig_seen.append(sp))
			caster.spell_replaced.connect(func(o, n): replaced_seen.append([o, n]))
			caster.slot_assigned.connect(func(i, s): slot_assigned_seen.append([i, s]))
			phase = 1; t = 0
		1:
			if t > 0.3:
				var mana: Spell = load("res://resources/spells/mana_shot.tres")
				var paths := prog.get_upgrade_paths(mana)
				if paths.size() != 2 or paths[0].id != &"manashot_volley" or paths[1].id != &"manashot_lance":
					print("[211] FAIL upgrade paths: ", paths.map(func(u): return u.id)); ok = false
				else:
					print("[211] upgrade paths resolve OK (volley + lance)")
				# Resource wiring, both branches (Lance's runtime apply is the
				# same code path as Volley's; static legs cover its content).
				var volley_r: Spell = load("res://resources/spells/mana_shot_volley.tres")
				var lance_r: Spell = load("res://resources/spells/mana_shot_lance.tres")
				if volley_r.projectile_count != 3 or volley_r.spread_degrees <= 0.0:
					print("[211] FAIL volley result not a multi-shot fan"); ok = false
				elif not lance_r.tags.has(&"piercing") or lance_r.damage <= mana.damage:
					print("[211] FAIL lance result not a heavier piercing shot"); ok = false
				elif paths[0].tier != 1 or paths[1].tier != 1 or paths[0].xp_threshold != 10 or paths[1].xp_threshold != 10:
					print("[211] FAIL tier/threshold wiring"); ok = false
				else:
					print("[211] result content OK: volley fan of 3, lance piercing heavy; both tier 1 @ 10 casts")
				# Real starting loadout pre-unlocks fire+mana via add_spell.
				if not caster.get_unlocked().has(mana):
					caster.unlock_spell(mana)
				if not caster.assign_slot(1, mana):
					print("[211] FAIL assign_slot(1, mana) refused"); ok = false
				if prog.can_upgrade(mana):
					print("[211] FAIL can_upgrade at 0 casts"); ok = false
				if prog.apply_upgrade(mana, &"nonexistent") != false:
					print("[211] FAIL unknown id accepted"); ok = false
				phase = 15; t = 0
		15:
			# Real-cast loop: one cast_slot(1) per 0.35s cooldown cycle to 10.
			var mana15: Spell = load("res://resources/spells/mana_shot.tres")
			var n: int = prog.cast_count(mana15)
			if n >= 10:
				if not prog.can_upgrade(mana15):
					print("[211] FAIL can_upgrade false at 10 real casts"); ok = false
				else:
					print("[211] can_upgrade true at exactly 10 real cooldown casts OK")
				phase = 2; t = 0
				return false
			if caster.cooldown_remaining(mana15) <= 0.0:
				caster.cast_slot(1)
				var m: int = prog.cast_count(mana15)
				if m == 9 and prog.can_upgrade(mana15):
					print("[211] FAIL can_upgrade below 10 casts (at 9)"); ok = false
				elif m == 9:
					print("[211] gate holds at 9 real casts OK")
		2:
			if t > 0.3:
				var mana: Spell = load("res://resources/spells/mana_shot.tres")
				if prog.cast_count(mana) != 10:
					print("[211] FAIL cast_count after real-cast loop: ", prog.cast_count(mana)); ok = false
				else:
					print("[211] XP read-only accrual via spell_cast OK (count=10, real casts)")
				var mana_cd: float = caster.cooldown_remaining(mana)
				if prog.apply_upgrade(mana, &"manashot_volley") != true:
					print("[211] FAIL apply_upgrade refused"); ok = false
				else:
					print("[211] apply_upgrade executes via replace_spell OK")
				phase = 3; t = 0
				set_meta("mana_cd", mana_cd)
		3:
			if t > 0.2:
				var mana: Spell = load("res://resources/spells/mana_shot.tres")
				var volley: Spell = load("res://resources/spells/mana_shot_volley.tres")
				var unl: Array = caster.get_unlocked()
				if unl.size() != 2 or unl[0].spell_name != "Fire Ball" or unl[1] != volley:
					print("[211] FAIL unlocked own-index swap: ", unl.map(func(s): return s.spell_name)); ok = false
				elif caster.get_slots()[1] != volley:
					print("[211] FAIL slot 1 not preserved with volley"); ok = false
				elif replaced_seen.size() != 1 or replaced_seen[0][0] != mana or replaced_seen[0][1] != volley:
					print("[211] FAIL spell_replaced signal: ", replaced_seen.size()); ok = false
				elif caster.cooldown_remaining(mana) != 0.0:
					print("[211] FAIL cooldown transfer: old not cleared"); ok = false
				else:
					print("[211] edge semantics OK: unlocked own-index, slot preserved, spell_replaced once, CD old cleared")
				if not prog.has_method("get_tier") or prog.get_tier(volley) != 1:
					print("[211] FAIL tier: volley not recorded Specialization on apply"); ok = false
				elif prog.get_tier(mana) != 0:
					print("[211] FAIL tier: consumed source not back to Base/0"); ok = false
				else:
					print("[211] tier recorded on apply (result=1, consumed source=0) OK")
				if upsig_seen.size() != 1 or upsig_seen[0] != mana:
					print("[211] FAIL upgrades_changed: ", upsig_seen.size()); ok = false
				else:
					print("[211] upgrades_changed fired once with source-spell payload OK")
				if caster.replace_spell(mana, volley) != false:
					print("[211] FAIL re-replace of consumed source accepted"); ok = false
				else:
					print("[211] refusal: consumed source re-replace refused OK")
				# Result spell actually casts its fan: 3 projectiles from one cast.
				phase = 4; t = 0
		4:
			var volley4: Spell = load("res://resources/spells/mana_shot_volley.tres")
			if caster.cooldown_remaining(volley4) > 0.0:
				return false
			var before := _projectile_count()
			caster.cast_slot(1)
			var after := _projectile_count()
			if after - before != 3:
				print("[211] FAIL volley cast spawned ", after - before, " projectiles, want 3"); ok = false
			else:
				print("[211] volley cast spawns 3-projectile fan OK")
			print("[211] ", "PASS" if ok else "FAIL")
			return true
		_:
			return true
	if t > 30.0:
		print("[211] FAIL timeout in phase ", phase)
		return true
	return false
