extends SceneTree
## #305 harness: Spirit Punch upgrade ROUTE (Base -> Burst -> Launch ->
## Freeze bubble) through the REAL SpellProgress provider and the
## replace_spell seam. Thresholds/tiers are provisional placeholder numbers
## (balance is an open human choice): 10 casts for Specialization, 15 for
## Mastery, 20 for Signature, mirroring the approved Fire Ball 10/15
## precedent with no tier-3 precedent existing. Provider mount is
## harness-local; production mount is main.gd's SpellProgress wiring.
var scene: Node
var p: Player
var prog: SpellProgress
var caster: Node
var phase := 0
var t := 0.0
var ok := true
var replaced_seen: Array = []

var base: Spell = load("res://resources/spells/spirit_punch.tres")
var burst: Spell = load("res://resources/spells/spirit_punch_burst.tres")
var launch: Spell = load("res://resources/spells/spirit_punch_launch.tres")
var bubble: Spell = load("res://resources/spells/spirit_punch_bubble.tres")
var up_burst: SpellUpgrade = load("res://resources/upgrades/spirit_punch_burst.tres")
var up_launch: SpellUpgrade = load("res://resources/upgrades/spirit_punch_launch.tres")
var up_bubble: SpellUpgrade = load("res://resources/upgrades/spirit_punch_bubble.tres")

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[305up] PASS ", name)
	else:
		print("[305up] FAIL ", name)
		ok = false

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	p = scene.get_node("Player")
	caster = p.get_node("SpellCaster")

func _casts(spell: Spell, n: int) -> void:
	for i in n:
		prog._on_spell_cast(spell)

func _process(delta: float) -> bool:
	t += delta
	match phase:
		0:
			if scene.current_area == null:
				return false
			prog = SpellProgress.new()
			prog.name = "SpellProgress305"
			scene.add_child(prog)
			prog.caster_path = NodePath("../Player/SpellCaster")
			prog.upgrades = [up_burst, up_launch, up_bubble]
			prog._ready()
			caster.spell_replaced.connect(func(o, n): replaced_seen.append([o, n]))
			phase = 1; t = 0
		1:
			if t < 0.3:
				return false
			# Static legs: chain wiring + no tier skipping offered.
			_check(up_burst.source_spell == base and up_burst.result_spell == burst
				and up_burst.tier == 1 and up_burst.xp_threshold == 10, "tier1: base -> burst @ 10")
			_check(up_launch.source_spell == burst and up_launch.result_spell == launch
				and up_launch.tier == 2 and up_launch.xp_threshold == 15, "tier2: burst -> launch @ 15")
			_check(up_bubble.source_spell == launch and up_bubble.result_spell == bubble
				and up_bubble.tier == 3 and up_bubble.xp_threshold == 20, "tier3: launch -> bubble @ 20")
			_check(prog.get_upgrade_paths(base) == [up_burst], "base offers ONLY the burst path (no skipping)")
			# Cumulative content across the chain (#305 convention: each
			# tier carries the prior tiers).
			_check(burst.burst_count == 3 and burst.launch_speed == 0.0, "burst result is burst-only")
			_check(launch.burst_count == 3 and launch.launch_speed > 0.0 and launch.freeze_radius == 0.0,
				"launch result carries burst, no bubble")
			_check(bubble.burst_count == 3 and bubble.launch_speed > 0.0
				and bubble.freeze_radius > 0.0 and bubble.freeze_duration == 5.0,
				"bubble result carries burst + launch + 5s freeze")
			# Runtime: grant base (auto-binds slot 2 after boot Fire 0/Mana 1).
			caster.unlock_spell(base)
			_check(caster.get_slots()[2] == base, "base grant auto-binds slot 2")
			_check(not prog.can_upgrade(base), "no upgrade before 10 casts")
			# Provider semantics: the panel gates on can_upgrade; apply_upgrade
			# trusts the caller on thresholds (refusal-bool covers only the
			# seam/unknown id), so the harness never applies early.
			_casts(base, 10)
			_check(prog.can_upgrade(base), "upgrade available at 10 casts")
			phase = 2; t = 0
		2:
			_check(prog.apply_upgrade(base, &"spirit_punch_burst"), "apply tier1 succeeds")
			_check(caster.get_slots()[2] == burst, "slot 2 preserved through tier1 swap")
			_check(prog.get_tier(burst) == 1 and prog.get_tier(base) == 0, "tier recorded on the result, source back to base")
			_check(replaced_seen.size() == 1 and replaced_seen[0] == [base, burst], "spell_replaced emitted once (base -> burst)")
			_check(not prog.can_upgrade(burst), "no tier2 before 15 burst casts")
			_casts(burst, 15)
			_check(prog.apply_upgrade(burst, &"spirit_punch_launch"), "apply tier2 succeeds")
			_check(caster.get_slots()[2] == launch, "slot 2 preserved through tier2 swap")
			_check(prog.get_tier(launch) == 2, "tier2 recorded")
			_casts(launch, 20)
			_check(prog.apply_upgrade(launch, &"spirit_punch_bubble"), "apply tier3 succeeds")
			_check(caster.get_slots()[2] == bubble, "slot 2 preserved through tier3 swap")
			_check(prog.get_tier(bubble) == 3, "tier3 recorded")
			_check(prog.get_upgrade_paths(bubble).is_empty(), "no paths beyond Signature")
			print("---\n[305up] %s" % ("ALL PASS" if ok else "FAILURES PRESENT"))
			quit(0 if ok else 1)
	return false
