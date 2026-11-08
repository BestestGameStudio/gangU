class_name Relic
extends Resource
## (#131, foundation C4) Data-driven relic definition. Relics are passive
## items sold by the hub shop; the owned set and apply seam live in
## owned_relics.gd. Catalog contents and balance numbers belong to C2 -
## this is the data SHAPE only, with placeholder fields.
##
## IDENTITY: `id` is the stable LOGICAL identity. Copies, separate loads
## and reloads of the same relic share one id (duplicates are refused by
## OwnedRelics); distinct relics carry distinct ids and never collapse,
## even with equal display names.

## Stable logical identity. Compared by OwnedRelics.add/has_id and by the
## shop's owned-offer exclusion - never by object pointer.
@export var id: StringName
@export var display_name: String

## (#66) Classification this passive hooks, from the SpellTags controlled
## vocabulary. Metadata only; effect parameters live below.
@export var hooked_tags: Array[StringName] = []

## OPTIONAL passive payload, damage-shaped (DamageModifier scalar fields).
## Zero/neutral values mean "no damage contribution". The generic query
## (OwnedRelics.modifiers_for) matches hooked_tags against the cast spell's
## tags; the shape is DamageModifier but the seam is a plain query, usable
## by consumers other than DamageCalc.
@export var stage: DamageModifier.Stage = DamageModifier.Stage.AMP
@export var amount: float = 0.0
@export var chance: float = 0.0
@export var multiplier: float = 1.0

## Builds a FRESH modifier per call - callers never share mutable state.
func to_modifier() -> DamageModifier:
	var m := DamageModifier.new()
	m.stage = stage
	m.amount = amount
	m.chance = chance
	m.multiplier = multiplier
	return m

func has_neutral_payload() -> bool:
	return amount == 0.0 and chance == 0.0 and multiplier == 1.0

func tags_valid() -> bool:
	for t in hooked_tags:
		if not SpellTags.is_valid(t):
			return false
	return true

## Generic scalar payload for non-damage consumers. No production effect
## keys or balance values are installed by this foundation.
@export var scalar_effects: Dictionary[StringName, float] = {}

func is_valid_definition() -> bool:
	return id != &"" and tags_valid()
