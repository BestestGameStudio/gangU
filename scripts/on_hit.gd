class_name OnHit
extends RefCounted
## #390: the one shared on-hit event. Every DamageCalc call site reports its
## landed hit here, whatever the delivery (projectile, melee, splash,
## contact), so on-hit effects subscribe once instead of being wired per spell
## or per receiver.
##
##   OnHit.bus().hit_landed.connect(_on_hit)   # func _on_hit(e: HitEvent)
##
## Filter inside the handler (e.attacker == my_player, e.spell.tags.has(...),
## e.killed, e.result.crit_tier ...). A connection bound to a Node is dropped
## automatically when that node is freed, so scene-owned subscribers need no
## cleanup; anything else should disconnect when done.
##
## Call-site protocol (review of #410):
##   var receipt := OnHit.begin(target)
##   target.apply_damage(...)                 # receiver calls OnHit.record()
##   OnHit.end(receipt)                       # closes the capture window
##   ... legacy signals ...
##   OnHit.report(attacker, spell, target, result, delivery, receipt)
##
## "Landed" is decided by the RECEIVER, not by the call: production receivers
## (Player, Enemy, Summon, DestroyableContainer, DefenseCore) call
## OnHit.record(self, hp_before, hp_after) at their HP mutation point, before
## they emit health_changed / died. A receiver that returns early (Player
## invulnerability, already dead, a container refusing a non-Player source)
## never records, so its hit is NOT landed and report() emits nothing. An
## accepted hit that removes 0 HP (e.g. a 0 roll) still lands: the receiver
## took it, and hp_lost says 0.
##
## `killed` and `hp_lost` come from that record, so they describe THIS hit at
## the moment it was applied: a synchronous revive in died(), or a legacy
## Projectile.hit listener dealing follow-up damage, cannot change them.
##
## Receivers that are not production receivers (test doubles, future stubs)
## and never record fall back to "accepted", with hp sampled around the
## apply call (no hp property -> never a kill).
##
## Attacker/target arguments are untyped on purpose: a projectile or splash
## can outlive its source, and a previously freed object passed to a typed
## Node parameter is a script error. They are normalized to null here.
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

## One damage application's outcome, captured at the receiver boundary.
class Receipt:
	extends RefCounted
	var target_id: int = 0
	## True once the window was closed by end().
	var closed: bool = false
	## True when the receiver recorded an HP mutation for this application.
	var recorded: bool = false
	## The hit landed (receiver accepted it).
	var accepted: bool = false
	var hp_before: int = 0
	var hp_after: int = 0
	## This application took hp from above 0 to 0.
	var killed: bool = false
	## HP actually removed by this application (<= the rolled amount).
	var hp_lost: int = 0
	## Fallback sampling for non-recording receivers.
	var _fallback_hp: Variant = null

static var _bus: OnHit = null
## instance_id -> Array[Receipt] (stack: nested hits on one target each get
## their own window).
static var _open: Dictionary = {}

## The shared bus. Created on first use.
static func bus() -> OnHit:
	if _bus == null:
		_bus = OnHit.new()
	return _bus

## Returns `obj` when it is a live Object, else null. Safe on freed refs.
static func live(obj: Variant) -> Object:
	if obj == null or not is_instance_valid(obj):
		return null
	return obj as Object

## True when `target` has an hp property above 0. Targets without hp
## (stubs, terrain) count as alive.
static func is_alive(target: Variant) -> bool:
	var t := live(target)
	if t == null:
		return false
	var hp: Variant = t.get(&"hp")
	if hp == null:
		return true
	return int(hp) > 0

## Production receivers record their own outcome; anything else falls back.
static func _records_receipts(t: Object) -> bool:
	return t is Player or t is Enemy or t is Summon or t is DestroyableContainer or t is DefenseCore

## Opens the capture window for one damage application on `target`. Call
## immediately before the apply_damage / apply_damage_from call.
static func begin(target: Variant) -> Receipt:
	var r := Receipt.new()
	var t := live(target)
	if t == null:
		r.closed = true
		return r
	r.target_id = t.get_instance_id()
	r._fallback_hp = t.get(&"hp")
	if not _open.has(r.target_id):
		_open[r.target_id] = []
	(_open[r.target_id] as Array).append(r)
	return r

## Receiver side: called at the HP mutation point, BEFORE health_changed /
## died are emitted. No-op when no DamageCalc window is open for `target`
## (direct apply_damage callers such as boss attacks do not report).
static func record(target: Object, hp_before: int, hp_after: int) -> void:
	if target == null:
		return
	var stack: Variant = _open.get(target.get_instance_id())
	if stack == null or (stack as Array).is_empty():
		return
	var r: Receipt = (stack as Array).back()
	if r.recorded:
		return # first mutation of this application wins
	r.recorded = true
	r.accepted = true
	r.hp_before = hp_before
	r.hp_after = hp_after
	r.hp_lost = maxi(0, hp_before - hp_after)
	r.killed = hp_before > 0 and hp_after <= 0

## Closes the capture window opened by begin(). Call immediately after the
## apply call, before any other listener can run. `target` is the same node
## passed to begin() (may have been freed meanwhile).
static func end(r: Receipt, target: Variant = null) -> Receipt:
	if r == null or r.closed:
		return r
	r.closed = true
	var stack: Variant = _open.get(r.target_id)
	if stack != null:
		(stack as Array).erase(r)
		if (stack as Array).is_empty():
			_open.erase(r.target_id)
	if r.recorded:
		return r
	var t := live(target)
	if t != null and _records_receipts(t):
		return r # a recording receiver that did not record refused the hit
	# Fallback for non-recording receivers (test doubles): accepted, with hp
	# sampled around the apply call.
	r.accepted = true
	if t != null and r._fallback_hp != null:
		var after: Variant = t.get(&"hp")
		if after != null:
			r.hp_before = int(r._fallback_hp)
			r.hp_after = int(after)
			r.hp_lost = maxi(0, r.hp_before - r.hp_after)
			r.killed = r.hp_before > 0 and r.hp_after <= 0
	return r

## Builds the payload from a closed receipt and emits hit_landed. Returns the
## event, or null when the receiver refused the hit (nothing is emitted).
static func report(attacker: Variant, spell: Spell, target: Variant, result: DamageResult, delivery: StringName, receipt: Receipt) -> HitEvent:
	if receipt == null or not receipt.closed or not receipt.accepted:
		return null
	var e := HitEvent.new()
	e.attacker = live(attacker) as Node
	e.spell = spell
	var t := live(target)
	e.target = t as Node
	e.result = result
	e.delivery = delivery
	e.killed = receipt.killed
	e.hp_lost = receipt.hp_lost
	if t is Node2D:
		e.position = (t as Node2D).global_position
	bus().hit_landed.emit(e)
	return e
