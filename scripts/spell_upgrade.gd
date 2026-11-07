class_name SpellUpgrade
extends Resource
## Spell upgrade definition (progression provider for F, #62). Approved
## direction (Daniel, 2026-11-07): manual upgrades, chosen by the player from
## the shared Tab spell panel; placeholder paths OK (fireball A split shot,
## B beam). XP use-qualification and thresholds are OPEN human choices.

## Stable id, e.g. &"fireball_split".
@export var id: StringName
## Player-facing name, e.g. "Split shot".
@export var display_name: String
## The spell this upgrade replaces (must be unlocked on the caster).
@export var source_spell: Spell
## The upgraded spell. NULL in placeholders: split/beam spell CONTENT is not
## decided; only the upgrade paths are approved. apply_upgrade refuses while
## this is null.
@export var result_spell: Spell
## XP threshold placeholder - thresholds are an open human choice.
@export var xp_threshold: int = 0
