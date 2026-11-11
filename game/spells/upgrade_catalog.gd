class_name UpgradeCatalog
extends RefCounted
## #512: the spell upgrade rows Main hands to SpellProgress, moved out of
## Main._ready unchanged (same rows, same order, same notes). Main used to
## build this list inline; a fresh array is returned per call like before.

const ROWS: Array[SpellUpgrade] = [
	preload("res://data/upgrades/fireball_split.tres"),
	preload("res://data/upgrades/fireball_beam.tres"),
	## Mastery-tier forks (2026-11-07, lead's numeric placeholder choices
	## under Colin's judgment grant - NOT preexisting owner-approved
	## content): 15 casts of a Specialization result qualify its fork.
	preload("res://data/upgrades/fireball_m2_split_wide.tres"),
	preload("res://data/upgrades/fireball_m2_split_heavy.tres"),
	preload("res://data/upgrades/fireball_m2_beam_long.tres"),
	preload("res://data/upgrades/fireball_m2_beam_heavy.tres"),
	preload("res://data/upgrades/fireball_m2_beam_piercing.tres"),
	preload("res://data/upgrades/fireball_m2_beam_homing.tres"),
	## (#211) Mana Shot Specialization paths: Volley (3-bolt fan) and
	## Lance (heavy piercing rail). Branch design and numbers are the
	## implementer's delegated discretion for this issue (Daniel via
	## staff-lead relay, 2026-11-08); 10-cast threshold mirrors the
	## approved Fire Ball tier-1 precedent.
	preload("res://data/upgrades/manashot_volley.tres"),
	preload("res://data/upgrades/manashot_lance.tres"),
	## (#265) Pickup Bolt Specialization paths: Flurry (faster, lighter)
	## and Heavy (slower piercing hitter). Branch design and numbers are
	## the implementer's delegated discretion for this issue (Daniel via
	## staff-lead relay, 2026-11-08); 10-cast threshold mirrors the
	## approved Fire Ball / Mana Shot tier-1 precedent.
	preload("res://data/upgrades/bolt_flurry.tres"),
	preload("res://data/upgrades/bolt_heavy.tres"),
	## Spirit Punch route (#305): base -> burst -> launch -> bubble,
	## tiers 1/2/3. Cast thresholds 10/15/20 are provisional
	## implementation discretion, not approved final balance.
	preload("res://data/upgrades/spirit_punch_burst.tres"),
	preload("res://data/upgrades/spirit_punch_launch.tres"),
	preload("res://data/upgrades/spirit_punch_bubble.tres"),
	## Water Ball tree (#331): three branches from the base, tiers
	## 1/2/3 each - Steer (guided -> seeking -> tidal seeker), Splash
	## (splash -> barrage -> heavy rain), Bubble (water bubble ->
	## surging -> big ball). Thresholds 10/15/20 mirror #305 and are
	## provisional, not approved final balance.
	preload("res://data/upgrades/water_guided.tres"),
	preload("res://data/upgrades/water_seeking.tres"),
	preload("res://data/upgrades/water_tidal.tres"),
	preload("res://data/upgrades/water_splash.tres"),
	preload("res://data/upgrades/water_barrage.tres"),
	preload("res://data/upgrades/water_heavy_rain.tres"),
	preload("res://data/upgrades/water_bubble.tres"),
	preload("res://data/upgrades/water_surging_bubble.tres"),
	preload("res://data/upgrades/water_big_ball.tres"),
	## Stone Hammer tree (#370): two routes from the base, tiers 1/2/3
	## each - Crush (reaper -> titan -> vortex) and Rhythm (rhythm ->
	## leap -> dice roll). One route per run, like Water Ball.
	## Thresholds 10/15/20 mirror #305/#331 and are provisional.
	preload("res://data/upgrades/hammer_reaper.tres"),
	preload("res://data/upgrades/hammer_titan.tres"),
	preload("res://data/upgrades/hammer_vortex.tres"),
	preload("res://data/upgrades/hammer_rhythm.tres"),
	preload("res://data/upgrades/hammer_leap.tres"),
	preload("res://data/upgrades/hammer_gambler.tres"),
]

static func all() -> Array[SpellUpgrade]:
	return ROWS.duplicate()
