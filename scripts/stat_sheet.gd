class_name StatSheet
extends RefCounted
## #376 builds the entries the Tab menu StatGrid shows: the player's stats,
## or (after clicking a spell) that spell's stats. Read-only: every number
## comes from the existing public accessors (Player stats/damage_modifiers,
## Projectile.attacker_modifiers_for, StoneHammerState), so no game math is
## duplicated or changed here.
##
## Entry = {id, value, title, details}; StatGrid renders icon + value and
## puts title + details in the hover card.

static func _pct(v: float, signed := true) -> String:
	return ("%+d%%" if signed else "%d%%") % roundi(v * 100.0)

static func _secs(v: float) -> String:
	return "%.1fs" % v

static func _entry(id: StringName, value: String, title: String, details: String) -> Dictionary:
	return {"id": id, "value": value, "title": title, "details": details}

## Crit chance carried by a DamageModifiers collection (null = none).
static func crit_of(mods: DamageModifiers) -> float:
	var total := 0.0
	if mods != null:
		for m in mods.items():
			if m.stage == DamageModifier.Stage.CRIT:
				total += m.chance
	return total

static func amp_of(mods: DamageModifiers) -> float:
	var total := 0.0
	if mods != null:
		for m in mods.items():
			if m.stage == DamageModifier.Stage.AMP:
				total += m.amount
	return total

## "Sources:" lines for one PlayerStats stat, or "" when nothing modifies it.
static func _sources(player: Player, stat: StringName) -> String:
	var mods := player.stats.modifiers(stat)
	if mods.is_empty():
		return ""
	var lines: Array[String] = ["", "Sources:"]
	for m in mods:
		var amount: String
		var fraction := stat == PlayerStats.DAMAGE_AMP or stat == PlayerStats.ARMOR or stat == PlayerStats.COOLDOWN_REDUCTION
		if m.op == StatModifier.Op.PERCENT or fraction:
			amount = _pct(m.value)
		else:
			amount = "%+d" % roundi(m.value)
		var who := String(m.source).capitalize() if m.source != &"" else "Bonus"
		var timed := " (%ds left)" % ceili(m.time_left) if m.is_timed() else ""
		lines.append("  %s %s%s" % [amount, who, timed])
	return "\n".join(lines)

static func _crit_rule() -> String:
	return "Each 100% is a guaranteed crit tier; the rest rolls for one more."

static func player_entries(player: Player) -> Array:
	var out: Array = []
	if player == null:
		return out
	out.append(_entry(&"hp", "%d/%d" % [player.hp, player.max_hp], "Health",
		"Current / max health.\nBase max: %d" % player.base_max_hp + _sources(player, PlayerStats.MAX_HP)))
	out.append(_entry(&"damage_amp", _pct(player.damage_amp()), "Damage Amp",
		"All your spell hits deal this much extra damage.\nRange %d%% to %+d%%." % [roundi(PlayerStats.DAMAGE_AMP_MIN * 100.0), roundi(PlayerStats.DAMAGE_AMP_MAX * 100.0)]
		+ _sources(player, PlayerStats.DAMAGE_AMP)))
	out.append(_entry(&"armor", _pct(player.armor()), "Armor",
		"Share of incoming damage blocked.\nAt most %d%%; negative means you take extra." % roundi(PlayerStats.ARMOR_MAX * 100.0)
		+ _sources(player, PlayerStats.ARMOR)))
	out.append(_entry(&"move_speed", "%d" % roundi(player.move_speed()), "Move Speed",
		"Pixels per second.\nBase: %d" % roundi(player.speed) + _sources(player, PlayerStats.MOVE_SPEED)))
	out.append(_entry(&"cooldown_reduction", _pct(player.cooldown_reduction()), "Cooldown Reduction",
		"Spell cooldowns are shortened by this much.\nAt most %d%%." % roundi(PlayerStats.COOLDOWN_REDUCTION_MAX * 100.0)
		+ _sources(player, PlayerStats.COOLDOWN_REDUCTION)))
	out.append(_entry(&"crit", _pct(crit_of(player.damage_modifiers), false), "Crit Chance",
		"Chance for a hit to crit for x2.\n" + _crit_rule()
		+ "\nSpells can add their own crit; click a spell to see its total."))
	return out

