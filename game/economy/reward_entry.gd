class_name RewardEntry
extends Resource
## Reward table entry (track A, #59): one possible enemy reward.
## Concurrent pool-API pin (lead, 2026-11-07): {kind, spell, item_scene,
## weight}. Item route stays UNWIRED until the #54 content decision lands.

## UPGRADE_TOKEN (#315): boss-only token, routed to SpellProgress on pickup.
## Stays pool-eligible after grant (like CURRENCY) so every boss kill can drop one.
## RELIC (#426): grants `relic` into the run's OwnedRelics on pickup.
## OwnedRelics.add is the duplicate gate, so the pool never tracks it.
## Appended LAST so saved .tres kind integers keep their meaning.
enum Kind { SPELL, ITEM, CURRENCY, UPGRADE_TOKEN, RELIC }

@export var kind: Kind = Kind.SPELL
## The spell this entry grants on pickup (kind SPELL).
@export var spell: Spell
## Reserved for item rewards (kind ITEM; open human choice) - unwired.
@export var item_scene: PackedScene
## Currency granted on pickup (kind CURRENCY, #128). Routed to the run wallet
## by the drop; amounts remain human-open placeholder data.
@export var currency_amount: int = 0
## The relic granted on pickup (kind RELIC, #426).
@export var relic: Relic
## Relative selection weight within the table. Contents/weights/chances are
## human-open; placeholder values only.
@export var weight: float = 1.0
