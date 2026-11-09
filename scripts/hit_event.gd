class_name HitEvent
extends RefCounted
## #390: the standard on-hit payload. One is built per landed hit, after the
## damage has been applied, and handed to every OnHit subscriber.
##
## Delivery-agnostic: a projectile, a hammer slam, a splash and a contact
## swing all produce the same shape. Subscribers must treat it as read-only.

## Who dealt the hit (Player, Enemy, Summon...). May be null or freed.
var attacker: Node
## The spell that produced the hit; null for spell-less hits (contact damage).
var spell: Spell
## Who received it. Still valid when subscribers run, even on a kill
## (Enemy frees itself with queue_free, so it lives until the frame ends).
var target: Node
## The DamageCalc roll: amount, crit, crit_tier.
var result: DamageResult
## True when this hit took the target from alive (hp > 0) to hp <= 0.
var killed: bool = false
## How the hit was delivered: one of the OnHit.DELIVERY_* names.
var delivery: StringName = &""
## World position of the target when hit (Vector2.ZERO when it is not a Node2D).
var position: Vector2 = Vector2.ZERO