## The hammer route state applies to every Stone Hammer form (hammer_radius).
static func is_hammer(spell: Spell) -> bool:
	return spell != null and spell.hammer_radius > 0.0

static func spell_entries(spell: Spell, player: Player, caster: SpellCaster) -> Array:
	var out: Array = []
	if spell == null:
		return out
	var mods: DamageModifiers = Projectile.attacker_modifiers_for(player, spell) if player != null else null
	var player_crit := crit_of(player.damage_modifiers) if player != null else 0.0
	var relic_crit := crit_of(mods) - player_crit
	var hammer := is_hammer(spell) and caster != null
	var bonus_crit := caster.hammer_state.bonus_crit if hammer else 0.0

	# Damage: base * (1 + summed AMP) - the DamageCalc order before crit.
	var amp := amp_of(mods)
	var dmg_details := "Damage per hit before crits and enemy armor.\nBase: %d" % roundi(spell.damage)
	if amp != 0.0:
		dmg_details += "\nDamage Amp: %s" % _pct(amp)
	out.append(_entry(&"damage", "%d" % int(spell.damage * (1.0 + amp)), "Damage", dmg_details))

	# Cooldown: the hammer's Rhythm combo shortens the base, then player CDR.
	var base_cd := caster.hammer_state.cooldown_for(spell) if hammer else spell.cooldown
	var cd := player.effective_cooldown(base_cd) if player != null else base_cd
	var cd_details := "Seconds before you can cast it again.\nBase: %s" % _secs(spell.cooldown)
	if hammer and spell.hammer_combo_cdr > 0.0:
		cd_details += "\nCombo: -%s per hit in a row (min %s)" % [_secs(spell.hammer_combo_cdr), _secs(spell.hammer_min_cooldown)]
	if player != null and player.cooldown_reduction() != 0.0:
		cd_details += "\nCooldown Reduction: %s" % _pct(player.cooldown_reduction())
	out.append(_entry(&"cooldown", _secs(cd), "Cooldown", cd_details))

	# Crit: player crit + relics hooked to this spell + Stone Hammer bonus.
	var crit_lines: Array[String] = ["Chance for this spell's hits to crit for x2.", _crit_rule(), "", "Sources:"]
	crit_lines.append("  Player: %s" % _pct(player_crit, false))
	if not is_zero_approx(relic_crit):
		crit_lines.append("  Relics: %s" % _pct(relic_crit))
	if hammer:
		crit_lines.append("  Hammer kills: %s" % _pct(bonus_crit))
		if spell.hammer_kill_crit > 0.0:
			crit_lines.append("  (+%s per kill, lasts the run)" % _pct(spell.hammer_kill_crit, false))
	out.append(_entry(&"crit", _pct(player_crit + relic_crit + bonus_crit, false), "Crit Chance", "\n".join(crit_lines)))

	out.append(_entry(&"range", "%d" % roundi(spell.range), "Range", "How far the spell reaches, in pixels."))
	var shots := maxi(spell.projectile_count, 1) * maxi(spell.burst_count, 1)
	if shots > 1:
		out.append(_entry(&"projectiles", "x%d" % shots, "Projectiles",
			"Projectiles per cast.\n%d per volley x %d volleys" % [maxi(spell.projectile_count, 1), maxi(spell.burst_count, 1)]))
	if spell.pierce_hits > 0:
		out.append(_entry(&"pierce", "%d" % spell.pierce_hits, "Pierce", "Extra enemies each projectile passes through."))
	if hammer:
		var scale := caster.hammer_state.size_scale(spell, player) if player != null else 1.0
		var area_details := "Strike radius, in pixels.\nBase: %d" % roundi(spell.hammer_radius)
		if spell.hammer_crit_scale > 0.0:
			area_details += "\nGrows with crit chance (x%.2f now, max x%.1f)" % [scale, spell.hammer_max_scale]
		out.append(_entry(&"area", "%d" % roundi(spell.hammer_radius * scale), "Area", area_details))
		if spell.hammer_combo_cdr > 0.0 or spell.hammer_dice_every > 0:
			var combo_details := "Strikes in a row that hit an enemy.\nA miss resets it."
			if spell.hammer_dice_every > 0:
				combo_details += "\nEvery %d hits rolls the dice." % spell.hammer_dice_every
			out.append(_entry(&"combo", "%d" % caster.hammer_state.combo_hits, "Combo", combo_details))
	return out
