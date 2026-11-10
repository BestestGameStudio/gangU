extends SceneTree
## #460 spirit bar + hold-H heal: the player's landed hits on enemies fill a
## spirit bar; with it full, holding H for a short channel heals 20% of max
## HP and empties the bar. Releasing early cancels and keeps the spirit.
## Run headless:
##   godot --headless --path . -s scripts/test460_spirit_heal.gd

var failures := 0
var _area: Node

func _check(ok: bool, label: String) -> void:
	if ok:
		print("[460] ", label, " -> PASS")
	else:
		failures += 1
		print("[460] ", label, " -> FAIL")

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _enemy(pos: Vector2, hp: int = 100000) -> Enemy:
	var e: Enemy = load("res://scenes/enemy.tscn").instantiate()
	e.max_hp = hp
	e.speed = 0.0
	e.contact_damage = 0
	_area.add_child(e)
	e.global_position = pos
	return e

## One landed (or refused) hit through the real OnHit call-site protocol.
func _land(attacker: Node, target: Node, amount: int = 1) -> HitEvent:
	var r := DamageResult.new()
	r.amount = amount
	var rc := OnHit.begin(target)
	target.apply_damage(amount)
	OnHit.end(rc, target)
	return OnHit.report(attacker, null, target, r, OnHit.DELIVERY_PROJECTILE, rc)

