class_name RewardEntry
extends Resource
## Reward table entry (track A, #59): one possible enemy reward.
## Concurrent pool-API pin (lead, 2026-11-07): {kind, spell, item_scene,
## weight}. Item route stays UNWIRED until the #54 content decision lands.

enum Kind { SPELL, ITEM }

@export var kind: Kind = Kind.SPELL
## The spell this entry grants on pickup (kind SPELL).
@export var spell: Spell
## Reserved for item rewards (kind ITEM; open human choice) - unwired.
@export var item_scene: PackedScene
## Relative selection weight within the table. Contents/weights/chances are
## human-open; placeholder values only.
@export var weight: float = 1.0
