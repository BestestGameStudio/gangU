class_name SpellDescription
extends RefCounted
## #399: read-only behavior copy, derived from the same fields consumed by
## SpellCaster, Projectile and the concrete attack nodes. Tags such as burn
## are metadata, not promises of damage-over-time. No stat math lives here.
## Do not key on spell_name: all Spirit Punch tiers share the same name.

static func for_spell(s: Spell) -> String:
	if s == null:
		return ""
	if s.cast_mode() == Spell.CastMode.HOOK:
		if s.hook_anchor_mode or s.alternate_spell != null:
			return "Primary reels a bunch to you and stuns1.5s. Ctrl + fire places up to3fixed anchor/lure pairs. Lures taunt every5s; a caught lure reels with its enemy and the pair disappears on arrival. Deals no damage."
		return ("At the aimed endpoint, reels enemies within %dpx toward you.%s Deals no damage." % [int(s.hook_magnet_radius), " Stuns for1.5s on arrival." if s.hook_arrival_stun > 0 else ""]) if s.hook_magnet_radius > 0 else "Hooks the first enemy toward your moving position. Weight and displacement force set the capped reel speed. Deals no damage."
	var parts: PackedStringArray = []
	if s.water_shot_hover_cap > 0:
		var duration := "indefinitely" if s.water_shot_hover_duration < 0 else "for %ds" % int(s.water_shot_hover_duration)
		return "Stops at the aimed point %s. Up to %d hover; oldest excess disappears. Ctrl + fire releases hovering shots or redirects travelling shots toward the cursor. %s" % [duration, s.water_shot_hover_cap, "Pierces enemies. Hovering contact deals %s damage every %ss. Ctrl + fire re-aims all shots; they hover again at the target." % [s.damage, s.water_shot_contact_interval] if s.water_shot_repeat_redirect else ("Pierces enemies." if s.tags.has(SpellTags.PIERCING) else "Damages enemies on contact, then disappears.")]
	if s.recast_redirect and s.projectile_art != null:
		return "Fires toward the cursor. Fire again or Ctrl + fire during flight to redirect once toward the cursor's new position."
	if s.terrain_block != &"":
		parts.append("Places a breakable terrain block at the aimed cell, if the cell allows it.")
	if s.summon != null:
		parts.append("Summons an ally to fight for you, subject to the shared summon cap.")
	if s.freeze_radius > 0.0:
		parts.append("Creates a freeze bubble where you cast. Enemies, summons and projectiles inside stop; you can still move.")
	var mode := s.cast_mode()
	if mode == Spell.CastMode.HAMMER:
		parts.append("Swings a hammer down at the aim point, damaging enemies around the impact.")
		if s.hammer_vortex_radius > 0.0:
			parts.append("Hold to pull enemies into a vortex; release to swing.")
		if s.hammer_kill_crit > 0.0:
			parts.append("Hammer kills build bonus crit chance for the run.")
		if s.hammer_crit_scale > 0.0:
			parts.append("Crit chance also increases the strike area, up to its cap.")
		if s.hammer_combo_cdr > 0.0:
			parts.append("Consecutive hits shorten cooldown; a miss or long idle resets the combo.")
		if s.hammer_jump:
			parts.append("Jumping protects you during wind-up; the shockwave hits enemies the hammer missed.")
		if s.hammer_dice_every > 0:
			parts.append("Every %d consecutive hits roll a reward die." % s.hammer_dice_every)
	elif mode == Spell.CastMode.SHIELD:
		parts.append("Surrounds you with a bubble that damages touching enemies and absorbs enemy shots until it pops or expires.")
		if s.shield_push_radius > 0.0 and s.shield_push_force > 0.0:
			parts.append("Pushes nearby enemies away when it ends.")
		if s.shield_shot != null:
			parts.append("Cast again while active to fire a Water Ball and shrink the bubble.")
	elif mode == Spell.CastMode.RAIN:
		parts.append("Creates a rain zone at the aim point. Falling drops splash nearby enemies on landing.")
	elif mode == Spell.CastMode.SPLASH:
		if s.projectile_count > 1:
			parts.append("Lobs %d water balls around the aim point; each splashes nearby enemies on landing." % s.projectile_count)
		else:
			parts.append("Lobs a water ball at the aim point, splashing nearby enemies on landing.")
	elif mode == Spell.CastMode.PROJECTILE:
		if s.launch_speed > 0.0:
			parts.append("Launches you toward your aim before attacking.")
		if s.tags.has(SpellTags.MELEE):
			parts.append("Fires a short-range punch toward your aim.")
		elif s.projectile_count > 1:
			parts.append("Fires %d projectiles toward your aim in a spread." % s.projectile_count)
		else:
			parts.append("Fires a projectile toward your aim.")
		if s.burst_count > 1:
			parts.append("Repeats the attack %d times per cast, following your aim between attacks." % s.burst_count)
		if s.recast_redirect:
			if s.redirect_limit > 0:
				parts.append("Press again to redirect flying shots toward your cursor, up to %d time(s) per shot." % s.redirect_limit)
			else:
				parts.append("Press again to redirect flying shots toward your cursor.")
		if s.cursor_chase_time < 0.0:
			parts.append("Shots keep turning toward your cursor.")
		elif s.cursor_chase_time > 0.0:
			parts.append("Shots briefly turn toward your cursor after firing or redirecting.")
		if s.tags.has(SpellTags.HOMING):
			parts.append("Shots turn toward nearby enemies.")
		if s.pierce_hits > 0:
			parts.append("Shots stay until %d hits land and can hit the same enemy again after a short delay." % s.pierce_hits)
		elif s.tags.has(SpellTags.PIERCING):
			parts.append("Shots pass through enemies instead of stopping at the first hit.")
	return " ".join(parts)
