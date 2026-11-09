class_name SpellDescription
extends RefCounted
## #399: read-only player-facing descriptions of the existing spell behavior.
## Kept separate from Spell resources and stat math. The stats panel owns
## displaying this text; upgrade-choice cards remain a separate concern.

static func for_spell(spell: Spell) -> String:
	if spell == null:
		return ""
	return ""
