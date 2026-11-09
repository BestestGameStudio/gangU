class_name HitEvent
extends RefCounted
## #390: the standard on-hit payload. One is built per LANDED hit (the
## receiver accepted the damage; refused hits emit nothing) and handed to
## every OnHit subscriber.
##
## Delivery-agnostic: a projectile, a hammer slam, a splash and a contact
## swing all produce the same shape. Subscribers must treat it as read-only.

## Who dealt the hit (Player, Enemy, Summon...). Null when there is none or it
## was freed before the hit landed (a shot outliving its shooter).
var attacker: Node
## The spell that produced the hit; null for spell-less hits (contact damage).
var spell: Spell
## Who received it. Still valid when subscribers run, even on a kill
## (Enemy frees itself with queue_free, so it lives until the frame ends).
var target: Node
## The DamageCalc ROLL: amount, crit, crit_tier. `result.amount` is what was
## dispatched, not what the target lost: overkill against 1 HP still says the
## full roll. Use hp_lost for the HP actually removed.
var result: DamageResult
## HP this hit actually removed, captured at the receiver (0..result.amount).
## Targets without hp report 0.
var hp_lost: int = 0
## True when THIS hit took the target from hp > 0 to 0, captured when the
## receiver applied it - before died() listeners (revive) or later follow-up
## damage could change the target's hp.
var killed: bool = false
## How the hit was delivered: one of the OnHit.DELIVERY_* names.
var delivery: StringName = &""
## World position of the target when hit (Vector2.ZERO when it is not a Node2D).
var position: Vector2 = Vector2.ZERO
