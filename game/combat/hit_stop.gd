class_name HitStop
extends Node
## #678: hit stop - a short freeze of gameplay movers on every landed spell
## impact against an enemy, plus a heavier staged "boss stop" on the killing
## blow against a boss: a longer freeze, a screen flash and a camera zoom
## punch, then a snap back to normal play. Direction reference: Sakurai's
## "Breaking Down Attack Animations" - holding the impact frame is what
## sells the hit.
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
## Timing runs on wall-clock milliseconds (Time.get_ticks_msec), never on
## mover clocks, so the stop itself is immune to its own freeze.
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
## Boss stop: freeze seconds on the killing blow against a boss. Replaces
## the normal stop for that hit. PLACEHOLDER.
@export var boss_stop_duration: float = 0.4
## Boss stop flash: full-screen ColorRect flashed at this color and peak
## alpha, fading back over flash_fade_time seconds. PLACEHOLDERs.
@export var flash_color: Color = Color.WHITE
@export var flash_intensity: float = 0.85
@export var flash_fade_time: float = 0.2
## Boss stop camera punch: zoom multiplier at the peak (1.15 = 15% in),
## reaching it in zoom_in_time seconds and easing back to neutral over
## zoom_out_time seconds as play resumes. PLACEHOLDERs.
@export var zoom_amount: float = 1.15
@export var zoom_in_time: float = 0.08
@export var zoom_out_time: float = 0.35

## The follow camera the boss stop punches. Assigned by main.gd; null only
## in harness scenes without one, where the flash still plays.
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
var _stop_start_msec := 0
var _stop_end_msec := 0
## Movers this stop currently claims; each entry is ONE claim on that
## mover's own FreezeHold.
var _claimed: Array[Node] = []
var _flash_rect: ColorRect = null
var _flash_tween: Tween = null


func _ready() -> void:
	OnHit.bus().hit_landed.connect(_on_hit_landed)
	# The flash overlay lives on a high canvas layer so it covers the world
	# and HUD alike; it stays invisible (alpha 0) outside a boss stop.
	var layer := CanvasLayer.new()
	layer.name = "HitStopFlashLayer"
	layer.layer = 100
	add_child(layer)
	_flash_rect = ColorRect.new()
	_flash_rect.name = "Flash"
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.color = Color(flash_color, 0.0)
	layer.add_child(_flash_rect)


func _process(_delta: float) -> void:
	if not _active:
		return
	# Movers spawned mid-stop (a burst spell's later repetitions, a summoned
	# shot) join the SAME stop instead of flying while everything else holds.
	_claim_sweep()
	if Time.get_ticks_msec() >= _stop_end_msec:
		_release_all()
		_active = false


## One claim on every live mover not already claimed by this stop.
func _claim_sweep() -> void:
	for group in MOVER_GROUPS:
		for node in get_tree().get_nodes_in_group(group):
			if _claimed.has(node) or not node.has_method(&"set_frozen"):
				continue
			_claimed.append(node)
			node.call(&"set_frozen", true)
			node.tree_exiting.connect(_on_claimed_tree_exiting.bind(node), CONNECT_ONE_SHOT)


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
	if e.killed and e.target.is_in_group(&"boss"):
		_boss_stop()
		return
	# Per-spell feel knob (#678): heavier spells carry a higher multiplier.
	var mult := 1.0
	if e.spell != null:
		mult = e.spell.hit_stop
	var duration := normal_duration * mult
	if e.result != null and e.result.crit_tier > 0:
		duration += crit_bonus_per_tier * e.result.crit_tier
	_extend_stop(duration, stack_cap)


## Starts a stop, or max-extends the active one (never stacks, never
## shortens) up to `cap` seconds from the stop's start.
func _extend_stop(duration: float, cap: float) -> void:
	if duration <= 0.0:
		return
	var now := Time.get_ticks_msec()
	if not _active:
		_active = true
		_stop_start_msec = now
		_stop_end_msec = now + _msec(duration)
		_claim_sweep()
		return
	var wanted := mini(now + _msec(duration), _stop_start_msec + _msec(cap))
	_stop_end_msec = maxi(_stop_end_msec, wanted)


## The killing blow on a boss: restarts the window at the boss duration,
## then flash + zoom punch. Play snaps back when the window ends.
func _boss_stop() -> void:
	var now := Time.get_ticks_msec()
	_active = true
	_stop_start_msec = now
	_stop_end_msec = now + _msec(boss_stop_duration)
	_claim_sweep()
	_flash()
	if camera != null:
		camera.zoom_punch(zoom_amount, zoom_in_time, zoom_out_time)


func _flash() -> void:
	if _flash_tween != null and _flash_tween.is_running():
		_flash_tween.kill()
	_flash_rect.color = Color(flash_color, flash_intensity)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_rect, ^"color:a", 0.0, flash_fade_time)


static func _msec(seconds: float) -> int:
	return int(round(seconds * 1000.0))
