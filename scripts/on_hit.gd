class_name OnHit
extends RefCounted
## #390: the one shared on-hit event. Every DamageCalc call site reports its
## landed hit here after applying the damage, whatever the delivery
## (projectile, melee, splash, contact), so on-hit effects subscribe once
## instead of being wired per spell or per receiver.
##
##   OnHit.bus().hit_landed.connect(_on_hit)   # func _on_hit(e: HitEvent)
##
## Filter inside the handler (e.attacker == my_player, e.spell.tags.has(...),
## e.killed, e.result.crit_tier ...). A connection bound to a Node is dropped
## automatically when that node is freed, so scene-owned subscribers need no
## cleanup; anything else should disconnect when done.
##
## The bus is a process-wide static: it is NOT rebuilt by the run reload
## (D10). Subscribers live in the scene, so a reload drops them with it.
##
## Scope (foundation only): no existing bespoke wiring (damage numbers,
## Hammer Reaper, relic passives) has been migrated, and no on-hit effect
## content exists yet. Hits that bypass DamageCalc (boss lunges/pulses,
## direct apply_damage calls) do not report.

signal hit_landed(event: HitEvent)

const DELIVERY_PROJECTILE: StringName = &"projectile"
const DELIVERY_MELEE: StringName = &"melee"
const DELIVERY_SPLASH: StringName = &"splash"
const DELIVERY_CONTACT: StringName = &"contact"

static var _bus: OnHit = null

## The shared bus. Created on first use.
static func bus() -> OnHit:
	if _bus == null:
		_bus = OnHit.new()
	return _bus

## True when `target` has an hp property above 0. Targets without hp
## (stubs, terrain) count as alive, so they can never report a kill.
static func is_alive(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var hp: Variant = target.get(&"hp")
	if hp == null:
		return true
	return int(hp) > 0

## Builds the payload and emits hit_landed. Call AFTER the damage is applied,
## with `was_alive` = is_alive(target) sampled BEFORE it, so `killed` means
## "this hit did the kill" (a hit on an already-dead body never counts).
static func report(attacker: Node, spell: Spell, target: Node, result: DamageResult, delivery: StringName, was_alive: bool) -> HitEvent:
	var e := HitEvent.new()
	e.attacker = attacker if attacker != null and is_instance_valid(attacker) else null
	e.spell = spell
	e.target = target
	e.result = result
	e.delivery = delivery
	e.killed = was_alive and not is_alive(target)
	if target != null and is_instance_valid(target) and target is Node2D:
		e.position = (target as Node2D).global_position
	bus().hit_landed.emit(e)
	return e
