extends SceneTree
var checks := 0
var failed := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failed += 1
	print("[717] ", label, " -> ", "PASS" if ok else "FAIL")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var router := SpellTriggerRouter.new()
	var s := Spell.new()
	var e := router.sample(&"q", s, true, false, 0.016)
	check(e.size() == 1 and e[0].mode == Spell.TriggerMode.DEFAULT, "default press casts immediately")
	check(router.sample(&"q", s, true, false, 0.5).size() == 1, "no-charge hold requests refire")
	check(router.sample(&"q", s, false, false, 0.016).is_empty(), "no-charge release does not duplicate cast")
	s.trigger_modes = Spell.TriggerMode.DEFAULT | Spell.TriggerMode.CHARGING | Spell.TriggerMode.ALTERNATE
	check(router.sample(&"q", s, true, false, 0.1).is_empty(), "tap press waits")
	e = router.sample(&"q", s, false, false, 0.1)
	check(e.size() == 1 and e[0].command == SpellTriggerRouter.Command.CAST and e[0].mode == Spell.TriggerMode.DEFAULT, "short tap casts default on release")
	check(router.sample(&"q", s, true, false, 0.24).is_empty(), "under0.25 does not charge")
	e = router.sample(&"q", s, true, false, 0.01)
	check(e.size() == 1 and e[0].command == SpellTriggerRouter.Command.BEGIN_CHARGE, "0.25 starts charge")
	e = router.sample(&"q", s, false, false, 0.01)
	check(e.size() == 1 and e[0].command == SpellTriggerRouter.Command.RELEASE_CHARGE, "charged release never also taps")
	e = router.sample(&"q", s, true, true, 0.5)
	check(e.size() == 1 and e[0].mode == Spell.TriggerMode.ALTERNATE and e[0].command == SpellTriggerRouter.Command.CAST, "Alt selects alternate without plain charge")
	e = router.sample(&"q", s, true, false, 0.5)
	check(e.size() == 1 and e[0].mode == Spell.TriggerMode.ALTERNATE, "modifier choice latched per press")
	router.cancel_all()
	s.alternate_can_charge = true
	e = router.sample(&"q", s, true, true, 0.25)
	check(e.size() == 1 and e[0].alternate and e[0].command == SpellTriggerRouter.Command.BEGIN_CHARGE, "explicit alternate charge declaration")
	check(router.cancel_all().size() == 1 and router.sample(&"q", s, false, true, 1).is_empty(), "cancel drops pending release")
	s.alternate_can_charge = false
	router.sample(&"q", s, true, false, 0.3)
	var other := Spell.new()
	e = router.sample(&"q", other, true, false, 0.016)
	check(e.size() == 2 and e[0].command == SpellTriggerRouter.Command.CANCEL_CHARGE and e[1].spell == other, "slot replacement cancels old charge")
	router.cancel_all()
	var vortex: Spell = load("res://data/spells/stone_hammer_vortex.tres")
	e = router.sample(&"q", vortex, true, false, 0.001)
	check(e.size() == 1 and e[0].command == SpellTriggerRouter.Command.BEGIN_CHARGE, "vortex retains immediate charging through data")
	check(vortex.trigger_modes == Spell.TriggerMode.CHARGING and vortex.charge_delay == 0, "vortex migration is explicit")
	var alternate := Spell.new()
	var charged := Spell.new()
	s.alternate_spell = alternate; s.charged_spell = charged
	check(s.trigger_payload(Spell.TriggerMode.ALTERNATE) == alternate and s.trigger_payload(Spell.TriggerMode.CHARGING) == charged, "declarative payloads selected")
	check(other.trigger_payload(Spell.TriggerMode.DEFAULT) == other, "ordinary spell payload unchanged")
	# Real caster integration, same consumer used by all seven cast keys.
	var main: Node = load("res://game/core/main.tscn").instantiate()
	root.add_child(main); current_scene = main
	await process_frame
	var caster: SpellCaster = main.get_node("Player/SpellCaster")
	caster.set_process(false)
	var credits: Array[Spell] = []
	caster.spell_cast.connect(func(spell: Spell): credits.append(spell))
	s.mode = Spell.CastMode.NONE; alternate.mode = Spell.CastMode.NONE; charged.mode = Spell.CastMode.NONE
	s.cooldown = 1.0; alternate.cooldown = 2.0; charged.cooldown = 3.0
	caster.unlock_spell(s); caster.assign_slot(2, s)
	var local := SpellTriggerRouter.new()
	caster._consume_trigger_commands(local.sample(&"q", s, true, true, 0.016), &"q", true)
	check(credits.size() == 1 and credits[0] == s and caster.cooldown_remaining(s) == 2, "alternate uses payload effect but source cooldown and cast credit")
	caster._consume_trigger_commands(local.sample(&"q", s, true, true, 0.5), &"q", false)
	check(credits.size() == 1, "held alternate cannot bypass source cooldown")
	caster._cooldowns.clear(); local.cancel_all()
	caster._consume_trigger_commands(local.sample(&"q", s, true, false, 0.25), &"q", true)
	check(caster.is_charging(s) and credits.size() == 1, "generic charge begins without hammer special case")
	caster._consume_trigger_commands(local.sample(&"q", s, false, false, 0.01), &"q", false)
	check(not caster.is_charging(s) and credits.size() == 2 and caster.cooldown_remaining(s) == 3, "generic charge release casts declared payload once")
	caster._cooldowns.clear()
	caster._consume_trigger_commands(local.sample(&"q", s, true, false, 0.25), &"q", true)
	caster._consume_trigger_commands(local.cancel_all(), &"", false)
	check(not caster.is_charging(s) and credits.size() == 2, "modal cancellation does not fire")
	main.queue_free();await process_frame
	print("[717] ",checks," checks, ",failed," failures")
	quit(1 if failed else 0)
