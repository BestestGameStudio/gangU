class_name HitStop
extends Node
## #678: hit stop - a short freeze of gameplay movers on every landed spell
## impact against an enemy, plus a heavier staged "boss stop" on the killing
## blow against a boss: a longer freeze plus a camera cinematic - a hard
## zoom onto the fallen boss, a held beat while the death animation plays
## zoomed, then an ease back to normal play (#687). Direction reference:
## Sakurai's "Breaking Down Attack
## Animations" - holding the impact frame is what sells the hit. (Mitra,
## 2026-11-15 demo feedback: no screen flash - the freeze and zoom carry it.)
##
## One subscriber: the OnHit bus (#390) already reports every landed hit, so
## no per-spell wiring. A hit the receiver refused emits nothing and stops
## nothing.
##
## The freeze reuses the FreezeHold pattern (#305), reference-counted per
## mover but claimed globally from here: every mover in the players /
## enemies / summons / projectiles groups that exposes set_frozen gets ONE
## claim from the active stop, and the claim is released when the stop ends.
## The claim stacks with FreezeBubble claims on the same mover without
## touching them: a bubble-frozen mover stays bubble-frozen after the stop.
## Visual-only CombatEffects (sparks, damage numbers, death bursts), the HUD
## and audio are not movers - they keep playing through the stop. Cooldowns,
## telegraphs and behavior clocks hold because they tick inside the frozen
## physics steps; player input is still read on the next live frame. No
## pause/menu system exists today; when one lands, pause wins.
##
## Timing accumulates this node's own frame delta, divided by
## Engine.time_scale so it counts REAL seconds (only the boss finisher, #692,
## touches the time scale, and it restores 1.0 itself). HitStop is not a
## mover and is never claimed, so the stop is immune to its own freeze.
##
## Overlaps: a hit during an active stop max-EXTENDS it (never stacks, never
## shortens) up to stack_cap from the stop's start, so fan-out and burst
## spells cannot chain into a long freeze. A boss stop replaces the window:
## it restarts the clock at its own longer duration.

## Seconds of freeze for a normal landed hit (before the spell multiplier
## and crit bonus). PLACEHOLDER starting value - final feel is a human
## balance call.
@export var normal_duration: float = 0.05
## Extra freeze seconds per crit tier of the landed hit. PLACEHOLDER.
@export var crit_bonus_per_tier: float = 0.02
## Hard cap in seconds on a normal stop's total length, measured from its
## start; further hits only max-extend up to here. PLACEHOLDER.
@export var stack_cap: float = 0.12
## Boss finisher (#692): the killing blow on a boss runs the whole camera
## beat in slow motion. Engine.time_scale drops to this at the kill and
## stays there for the beat, so the death animation plays in slow-mo under
## the zoom; every mover, the player included, is frozen (input locked)
## for the same span. Then the time scale eases back to 1.0 over
## zoom_out_time. 1.0 = no slow-mo. PLACEHOLDER.
@export var boss_slowmo_scale: float = 0.35
## Boss stop camera beat (#687): zoom multiplier at the peak (1.3 = 30%
## in), reached in zoom_in_time seconds, the frame then HOLDS on the fallen
## boss for boss_focus_hold seconds while the death animation plays zoomed,
## and the zoom eases back to neutral over zoom_out_time as the follow
## returns to the player. All boss-beat times are REAL seconds (the beat
## runs in slow-mo, #692). PLACEHOLDERs - Mitra's ask is maximum impact.
@export var zoom_amount: float = 1.3
@export var zoom_in_time: float = 0.1
@export var boss_focus_hold: float = 2.4
@export var zoom_out_time: float = 0.5

## The follow camera that plays the boss-stop beat. Assigned by main.gd;
## null only in harness scenes without one.
@export var camera: FollowCamera = null

## Groups whose members freeze during a stop (players, enemies, summons and
## both sides' projectiles - the same movers FreezeBubble covers, plus the
## player). Only nodes exposing set_frozen are claimed.
const MOVER_GROUPS: Array[StringName] = [
	PhysicsLayers.PLAYER_GROUP,
	PhysicsLayers.ENEMY_GROUP,
	&"summons",
	&"projectiles",
]

var _active := false
## Seconds since the active stop began, and its current full length.
var _elapsed := 0.0
var _stop_length := 0.0
## Movers this stop currently claims; each entry is ONE claim on that
## mover's own FreezeHold.
var _claimed: Array[Node] = []
## #692: a boss finisher is running (slow-mo + full freeze), and the
## real-time ease of the time scale back to 1.0 after it.
var _boss_active := false
var _ramp_left := 0.0


