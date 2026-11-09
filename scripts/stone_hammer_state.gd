class_name StoneHammerState
extends RefCounted
## #370 Stone Hammer run state, one per SpellCaster (SpellCaster.hammer_state).
## It lives on the caster, not on a Spell resource, so it survives upgrades
## (replace_spell swaps the resource) and resets with the run reload (D10).
##  - Crush route: bonus crit chance earned from hammer kills.
##  - Rhythm route: the consecutive-hit combo that shortens the cooldown,
##    picks the hit tone's pitch and counts toward the dice roll.

signal crit_changed(bonus: float)
signal combo_changed(hits: int)
signal tone_played(step: int, pitch: float)
signal dice_rolled(face: int, entry: RewardEntry)

## The hammer's crits use the shared x2.0 multiplier (#206 convention).
const CRIT_MULTIPLIER := 2.0
## Hit tone: each combo step raises the pitch by this many semitones.
const TONE_SEMITONES_PER_STEP := 2.0

## Permanent (run-long) crit chance from Crush-route kills.
var bonus_crit := 0.0
## Consecutive strikes that hit at least one enemy (Rhythm route).
var combo_hits := 0
## Seconds since the last swing while a combo is alive.
var idle_time := 0.0
var last_tone_step := 0
var last_tone_pitch := 0.0
var rng := RandomNumberGenerator.new()

func _init() -> void:
	rng.randomize()

## Caster clock. `cooling` is true while the hammer is on cooldown; the combo
## only resets once the hammer is off cooldown AND unused for the idle limit.
func tick(delta: float, cooling: bool, idle_limit: float) -> void:
	if combo_hits <= 0:
		return
	idle_time += delta
	if not cooling and idle_limit > 0.0 and idle_time >= idle_limit:
		reset_combo()

func on_cast() -> void:
	idle_time = 0.0

func reset_combo() -> void:
	idle_time = 0.0
	if combo_hits == 0:
		return
	combo_hits = 0
	combo_changed.emit(combo_hits)

## Combo steps that still shorten the cooldown (the pitch caps here too).
static func max_steps(spell: Spell) -> int:
	if spell == null or spell.hammer_combo_cdr <= 0.0:
		return 0
	return maxi(ceili((spell.cooldown - spell.hammer_min_cooldown) / spell.hammer_combo_cdr - 0.0001), 0)

## Base cooldown for the next swing (before the player's cooldown reduction).
func cooldown_for(spell: Spell) -> float:
	if spell.hammer_combo_cdr <= 0.0:
		return spell.cooldown
	return maxf(spell.cooldown - spell.hammer_combo_cdr * combo_hits, spell.hammer_min_cooldown)

## Total crit chance a swing rolls with: the source's own crit modifiers plus
## the Crush-route bonus.
func crit_chance(spell: Spell, source: Node) -> float:
	var total := bonus_crit
	var mods := Projectile.attacker_modifiers_for(source, spell)
	if mods != null:
		for m in mods.items():
			if m.stage == DamageModifier.Stage.CRIT:
				total += m.chance
	return total

## Crush Mastery: strike size multiplier from the current crit chance.
func size_scale(spell: Spell, source: Node) -> float:
	if spell.hammer_crit_scale <= 0.0:
		return 1.0
	return clampf(1.0 + crit_chance(spell, source) * spell.hammer_crit_scale, 1.0, maxf(spell.hammer_max_scale, 1.0))

## The attacker modifiers one swing rolls with: the source's (plus owned
## relics, Projectile.attacker_modifiers_for) and the bonus crit, in a fresh
## copy so nothing accumulates on the source.
func attacker_modifiers(spell: Spell, source: Node) -> DamageModifiers:
	var mods := Projectile.attacker_modifiers_for(source, spell)
	if bonus_crit <= 0.0:
		return mods
	var merged := DamageModifiers.new()
	if mods != null:
		for m in mods.items():
			merged.add(m)
	merged.add(DamageModifier.crit(bonus_crit, CRIT_MULTIPLIER))
	return merged

## Records one landed swing. `hits` counts enemies the hammer itself struck
## (shockwave damage never counts). Returns {tone_step, dice_face, dice_entry}:
## tone_step 0 = no tone, dice_face 0 = no roll.
func register_strike(spell: Spell, hits: int, kills: int) -> Dictionary:
	var out := {"tone_step": 0, "dice_face": 0, "dice_entry": null}
	if spell.hammer_kill_crit > 0.0 and kills > 0:
		bonus_crit += spell.hammer_kill_crit * kills
		crit_changed.emit(bonus_crit)
	if spell.hammer_combo_cdr <= 0.0 and spell.hammer_dice_every <= 0:
		return out
	if hits <= 0:
		# A miss breaks the combo (and with it the cooldown reduction).
		reset_combo()
		return out
	combo_hits += 1
	idle_time = 0.0
	combo_changed.emit(combo_hits)
	if spell.hammer_combo_cdr > 0.0:
		var cap := maxi(max_steps(spell), 1)
		last_tone_step = mini(combo_hits, cap)
		last_tone_pitch = pow(2.0, TONE_SEMITONES_PER_STEP * float(last_tone_step - 1) / 12.0)
		out["tone_step"] = last_tone_step
		tone_played.emit(last_tone_step, last_tone_pitch)
	if spell.hammer_dice_every > 0 and combo_hits % spell.hammer_dice_every == 0:
		var face := rng.randi_range(1, 6)
		var entry: RewardEntry = null
		if face - 1 < spell.hammer_dice_tables.size() and spell.hammer_dice_tables[face - 1] != null:
			entry = spell.hammer_dice_tables[face - 1].roll([])
		out["dice_face"] = face
		out["dice_entry"] = entry
		dice_rolled.emit(face, entry)
	return out
