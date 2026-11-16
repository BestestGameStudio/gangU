extends SceneTree
## Progression provider harness (#33/#36), post-#67, #703 chains: the next
## upgrade resolves against the REAL B caster; apply_upgrade now EXECUTES through the
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
	scene = load("res://game/core/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	p = scene.get_node("Player")
	caster = p.get_node("SpellCaster")

func _process(delta: float) -> bool:
	t += delta
	match phase:
		0:
			if scene.area_loader.current_area == null:
				return false
			prog = SpellProgress.new()
			prog.name = "SpellProgress"
			scene.add_child(prog)
			prog.caster_path = NodePath("../Player/SpellCaster") # resolved relative to the provider (ReviveSatchel convention)
			# #703: one fixed linear chain - Fire Ball upgrades to Split only.
			var split: SpellUpgrade = load("res://data/upgrades/fireball_split.tres")
			prog.upgrades = [split]
			prog._ready()
			prog.upgrades_changed.connect(func(sp): upsig_seen.append(sp))
			caster.spell_replaced.connect(func(o, n): replaced_seen.append([o, n]))
			caster.slot_assigned.connect(func(i, s): slot_assigned_seen.append([i, s]))
			phase = 1; t = 0
		1:
			if t > 0.3:
				var fire: Spell = load("res://data/spells/fire_ball.tres")
				var split: Spell = load("res://data/spells/fire_ball_split.tres")
				var next := prog.next_upgrade(fire)
				if next == null or next.id != &"fireball_split":
					print("[PROG] FAIL next upgrade in chain: ", next.id if next != null else "null"); ok = false
				else:
					print("[PROG] chain next upgrade resolves OK (split)")
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
			var fire15: Spell = load("res://data/spells/fire_ball.tres")
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
				var fire: Spell = load("res://data/spells/fire_ball.tres")
				if prog.cast_count(fire) != 10:
					print("[PROG] FAIL cast_count after real-cast loop: ", prog.cast_count(fire)); ok = false
				else:
					print("[PROG] XP read-only accrual via spell_cast OK (count=10, real casts)")
				if not caster.has_method("replace_spell"):
					print("[PROG] FAIL replace_spell seam expected landed (#67 merged)"); ok = false
					print("[PROG] ", "PASS" if ok else "FAIL")
					quit(0 if ok else 1)
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
				var fire: Spell = load("res://data/spells/fire_ball.tres")
				var split: Spell = load("res://data/spells/fire_ball_split.tres")
				var unl: Array = caster.get_unlocked()
				if unl.size() != 3 or unl[0] != split or unl[1].spell_name != "Mana Shot" or unl[2].id() != &"water_shot":
					print("[PROG] FAIL unlocked own-index swap: ", unl.map(func(s): return s.spell_name)); ok = false
				elif caster.get_slots()[0] != split:
					print("[PROG] FAIL slot 0 not preserved with split"); ok = false
				elif replaced_seen.size() != 1 or replaced_seen[0][0] != fire or replaced_seen[0][1] != split:
					print("[PROG] FAIL spell_replaced signal: ", replaced_seen.size()); ok = false
				elif slot_assigned_seen.size() != 1 or slot_assigned_seen[0][0] != 0 or slot_assigned_seen[0][1] != split: # #238: boot seeds slot 1, so the assign above is a no-op
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
				elif load("res://data/upgrades/fireball_split.tres").get("tier") != 1 or load("res://data/upgrades/fireball_m2_split_wide.tres").get("tier") != 2:
					print("[PROG] FAIL tier: chain resources missing tier=1/2"); ok = false
				else:
					print("[PROG] tier recorded on apply (result=1, consumed source=0, chain resources tier=1/2) OK")
				if upsig_seen.size() != 1 or upsig_seen[0] != fire:
					print("[PROG] FAIL upgrades_changed: ", upsig_seen.size(), " calls, payload=", upsig_seen[0] if upsig_seen.size() > 0 else "none"); ok = false
				else:
					print("[PROG] upgrades_changed fired once with source-spell payload OK")
				if caster.replace_spell(fire, split) != false:
					print("[PROG] FAIL re-replace of consumed source accepted"); ok = false
				else:
					print("[PROG] refusal: consumed source re-replace refused OK")
				check_quests()
				print("[PROG] ", "PASS" if ok else "FAIL")
				quit(0 if ok else 1)
				return true
		_:
			quit(0 if ok else 1)
			return true
	if t > 30.0:
		print("[PROG] FAIL timeout in phase ", phase); ok = false
		quit(0 if ok else 1)
		return true
	return false

func quest_check(value: bool, label: String) -> void:
	if not value: ok = false
	print("[PROG] quest ", label, " ", "OK" if value else "FAIL")

func check_quests() -> void:
	var base: Spell = load("res://data/spells/water_shot.tres")
	var first: SpellUpgrade = load("res://data/upgrades/water_shot_hover.tres")
	var second: SpellUpgrade = load("res://data/upgrades/water_shot_reservoir.tres")
	var third: SpellUpgrade = load("res://data/upgrades/water_shot_tide.tres")
	prog.upgrades.append_array([first, second, third])
	for i in 20: prog._on_spell_cast(base)
	quest_check(not prog.can_upgrade(base), "casts cannot bypass authored hit quest")
	var target := Enemy.new()
	var e := HitEvent.new(); e.attacker = p; e.spell = base; e.target = target
	e.delivery = OnHit.DELIVERY_PROJECTILE; e.hp_lost = 1; e.projectile_id = 101
	prog._on_quest_hit(e)
	quest_check(prog.qualification_count(first) == 0, "unredirected hit excluded")
	e.redirected = true
	prog._on_quest_hit(e); prog._on_quest_hit(e)
	quest_check(prog.qualification_count(first) == 1, "same shot enemy pair counted once")
	e.hp_lost = 0; e.projectile_id = 102; prog._on_quest_hit(e)
	quest_check(prog.qualification_count(first) == 1, "no damage excluded")
	e.hp_lost = 1
	for i in range(102, 106): e.projectile_id = i; prog._on_quest_hit(e)
	quest_check(prog.can_upgrade(base), "five redirected shots may hit same enemy")
	var carried := prog.capture_run_state(); prog._quest_counts.clear(); prog.restore_run_state(carried)
	quest_check(prog.can_upgrade(base), "quest count follows progression death carry")
	quest_check(prog.apply_upgrade(base, first.id), "qualified quest applies normal replacement")
	e.spell = first.result_spell; e.projectile_id = 201; prog._on_quest_hit(e); prog._on_quest_hit(e)
	quest_check(prog.qualification_count(second) == 0, "one shot repeated cannot satisfy volley")
	e.projectile_id = 202; prog._on_quest_hit(e)
	quest_check(not prog.can_upgrade(e.spell), "two distinct shots insufficient")
	for target_key in prog._quest_volleys:
		for shot_key in prog._quest_volleys[target_key]: prog._quest_volleys[target_key][shot_key] -= 1000
	e.projectile_id = 203; prog._on_quest_hit(e)
	quest_check(not prog.can_upgrade(e.spell), "expired volley shots excluded")
	e.projectile_id = 204; prog._on_quest_hit(e)
	e.projectile_id = 205; prog._on_quest_hit(e)
	quest_check(prog.can_upgrade(e.spell), "three distinct shots same enemy short window")
	quest_check(prog.apply_upgrade(e.spell, second.id), "volley qualification applies")
	for i in 4: prog._on_spell_cast(second.result_spell)
	quest_check(not prog.can_upgrade(second.result_spell), "five cast quest closed at four")
	prog._on_spell_cast(second.result_spell)
	quest_check(prog.can_upgrade(second.result_spell), "five cast quest qualifies at five")
	var menu := prog.upgrade_menu(second.result_spell)
	quest_check(menu[2].objective == third.quest.objective and menu[2].threshold == 5, "menu exposes quest objective and count")
	var card := UpgradeCard.new(); scene.add_child(card)
	card.setup("hidden", "hidden effect", false)
	card.set_unlock_state("locked", 2, 5, "", "", first.quest.objective)
	quest_check(card.progress_bar.visible and card.progress_bar.value == 2 and card.progress_bar.max_value == 5 and card.progress_label.text.contains("2 / 5"), "quest bar tracks partial progress with objective and count")
	quest_check((card.progress_bar.get_theme_stylebox("background") as StyleBoxFlat).bg_color.a > 0 and (card.progress_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color == UpgradeCard.SATISFIED_PROGRESS, "quest bar has visible track and green partial fill")
	card.queue_free()
	target.free()