func _initialize() -> void:
	root.size = Vector2i(1152, 648)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(5)
	_area = main
	var player: Player = main.get_node("Player")
	var meter := player.get_node_or_null("SpiritMeter") as SpiritMeter
	var hud: HUD = main.get_node("HUD")
	var bar := hud.get_node("Root/SpiritBar") as ProgressBar
	var label := hud.get_node("Root/SpiritBar/SpiritLabel") as Label
	var hp_bar := hud.get_node("Root/HPBar") as Control
	var grid := hud.get_node("Root/SpellGrid") as Control

	_check(meter != null, "player has a SpiritMeter")
	if meter == null:
		quit(1)
		return
	meter.set_physics_process(false) # stepped deterministically below
	_check(InputMap.has_action(SpiritMeter.HEAL_ACTION), "heal action registered")
	var bound_h := false
	for ev in InputMap.action_get_events(SpiritMeter.HEAL_ACTION):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_H:
			bound_h = true
	_check(bound_h, "heal action bound to H")

	# Starting state + HUD.
	_check(meter.spirit == 0.0 and not meter.is_full(), "spirit starts empty")
	_check(bar.visible and is_equal_approx(bar.ratio, 0.0) and label.text == "SPIRIT", "HUD spirit bar visible and empty (label '%s')" % label.text)
	_check(bar.get_global_rect().position.y >= hp_bar.get_global_rect().end.y, "spirit bar sits under the HP bar")
	_check(not grid.get_global_rect().intersects(bar.get_global_rect()), "spell grid clear of the spirit bar")
	_check(hud.reserved_rect().encloses(bar.get_global_rect()), "reserved_rect includes the spirit bar")

	# Only the player's landed hits on enemies count.
	var e := _enemy(player.global_position + Vector2(300, 0))
	await process_frame
	var ev := _land(player, e)
	_check(ev != null and is_equal_approx(meter.spirit, meter.spirit_per_hit), "a landed player hit adds spirit (%.1f)" % meter.spirit)
	await process_frame
	_check(is_equal_approx(bar.ratio, meter.spirit_per_hit / meter.max_spirit), "HUD bar follows spirit (ratio %.2f)" % bar.ratio)
	var before := meter.spirit
	_land(e, player, 1) # enemy hits the player
	player.heal(1)
	_check(meter.spirit == before, "hits the player takes add no spirit")
	_land(null, e)
	_check(meter.spirit == before, "attacker-less hits add no spirit")
	var other := _enemy(player.global_position + Vector2(-300, 0))
	_land(other, e)
	_check(meter.spirit == before, "enemy-on-enemy hits add no spirit")
	var dead := _enemy(player.global_position + Vector2(0, 300), 1)
	_land(player, dead) # kill: lands
	var after_kill := meter.spirit
	_check(is_equal_approx(after_kill, before + meter.spirit_per_hit), "a killing hit counts")
	_check(_land(player, dead) == null and meter.spirit == after_kill, "a refused hit on a dead enemy adds nothing")

	# A real projectile from the player counts end to end.
	var caster: SpellCaster = player.get_node("SpellCaster")
	var spell: Spell = caster.get_slots()[0]
	e.global_position = player.global_position + Vector2(120, 0)
	var spirit_pre := meter.spirit
	caster.aim_override = e.global_position
	caster._cooldowns.erase(spell)
	caster._cast_spell(spell)
	for i in 90:
		await physics_frame
		if meter.spirit > spirit_pre:
			break
	_check(meter.spirit > spirit_pre, "a real cast that hits an enemy fills spirit (%.1f -> %.1f)" % [spirit_pre, meter.spirit])

	# Clamp at max.
	for i in 100:
		meter.add_spirit(meter.spirit_per_hit)
	_check(meter.spirit == meter.max_spirit and meter.is_full(), "spirit clamps at max")
	await process_frame
	_check(is_equal_approx(bar.ratio, 1.0) and label.text.contains("HOLD H"), "HUD says the heal is ready (label '%s')" % label.text)

	# No heal at full HP.
	player.heal(player.max_hp)
	meter.tick_channel(0.1, true)
	_check(not meter.is_channelling() and meter.is_full(), "no channel at full HP; spirit kept")

	# Early release cancels and keeps spirit.
	player.apply_damage(50)
	var hp_hurt := player.hp
	var ended: Array = []
	var healed: Array = []
	meter.channel_ended.connect(func(c): ended.append(c))
	meter.healed.connect(func(a): healed.append(a))
	meter.tick_channel(0.016, true)
	_check(meter.is_channelling(), "holding H with a full bar starts the channel")
	meter.tick_channel(0.5, true)
	await process_frame
	_check(label.text == "HEALING..." and bar.ratio > 0.4 and bar.ratio < 0.6, "HUD shows channel progress (ratio %.2f, '%s')" % [bar.ratio, label.text])
	meter.tick_channel(0.016, false)
	_check(not meter.is_channelling() and ended == [false], "releasing H early cancels")
	_check(player.hp == hp_hurt and meter.is_full(), "cancelled channel heals nothing and keeps spirit")

	# Full hold heals 20% of max HP and empties the bar.
	meter.tick_channel(0.016, true)
	meter.tick_channel(meter.channel_time * 0.5, true)
	_check(player.hp == hp_hurt, "no heal before the hold completes")
	meter.tick_channel(meter.channel_time, true)
	var expected := ceili(player.max_hp * 0.2)
	_check(player.hp == mini(hp_hurt + expected, player.max_hp), "full hold heals 20%% of max HP (%d -> %d, +%d)" % [hp_hurt, player.hp, expected])
	_check(healed == [expected] and ended.back() == true, "healed + channel_ended(true) emitted")
	_check(meter.spirit == 0.0 and not meter.is_channelling(), "heal empties the spirit bar")
	await process_frame
	_check(is_equal_approx(bar.ratio, 0.0) and label.text == "SPIRIT", "HUD bar empties after the heal")
	meter.tick_channel(meter.channel_time * 2.0, true)
	_check(player.hp == mini(hp_hurt + expected, player.max_hp), "empty bar: holding H does nothing")

	# 20% scales with max HP.
	player.stats.add(StatModifier.flat(PlayerStats.MAX_HP, 100))
	_check(meter.heal_amount() == ceili(player.max_hp * 0.2), "heal amount follows max HP (%d of %d)" % [meter.heal_amount(), player.max_hp])

	# Death cancels a running channel.
	meter.add_spirit(meter.max_spirit)
	player.apply_damage(30)
	meter.tick_channel(0.016, true)
	_check(meter.is_channelling(), "channel restarts with a refilled bar")
	player.apply_damage(player.hp)
	meter.tick_channel(0.016, true)
	_check(not meter.is_channelling() and player.hp == 0 and meter.is_full(), "death cancels the channel, spirit kept")
	meter.tick_channel(5.0, true)
	_check(player.hp == 0, "no heal while dead")

	print("[460] RESULT: ", "ALL PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(1 if failures > 0 else 0)