func _ready() -> void:
	OnHit.bus().hit_landed.connect(_on_hit_landed)


func _process(delta: float) -> void:
	# Counted in REAL seconds: the finisher slows Engine.time_scale, which
	# scales this node's own delta too.
	var real_delta := delta / maxf(Engine.time_scale, 0.001)
	if _ramp_left > 0.0:
		_ramp_left = maxf(_ramp_left - real_delta, 0.0)
		var t := 1.0 - _ramp_left / maxf(zoom_out_time, 0.001)
		Engine.time_scale = lerpf(boss_slowmo_scale, 1.0, t)
	if not _active:
		return

	# Movers spawned mid-stop (a burst spell's later repetitions, a summoned
	# shot) join the SAME stop instead of flying while everything else holds.
	_claim_sweep()
	_elapsed += real_delta
	if _elapsed >= _stop_length:
		_release_all()
		_active = false
		if _boss_active:
			_boss_active = false
			_ramp_left = zoom_out_time
			if zoom_out_time <= 0.0:
				Engine.time_scale = 1.0


## The time scale must never outlive this node (scene change, quit).
func _exit_tree() -> void:
	Engine.time_scale = 1.0


## One claim on every live mover not already claimed by this stop.
func _claim_sweep() -> void:
	for group in MOVER_GROUPS:
		for node in get_tree().get_nodes_in_group(group):
			if _claimed.has(node) or not node.has_method(&"set_frozen"):
				continue
			_claimed.append(node)
			node.call(&"set_frozen", true)
			# A mover can be claimed, released and claimed again by a later
			# stop while its one-shot connection from the first claim is still
			# live - only connect when it is not already.
			var on_exit := _on_claimed_tree_exiting.bind(node)
			if not node.tree_exiting.is_connected(on_exit):
				node.tree_exiting.connect(on_exit, CONNECT_ONE_SHOT)


func _release_all() -> void:
	for node in _claimed:
		if is_instance_valid(node):
			node.call(&"set_frozen", false)
	_claimed.clear()


func _on_claimed_tree_exiting(node: Node) -> void:
	_claimed.erase(node)


func _on_hit_landed(e: HitEvent) -> void:
	if e.target == null or not e.target.is_in_group(PhysicsLayers.ENEMY_GROUP):
		return
	if e.killed and (e.target.is_in_group(&"boss") or _is_defeated_general(e.target)):
		_boss_stop(e.position)
		return
	# Per-spell feel knob (#678): heavier spells carry a higher multiplier.
	var mult := 1.0
	if e.spell != null:
		mult = e.spell.hit_stop
	var duration := normal_duration * mult
	if e.result != null and e.result.crit_tier > 0:
		duration += crit_bonus_per_tier * e.result.crit_tier
	_extend_stop(duration, stack_cap)


## #692: the Sand General (a DesertStatue, not in the "boss" group) gets the
## same finisher on his killing blow.
func _is_defeated_general(target: Node) -> bool:
	return target is DesertStatue and (target as DesertStatue).is_defeated_general()


## Starts a stop, or max-extends the active one (never stacks, never
## shortens) up to `cap` seconds from the stop's start.
func _extend_stop(duration: float, cap: float) -> void:
	if duration <= 0.0 or _boss_active:
		return
	if not _active:
		_active = true
		_elapsed = 0.0
		_stop_length = duration
		_claim_sweep()
		return
	_stop_length = maxf(_stop_length, minf(_elapsed + duration, cap))


## The killing blow on a boss (#692 finisher): slow-mo on, every mover
## frozen (the player's input is locked) and the camera beat started on the
## fallen boss's position. The freeze, the slow-mo and the camera hold all
## last zoom_in_time + boss_focus_hold real seconds; then play resumes and
## the time scale eases back to normal while the zoom eases out.
func _boss_stop(at: Vector2) -> void:
	_active = true
	_boss_active = true
	_elapsed = 0.0
	_ramp_left = 0.0
	_stop_length = zoom_in_time + boss_focus_hold
	Engine.time_scale = clampf(boss_slowmo_scale, 0.05, 1.0)
	_claim_sweep()
	if camera != null:
		camera.boss_focus(at, zoom_amount, zoom_in_time, boss_focus_hold, zoom_out_time)
