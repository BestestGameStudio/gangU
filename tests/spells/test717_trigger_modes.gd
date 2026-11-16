extends SceneTree
class WaterTarget extends CharacterBody2D:
	var received := 0.0
	func apply_damage(amount: float): received += amount
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
	check(e.size() == 1 and e[0].command == SpellTriggerRouter.Command.CAST and e[0].mode == Spell.TriggerMode.DEFAULT and e[0].fresh, "short tap casts default on release")
	check(router.sample(&"q", s, true, false, 0.24).is_empty(), "under0.25 does not charge")
	e = router.sample(&"q", s, true, false, 0.01)
	check(e.size() == 1 and e[0].command == SpellTriggerRouter.Command.BEGIN_CHARGE, "0.25 starts charge")
	e = router.sample(&"q", s, false, false, 0.01)
	check(e.size() == 1 and e[0].command == SpellTriggerRouter.Command.RELEASE_CHARGE, "charged release never also taps")
	e = router.sample(&"q", s, true, true, 0.5)
	check(e.size() == 1 and e[0].mode == Spell.TriggerMode.ALTERNATE and e[0].command == SpellTriggerRouter.Command.CAST, "Ctrl selects alternate without plain charge")
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
	# Production charge retry when held through cooldown uses the same route.
	local.cancel_all(); caster.cancel_charge(s)
	caster._cooldowns[s] = 0.1
	caster._trigger_router = SpellTriggerRouter.new()
	Input.action_press(&"spell_slot_3")
	caster._route_trigger_input(s, &"spell_slot_3", false, 0.25)
	check(not caster.is_charging(s), "charge cannot start during cooldown")
	caster._cooldowns.clear()
	caster._route_trigger_input(s, &"spell_slot_3", false, 0.01)
	check(caster.is_charging(s), "held charge retries once cooldown clears")
	Input.action_release(&"spell_slot_3")
	caster._route_trigger_input(s, &"spell_slot_3", false, 0.01)
	check(not caster.is_charging(s) and credits.size() == 3, "actual action release casts one charge")
	caster._trigger_router.cancel_all(); caster._cooldowns.clear()
	other.mode = Spell.CastMode.NONE
	for action: StringName in [&"cast", &"spell_slot_1", &"spell_slot_2", &"spell_slot_3", &"spell_slot_4", &"spell_slot_5"]:
		Input.action_press(action)
		caster._route_trigger_input(other, action, false, 0.01)
		Input.action_release(action)
		caster._route_trigger_input(other, action, false, 0.01)
		caster._cooldowns.clear()
	check(credits.size() == 9, "equipped and all five slot actions use shared routing")
	# Cross-action ownership: a held generic charge reserves its source.
	credits.clear(); caster._cooldowns.clear(); caster._trigger_router = SpellTriggerRouter.new()
	Input.action_press(&"cast")
	caster._route_trigger_input(s, &"cast", false, 0.25)
	Input.action_press(&"spell_slot_3")
	caster._route_trigger_input(s, &"spell_slot_3", true, 0.01)
	check(caster.is_charging(s) and credits.is_empty(), "generic charge blocks alternate cast through another action")
	Input.action_release(&"spell_slot_3");caster._route_trigger_input(s, &"spell_slot_3", true, 0.01)
	Input.action_release(&"cast");caster._route_trigger_input(s, &"cast", false, 0.01)
	check(credits.size() == 1 and caster.cooldown_remaining(s) == charged.cooldown, "charge release commits source only once across keys")
	caster._cooldowns.clear();caster.begin_charge(s)
	caster._start_cooldown(s, 9.0)
	var before := credits.size()
	check(not caster.release_charge(s, charged) and not caster.is_charging(s) and credits.size() == before and caster.cooldown_remaining(s) == 9.0, "charge release cancels rather than firing through active source cooldown")
	# Deferred Big Ball end must charge the equipped source, not the payload.
	caster._cooldowns.clear()
	var big_ball := Spell.new()
	big_ball.mode = Spell.CastMode.SHIELD
	big_ball.cooldown = 8.0
	big_ball.shield_duration = 10.0
	big_ball.shield_radius = 80.0
	big_ball.shield_shot = load("res://data/spells/water_ball.tres")
	s.alternate_spell = big_ball
	Input.action_press(&"spell_slot_3");caster._route_trigger_input(s, &"spell_slot_3", true, 0.01)
	Input.action_release(&"spell_slot_3");caster._route_trigger_input(s, &"spell_slot_3", true, 0.01)
	var shield := caster.active_shield()
	check(shield != null and caster.cooldown_remaining(s) == big_ball.shield_shot.cooldown, "Big Ball alternate initially uses source shot cooldown")
	if shield != null:
		shield.ended.emit(false)
	check(caster.cooldown_remaining(s) == big_ball.cooldown and caster.cooldown_remaining(big_ball) == 0 and caster.cooldown_duration(s) == big_ball.cooldown, "deferred Big Ball full cooldown and HUD stay on source")
	# Water Shot reuses this input consumer; hover and redirect must not become casts.
	caster._cooldowns.clear()
	for shot in get_nodes_in_group(&"projectiles"): shot.queue_free()
	await process_frame
	var ws: Spell = load("res://data/spells/water_shot.tres")
	caster.aim_override = caster.global_position + Vector2(100, 0)
	caster._cast_spell(ws)
	var base_shot: Projectile = caster.live_shots(ws)[0]
	base_shot.set_physics_process(false)
	caster.aim_override = base_shot.global_position + Vector2(0, 200)
	before = credits.size()
	check(caster._redirect_gate(ws, true) and base_shot._redirect_curve_left > 0.0 and credits.size() == before, "Water Shot base redirects once without extra cast credit")
	base_shot._physics_process(0.025)
	check(base_shot.direction.x > 0 and base_shot.direction.y > 0 and base_shot.direction.y < 0.99, "redirect begins a curve rather than instant snap")
	base_shot._physics_process(0.15)
	check(base_shot._redirect_curve_left == 0.0 and base_shot.direction.y > 0.9, "redirect finishes short0.15s bend")
	check(base_shot.get_node("WaterShotArt") is AnimatedSprite2D and base_shot.get_node("WaterShotArt").is_playing() and base_shot.get_node("WaterShotArt").sprite_frames.get_frame_count(&"spin") == 8, "Water Shot ball spins during flight")
	check(not base_shot.can_redirect() and not caster._redirect_gate(ws, true), "base exhausted redirect permits next normal cast")
	# Redirects must make immediate progress toward the new point, not loop
	# through the old heading. Exercise left/right, behind, vertical and near.
	for offset in [Vector2(-200, 0), Vector2(200, 0), Vector2(0, -200), Vector2(0, 200), Vector2(-20, 0)]:
		caster._cast_spell(ws)
		var probe: Projectile = caster.live_shots(ws)[-1]
		probe.set_physics_process(false)
		probe.direction = Vector2.RIGHT
		var start := probe.global_position
		var goal: Vector2 = start + offset
		probe.redirect(goal)
		var forward := true
		for frame in 10:
			var was := probe.global_position
			probe._physics_process(0.015)
			forward = forward and (probe.global_position - was).dot(offset.normalized()) > 0.0
			forward = forward and probe.direction.dot(offset.normalized()) > 0.96
		check(forward, "redirect stays in narrow forward cone without looping: " + str(offset))
		probe.queue_free()
	# Distinct starts must converge on the cursor, not parallel displaced rays.
	for offset_y in [-60.0, 0.0, 60.0]:
		caster._cast_spell(ws)
		var converging: Projectile = caster.live_shots(ws)[-1]
		converging.set_physics_process(false)
		converging.global_position = caster.global_position + Vector2(0, offset_y)
		converging.direction = Vector2.RIGHT
		var goal := caster.global_position + Vector2(180, 0)
		converging.redirect(goal)
		var nearest := 1000.0
		for frame in 450:
			converging._physics_process(0.001)
			nearest = minf(nearest, converging.global_position.distance_to(goal))
		check(nearest < 0.5, "redirect converges within collision core from offset " + str(offset_y))
		converging.queue_free()
	# Fresh alternate redirects travelling shots, not casts; all eligible shots.
	var credit_before := credits.size()
	caster._cast_spell(ws); caster._cast_spell(ws)
	var base_before := caster.live_shots(ws).size()
	caster.aim_override = caster.global_position + Vector2(-200, -100)
	var alt_base := SpellTriggerRouter.new()
	var alt_credits := credits.size()
	caster._consume_trigger_commands(alt_base.sample(&"base_alt", ws, true, true, 0.01), &"base_alt", true)
	check(caster.live_shots(ws).size() == base_before and credits.size() == alt_credits and caster.live_shots(ws).all(func(p): return not p.can_redirect()), "base Ctrl redirects all eligible travelling shots without a cast")
	caster._consume_trigger_commands(alt_base.sample(&"base_alt", ws, false, true, 0.01), &"base_alt", false)
	caster._consume_trigger_commands(alt_base.sample(&"base_alt", ws, true, true, 0.01), &"base_alt", true)
	check(credits.size() == alt_credits, "base exhausted Ctrl does not spawn a shot")
	var hover: Spell = load("res://data/spells/water_shot_hover.tres")
	caster._cast_spell(hover)
	var travelling := caster.live_shots(hover)[-1] as WaterShotProjectile
	travelling.set_physics_process(false)
	var new_target := travelling.global_position + Vector2(100, -60)
	check(travelling.alternate_toward(new_target) and travelling.released and travelling._redirect_curve_left > 0.0, "Hover premature alternate re-aims and permanently releases initial flight")
	check(not travelling.alternate_toward(new_target + Vector2(0, 20)), "Hover travelling redirect is once per shot")
	travelling._physics_process(0.4)
	check(not travelling.hovering and travelling.released, "prematurely released Hover passes target without hovering")
	travelling.queue_free(); await process_frame
	var made: Array[WaterShotProjectile] = []
	for i in 4:
		caster.aim_override = caster.global_position + Vector2(100 + i * 20, 0)
		caster._cast_spell(hover)
		var shot := caster.live_shots(hover)[-1] as WaterShotProjectile
		shot.set_physics_process(false); shot._physics_process(1.0); made.append(shot)
	check(made[0].is_queued_for_deletion() and caster.live_shots(hover).size() == 3, "hover cap3 evicts oldest hovering shot")
	var hp := made[-1]
	check(hp.hovering, "shot reaches captured initial aim and hovers")
	var hover_art := hp.get_node("WaterShotArt") as AnimatedSprite2D
	var previous_frame := hover_art.frame
	await create_timer(0.08).timeout
	check(hover_art.is_playing() and hover_art.frame != previous_frame, "Water Shot loop advances frames while hovering")
	hp.set_frozen(true)
	previous_frame = hover_art.frame
	await create_timer(0.09).timeout
	check(not hover_art.is_playing() and hover_art.frame == previous_frame, "frozen Water Shot animation holds its frame")
	hp.set_frozen(false)
	await create_timer(0.09).timeout
	check(hover_art.is_playing() and hover_art.frame != previous_frame, "unfrozen Water Shot animation resumes")
	caster.aim_override = hp.global_position + Vector2(0, 200)
	before = credits.size()
	var alt_router := SpellTriggerRouter.new()
	caster._consume_trigger_commands(alt_router.sample(&"water_test", hover, true, true, 0.01), &"water_test", true)
	check(not hp.hovering and hp.released and hp._redirect_curve_left > 0.0 and credits.size() == before, "Ctrl-fire releases hover without casting or XP")
	hp._physics_process(0.3)
	check(not hp.hovering and hp.released and not hp.release_toward(Vector2.ZERO), "specialization released shot never hovers or redirects again")

	caster.aim_override = caster.global_position + Vector2(100, 0); caster._cast_spell(hover)
	var expires := caster.live_shots(hover)[-1] as WaterShotProjectile
	expires.set_physics_process(false); expires._physics_process(1.0); expires._physics_process(1.99)
	check(not expires.is_queued_for_deletion(), "hover lives before2s")
	expires._physics_process(0.02); check(expires.is_queued_for_deletion(), "hover expires after2s")
	var sig: Spell = load("res://data/spells/water_shot_tide.tres")
	caster._cast_spell(sig)
	var tide := caster.live_shots(sig)[0] as WaterShotProjectile
	tide.set_physics_process(false); tide._physics_process(1.0)
	caster.aim_override = tide.global_position + Vector2(0, 100)
	check(caster.release_water_shots(sig) == 1 and caster.release_water_shots(sig) == 0, "Signature redirect has0.5s cooldown")
	tide._physics_process(1.0); check(tide.hovering, "Signature released shot returns to hover at target")
	tide._physics_process(100); check(not tide.is_queued_for_deletion(), "Signature hover has no expiry")
	caster._water_redirect_cooldown = 0
	caster.aim_override = tide.global_position + Vector2(200, 0)
	check(caster.release_water_shots(sig) == 1 and tide._redirect_curve_left > 0.0, "Signature can redirect again after cooldown")
	for offset in [Vector2(-200, 0), Vector2(200, 0), Vector2(0, -200), Vector2(0, 200), Vector2(-20, 0)]:
		tide.hovering = true; tide.released = true; tide.direction = Vector2.RIGHT
		var goal: Vector2 = tide.global_position + offset
		tide.release_toward(goal)
		var forward := true
		for frame in 10:
			var was := tide.global_position
			tide._physics_process(0.015)
			if not tide.hovering:
				forward = forward and (tide.global_position - was).dot(offset.normalized()) > 0.0
		check(forward, "Signature release makes forward progress without looping: " + str(offset))
	caster._cast_spell(sig)
	var initial_tide := caster.live_shots(sig)[-1] as WaterShotProjectile
	initial_tide.set_physics_process(false)
	check(not initial_tide.released and initial_tide.alternate_toward(initial_tide.global_position + Vector2(-100, -40)) and initial_tide.released, "Signature alternate redirects first flight, not just released shots")
	check(initial_tide.alternate_toward(initial_tide.global_position + Vector2(100, -40)), "Signature travelling redirect remains repeatable behind caster cooldown")
	check(load("res://data/spells/water_shot_reservoir.tres").tags.has(SpellTags.PIERCING) and sig.tags.has(SpellTags.PIERCING) and not hover.tags.has(SpellTags.PIERCING), "only Mastery/Signature pierce")
	# Real Projectile hit dispatch while stationary: normal damage, with tier-specific survival.
	var landed: Array[HitEvent] = []
	var capture_hit := func(event: HitEvent): landed.append(event)
	OnHit.bus().hit_landed.connect(capture_hit)
	var target := WaterTarget.new(); root.add_child(target)
	caster._cast_spell(hover)
	var fragile := caster.live_shots(hover)[-1] as WaterShotProjectile
	fragile.set_physics_process(false); fragile._physics_process(1.0); fragile._on_body_entered(target)
	check(target.received == hover.damage and fragile.is_queued_for_deletion(), "hover contact deals normal damage and destroys Specialization")
	var reservoir: Spell = load("res://data/spells/water_shot_reservoir.tres")
	caster._cast_spell(reservoir)
	var piercing := caster.live_shots(reservoir)[-1] as WaterShotProjectile
	piercing.set_physics_process(false); piercing._physics_process(1.0)
	var before_damage := target.received
	piercing._on_body_entered(target)
	check(target.received == before_damage + reservoir.damage and not piercing.is_queued_for_deletion() and piercing.hovering, "Mastery contact deals normal damage and retains hovering shot")
	piercing._physics_process(4.99); check(not piercing.is_queued_for_deletion(), "Mastery hover survives before5s")
	piercing._physics_process(0.02); check(piercing.is_queued_for_deletion(), "Mastery hover expires after5s")
	# Repeat hover damage uses normal dispatch, bounded per target and ball.
	tide.hovering = true
	var damage_before := target.received
	tide._on_body_entered(target)
	tide._on_body_entered(target)
	check(target.received == damage_before + sig.damage, "Signature immediate contact hits once, not per-frame")
	check(landed[-1].projectile_id == tide.get_instance_id() and landed[-1].redirected, "landed projectile event snapshots redirect identity for quests")
	tide._physics_process(0.49); tide._on_body_entered(target)
	check(target.received == damage_before + sig.damage, "Signature cannot tick early")
	tide._physics_process(0.011); tide._on_body_entered(target)
	check(target.received == damage_before + sig.damage * 2, "Signature ticks again after contact interval")
	tide.set_frozen(true); tide._physics_process(2.0); tide._on_body_entered(target)
	check(target.received == damage_before + sig.damage * 2, "frozen hover ball cannot tick or advance clock")
	tide.set_frozen(false)
	tide._physics_process(0.51); tide._on_body_entered(target)
	check(target.received == damage_before + sig.damage * 3 and tide._hit_bodies.count(target) == 1, "unfrozen contact resumes without duplicate retained-body entries")
	tide.hovering = false; tide._life_t += 1.0; tide._on_body_entered(target)
	check(target.received == damage_before + sig.damage * 3, "released Signature does not repeat contact on prior body")
	var next_target := WaterTarget.new(); root.add_child(next_target)
	tide.hovering = true; tide._on_body_entered(next_target)
	check(next_target.received == sig.damage, "Signature tick cooldown is per enemy, not global")

	check(SpellDescription.for_spell(sig).contains("Ctrl + fire") and SpellDescription.for_spell(sig).contains("every 0.5s"), "panel uses Ctrl and explains Signature contact tick")
	for shot in caster.live_shots(sig): shot.queue_free()
	await process_frame
	caster.aim_override = caster.global_position + Vector2(100, 0)
	var spread_shots: Array[WaterShotProjectile] = []
	for i in 3:
		caster._cast_spell(sig)
		var shot := caster.live_shots(sig)[-1] as WaterShotProjectile
		shot.set_physics_process(false); shot._physics_process(1); spread_shots.append(shot)
	var anchor := spread_shots[0].global_position
	for shot in spread_shots: shot._physics_process(1)
	check(spread_shots.all(func(shot): return shot.global_position.distance_to(anchor) <= sig.water_shot_hover_spread_speed + 0.1), "hover separation is slow, at most12px per second")
	for i in 180:
		for shot in spread_shots: shot._physics_process(1.0 / 60)
	check(spread_shots[0].global_position.distance_to(spread_shots[1].global_position) > 20 and spread_shots.all(func(shot): return shot.global_position.distance_to(anchor) <= sig.water_shot_hover_spread_radius + 0.1), "coincident hover shots spread inside14px radius without overlap")
	target.queue_free()

	OnHit.bus().hit_landed.disconnect(capture_hit)
	landed.clear()
	main.queue_free();await process_frame
	print("[717] ",checks," checks, ",failed," failures")
	quit(1 if failed else 0)
