extends SceneTree
## #36 acceptance driver (headless, local composition): upgrade identity and
## cooldown hardening for the SHIPPED replace_spell machinery (post-B seam).
## PRODUCTION (main.tscn composition, real mounts only - no fixture):
##   cooldown transfer  - the upgraded spell inherits the source's REMAINING
##                        cooldown (maxf(rem, 0), old key erased): upgrading
##                        mid-cooldown is never a free recast
##   own cooldown after - once the inherited remainder expires, the next cast
##                        keys the cooldown to the UPGRADED spell's own value
##   HUD rows           - the row is re-keyed to the upgraded object (no
##                        stale base row) and the visible name follows it
##   slot preservation  - the equip slot INDEX survives the swap
##                        (slot_assigned re-emit, NO slot_cleared)
##   identity           - unlocked[]/legacy spells[] swapped at their own
##                        indices, current_index untouched, no duplicates
##   shared .tres       - base AND result Spell resources are never mutated
## XP is driven through the read-only spell_cast signal observation (same
## approach as test_e_mount); the cast under cooldown test is a REAL cast.

var scene: Node
var p: Player
var caster: SpellCaster
var progress: SpellProgress
var hud: HUD
var fb: Spell = preload("res://resources/spells/fire_ball.tres")
var split: Spell = preload("res://resources/spells/fire_ball_split.tres")
var split_up: SpellUpgrade = preload("res://resources/upgrades/fireball_split.tres")
var beam_up: SpellUpgrade = preload("res://resources/upgrades/fireball_beam.tres")
var phase := 0
var t := 0.0
var fails := 0
var apply_ok := false
var replaced_seen: Array = []
var slot_assigned_seen: Array = []
var slot_cleared_count := 0
var upgrades_changed_count := 0
var last_cast: Spell = null
var snap := {}

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	p = scene.get_node("Player")

func _grab_refs() -> void:
	caster = p.get_node("SpellCaster")
	progress = scene.get_node("SpellProgress")
	for c in scene.get_children():
		if c is HUD:
			hud = c
	caster.spell_replaced.connect(func(o, n): replaced_seen.append([o, n]))
	caster.slot_assigned.connect(func(i, s): slot_assigned_seen.append([i, s]))
	caster.slot_cleared.connect(func(_i): slot_cleared_count += 1)
	progress.upgrades_changed.connect(func(_s): upgrades_changed_count += 1)
	caster.spell_cast.connect(func(s): last_cast = s)

func _snap(spell: Spell) -> Dictionary:
	return {"name": spell.spell_name, "cooldown": spell.cooldown,
		"damage": spell.damage, "count": spell.projectile_count,
		"spread": spell.spread_degrees, "range": spell.range}

func _unmutated(spell: Spell, s: Dictionary) -> bool:
	return spell.spell_name == s["name"] and spell.cooldown == s["cooldown"] \
		and spell.damage == s["damage"] and spell.projectile_count == s["count"] \
		and spell.spread_degrees == s["spread"] and spell.range == s["range"]

func _check(label: String, ok: bool) -> void:
	if not ok:
		fails += 1
	print("[36] ", label, " -> ", "PASS" if ok else "FAIL")

func _process(delta: float) -> bool:
	t += delta
	match phase:
		0:
			if progress == null and scene.get_node_or_null("SpellProgress") != null:
				_grab_refs()
			if t > 0.3 and progress != null:
				snap = {"fb": _snap(fb), "split": _snap(split)}
				_check("pre: fb unlocked, split not", caster.get_unlocked().has(fb) and not caster.get_unlocked().has(split))
				_check("pre: slot 2 assign fb", caster.assign_slot(2, fb) and caster.get_slots()[2] == fb)
				for i in 10: # XP observation, read-only
					caster.spell_cast.emit(fb)
				last_cast = null
				_check("pre: can_upgrade(fb) at 10 casts", progress.can_upgrade(fb))
				# #36 tier delta legs (clean FAIL on old base: no field/accessor)
				_check("tier: spec resource fields tier=1", split_up.get("tier") == 1 and beam_up.get("tier") == 1)
				_check("tier: base spell is 0 pre-apply", not progress.has_method("get_tier") or progress.get_tier(fb) == 0)
				_check("pre: HUD row keyed to fb", hud._spell_rows.has(fb) and not hud._spell_rows.has(split))
				caster.cast_slot(2) # REAL cast: fb cooldown starts
				apply_ok = progress.apply_upgrade(fb, &"fireball_split")
				_check("apply_upgrade accepted", apply_ok)
				phase = 1; t = 0
		1:
			if t > 0.4:
				var rem := caster.cooldown_remaining(split)
				_check("cooldown transferred to split (no free recast)", rem > 0.2 and rem <= fb.cooldown)
				_check("old fb cooldown key erased", caster.cooldown_remaining(fb) == 0.0)
				_check("slot 2 blocked while inherited cooldown runs", not caster.can_cast_slot(2))
				_check("slot index preserved: split in slot 2", caster.get_slots()[2] == split)
				var others_empty := true
				for i in 6:
					if i != 2 and caster.get_slots()[i] != null:
						others_empty = false
				_check("other slots untouched", others_empty)
				_check("identity: unlocked swapped, no duplicate", caster.get_unlocked().has(split) and not caster.get_unlocked().has(fb))
				_check("identity: legacy list index kept, equipped follows", caster.spells[0] == split and caster.equipped_spell == split and caster.current_index == 0)
				_check("signals: spell_replaced(fb, split)", replaced_seen.size() == 1 and replaced_seen[0][0] == fb and replaced_seen[0][1] == split)
				_check("signals: slot_assigned(2, split) re-emitted", slot_assigned_seen.any(func(e): return e[0] == 2 and e[1] == split))
				_check("signals: no slot_cleared on upgrade", slot_cleared_count == 0)
				_check("signals: upgrades_changed emitted once", upgrades_changed_count == 1)
				_check("HUD: row re-keyed to split, stale fb row gone", hud._spell_rows.has(split) and not hud._spell_rows.has(fb))
				_check("HUD: visible name follows upgraded object", hud._spell_rows[split]["name"].text.contains("Split"))
				_check("tier: split recorded Specialization ON apply", progress.has_method("get_tier") and progress.get_tier(split) == 1)
				_check("tier: consumed source drops to Base/0", progress.has_method("get_tier") and progress.get_tier(fb) == 0)
				var m2: Array = progress.get_upgrade_paths(split)
				_check("tier: mastery forks carry tier=2", m2.size() == 2 and m2.all(func(u): return u.get("tier") == 2))
				_check("shared base .tres unmutated", _unmutated(fb, snap["fb"]))
				_check("shared result .tres unmutated", _unmutated(split, snap["split"]))
				phase = 2; t = 0
		2:
			if t > 0.8: # inherited fb remainder (<=0.5) expired
				_check("inherited cooldown expired", caster.can_cast_slot(2))
				caster.cast_slot(2)
				_check("recast keys cooldown to upgraded spell", caster.cooldown_remaining(split) > split.cooldown - 0.1 and caster.cooldown_remaining(split) <= split.cooldown)
				_check("recast emitted for split", last_cast == split)
				_check("base still unmutated after upgraded cast", _unmutated(fb, snap["fb"]) and _unmutated(split, snap["split"]))
				if fails == 0:
					print("[36] ALL PASS")
				print("[36] DONE")
				quit()
	return false
