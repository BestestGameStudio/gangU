class_name UpgradeCatalog
extends RefCounted
## #512: the spell upgrade rows Main hands to SpellProgress, moved out of
## Main._ready unchanged (same rows, same order, same notes). Main used to
## build this list inline; a fresh array is returned per call like before.
## #703 (Daniel, 2026-11-15): upgrade PATHS are gone. Each spell has one
## fixed linear chain through the tiers (Specialization > Mastery >
## Signature); there is no branch choice and no route code. Chains below
## are the owner-confirmed set.

const ROWS: Array[SpellUpgrade] = [
	preload("res://data/upgrades/hook_shot_magnet.tres"),
	preload("res://data/upgrades/hook_shot_catch.tres"),
	preload("res://data/upgrades/hook_shot_rock.tres"),
	preload("res://data/upgrades/water_shot_hover.tres"),
	preload("res://data/upgrades/water_shot_reservoir.tres"),
	preload("res://data/upgrades/water_shot_tide.tres"),
	## Fire Ball chain: split -> split_wide (tiers 1/2).
	preload("res://data/upgrades/fireball_split.tres"),
	preload("res://data/upgrades/fireball_m2_split_wide.tres"),
	## Mana Shot chain: volley (tier 1).
	preload("res://data/upgrades/manashot_volley.tres"),
	## Pickup Bolt chain: flurry (tier 1).
	preload("res://data/upgrades/bolt_flurry.tres"),
	## Spirit Punch chain: burst -> launch -> bubble (tiers 1/2/3).
	preload("res://data/upgrades/spirit_punch_burst.tres"),
	preload("res://data/upgrades/spirit_punch_launch.tres"),
	preload("res://data/upgrades/spirit_punch_bubble.tres"),
	## Water Ball chain: splash -> barrage -> heavy_rain (tiers 1/2/3).
	preload("res://data/upgrades/water_splash.tres"),
	preload("res://data/upgrades/water_barrage.tres"),
	preload("res://data/upgrades/water_heavy_rain.tres"),
	## Stone Hammer chain: reaper -> titan -> vortex (tiers 1/2/3).
	preload("res://data/upgrades/hammer_reaper.tres"),
	preload("res://data/upgrades/hammer_titan.tres"),
	preload("res://data/upgrades/hammer_vortex.tres"),
]

static func all() -> Array[SpellUpgrade]:
	return ROWS.duplicate()
