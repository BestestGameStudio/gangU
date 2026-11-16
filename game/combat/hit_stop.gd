class_name HitStop
extends Node
## #678 / #696: hit stop - the short freeze that sells a landed hit - plus the
## staged boss finisher (#687, #692) on a boss's killing blow. Direction
## reference: Sakurai's "Breaking Down Attack Animations" - holding the impact
## frame is what sells the hit. (Mitra, 2026-11-15: no screen flash.)
##
## One subscriber: the OnHit bus (#390) reports every landed hit, so there is
## no per-spell wiring. A hit the receiver refused emits nothing and stops
## nothing. Damage, collision and knockback, hit flashes, sparks, damage
## numbers and sounds are separate systems that run whether or not a stop is
## granted; skipping a stop never skips them.
##
## #696 - why this was reworked: every landed hit used to start or extend a
## GLOBAL freeze (player, every enemy, summons, projectiles) with no cooldown
## and no budget, so fan-out, pierce and rapid fire re-armed it back to back
## and the game looked like it lagged.
##
## DECISION RULES (all numbers are the exported knobs below):
## 1. Boss finisher first. A boss's killing blow (#692) owns everything:
##    normal stops are ignored while it runs and cannot shorten or extend it.
## 2. LOCAL by default. A hit freezes only the enemy it hit (its movement and
##    animation), for a few frames. The player and the rest of the world keep
##    running. Merges overlapping requests by max remaining time, capped from
##    the stop's start, and a short re-arm gap stops a stream of hits from
##    holding one enemy frozen.
## 3. GLOBAL only for significant hits, on top of the local stop. A hit is
##    HEAVY when its attack metadata says so: roll amount >= heavy_min_damage,
##    Spell.hit_stop >= heavy_min_multiplier, or crit tier >= heavy_min_crit_tier.
##    The global freeze needs the global cooldown to have elapsed and budget
##    left in the rolling window (default 100 ms per 1 s). Otherwise the
##    global part is skipped (never queued) and the local stop still plays.
##    Heavy hits inside impact_window of a global stop's start are the same
##    impact: they merge by max remaining time, never add up.
## 4. RAPID spells (cooldown <= rapid_max_cooldown) never get a global stop.
## 5. MULTI-HIT spells (several projectiles, pierce, splash) stop on the first
##    hit of a volley and on a killing hit, not on every hit in between.
##
## Freezes reuse the FreezeHold seam (#305): reference-counted per mover, so
## they stack safely with FreezeBubble claims without touching them. The
## cooldowns and behavior clocks hold because they tick inside the frozen
## physics steps; input is read again on the first live frame.
##
## Timing accumulates this node's own frame delta divided by Engine.time_scale,
## so it counts REAL seconds even while the boss finisher slows the game.
## HitStop is not a mover and is never claimed, so a stop cannot freeze itself.

## One frame at the project's 60 fps physics rate, in seconds. Frame knobs
## below convert with this.
const FRAME := 1.0 / 60.0

@export_group("Local stop (the enemy that was hit)")
## Frames of freeze on the hit enemy for a normal impact. PLACEHOLDER.
@export_range(0, 30) var local_frames_normal: int = 3
## Frames for a heavy impact. PLACEHOLDER.
@export_range(0, 30) var local_frames_heavy: int = 5
## Frames for a rapid-fire impact. PLACEHOLDER.
@export_range(0, 30) var local_frames_rapid: int = 1
## Extra frames per crit tier of the landed hit. PLACEHOLDER.
@export_range(0, 10) var local_frames_per_crit_tier: int = 1
## Hard cap in frames on one local stop, measured from its start. PLACEHOLDER.
@export_range(0, 60) var local_cap_frames: int = 8
## Frames after a local stop ends before the same enemy can be stopped again,
## so a stream of hits cannot hold it frozen. PLACEHOLDER.
@export_range(0, 60) var local_regap_frames: int = 3

@export_group("Hit categories")
## A hit is HEAVY when its rolled damage is at least this. PLACEHOLDER.
@export var heavy_min_damage: int = 40
## ...or the spell's Spell.hit_stop multiplier is at least this.
@export var heavy_min_multiplier: float = 1.5
## ...or the hit's crit tier is at least this.
@export var heavy_min_crit_tier: int = 2
## A spell with a cooldown at or below this (seconds) is RAPID: it never gets
## a global stop. PLACEHOLDER.
@export var rapid_max_cooldown: float = 0.4
## Seconds after a multi-hit spell's stopping hit during which its further
## non-killing hits stop nothing (the volley is one impact). PLACEHOLDER.
@export var multi_hit_window: float = 0.4

@export_group("Global stop (the whole world)")
## Frames of global freeze for a heavy impact (on top of its local stop).
## PLACEHOLDER.
@export_range(0, 30) var global_frames_heavy: int = 4
## Hard cap in frames on one global stop, measured from its start.
@export_range(0, 30) var global_cap_frames: int = 6
## Minimum seconds between global stop starts. PLACEHOLDER.
@export var global_cooldown: float = 0.3
## Rolling budget: at most this many seconds of global freeze per
## budget_window seconds (100 ms per second). PLACEHOLDER.
@export var global_budget_seconds: float = 0.1
@export var global_budget_window: float = 1.0
## Heavy hits arriving this many seconds after a global stop began are the
## same impact: they merge into it by max remaining time. PLACEHOLDER.
@export var impact_window: float = 0.05

@export_group("Boss finisher")
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
## Real seconds of the pan + zoom ramp onto the boss (#692: Mitra asked for
## a more gradual ramp; was a 0.1s snap). Eased in and out.
@export var zoom_in_time: float = 0.9
## Real seconds the camera HOLDS on the fallen boss (slow-mo + input lock).
@export var boss_focus_hold: float = 1.8
## Real seconds for the zoom and the time scale to ease back to normal.
@export var zoom_out_time: float = 0.5


@export_group("")
## The follow camera that plays the boss-stop beat. Assigned by main.gd;
## null only in harness scenes without one.
@export var camera: FollowCamera = null

## Groups whose members freeze during a GLOBAL stop (players, enemies, summons
## and both sides' projectiles - the same movers FreezeBubble covers, plus the
## player). Only nodes exposing set_frozen are claimed.
const MOVER_GROUPS: Array[StringName] = [
	PhysicsLayers.PLAYER_GROUP,
	PhysicsLayers.ENEMY_GROUP,
	&"summons",
	&"projectiles",
]

## Real seconds this node has run (sum of delta / Engine.time_scale).
var _now := 0.0
## Global stop (also the boss finisher's freeze).
var _active := false
var _elapsed := 0.0
var _stop_length := 0.0
var _last_global_start := -1000.0
## Movers the global stop currently claims; ONE claim each.
var _claimed: Array[Node] = []
## Global freeze seconds granted: Vector2(granted_at, seconds), pruned to the
## budget window.
var _budget_log: Array[Vector2] = []
## Local stops: enemy -> {elapsed, len}. Re-arm gate: enemy -> real time
## before which no new local stop may start.
var _local: Dictionary = {}
var _local_gate: Dictionary = {}
## Multi-hit volleys: Spell instance id -> real time of its last stopping hit.
var _volley_at: Dictionary = {}
## A boss finisher is running (slow-mo + full freeze), and the real-time ease
## of the time scale back to 1.0 after it.
var _boss_active := false
var _ramp_left := 0.0


func _ready() -> void:
	OnHit.bus().hit_landed.connect(_on_hit_landed)


func _process(delta: float) -> void:
	# REAL seconds: the finisher slows Engine.time_scale, which scales this
	# node's own delta too.
	var real_delta := delta / maxf(Engine.time_scale, 0.001)
	_now += real_delta
	if _ramp_left > 0.0:
		_ramp_left = maxf(_ramp_left - real_delta, 0.0)
		var t := 1.0 - _ramp_left / maxf(zoom_out_time, 0.001)
		Engine.time_scale = lerpf(boss_slowmo_scale, 1.0, t)
	_tick_local(real_delta)
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


## --- Queries (used by the harness and handy for debugging) ----------------

## True while a global stop or the boss finisher freezes the world.
func is_global_active() -> bool:
	return _active


func is_boss_active() -> bool:
	return _boss_active


## True while `node` is inside a local stop of its own.
func is_local_active(node: Node) -> bool:
	return _local.has(node)


## Seconds of global freeze still available in the rolling window.
func global_budget_left() -> float:
	_prune_budget()
	var used := 0.0
	for entry in _budget_log:
		used += entry.y
	return maxf(global_budget_seconds - used, 0.0)


## --- Global claims -----------------------------------------------------------

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


func _prune_budget() -> void:
	while not _budget_log.is_empty() and _budget_log[0].x <= _now - global_budget_window:
		_budget_log.pop_front()


## --- The decision ------------------------------------------------------------

func _on_hit_landed(e: HitEvent) -> void:
	if e.target == null or not e.target.is_in_group(PhysicsLayers.ENEMY_GROUP):
		return
	if e.killed and (e.target.is_in_group(&"boss") or _is_defeated_general(e.target)):
		_boss_stop(e.position)
		return
	# Rule 1: the boss finisher owns the world until it is over.
	if _boss_active:
		return
	# Rule 5: a multi-hit volley stops on its first hit and on a kill only.
	if e.spell != null and _is_multi_hit(e.spell):
		var key := e.spell.get_instance_id()
		if not e.killed and _now - float(_volley_at.get(key, -1000.0)) < multi_hit_window:
			return
		_volley_at[key] = _now
	var rapid := e.spell != null and e.spell.cooldown <= rapid_max_cooldown
	var heavy := not rapid and _is_heavy(e)
	var mult := 1.0
	if e.spell != null:
		mult = e.spell.hit_stop
	var frames := local_frames_heavy if heavy else (local_frames_rapid if rapid else local_frames_normal)
	if e.result != null:
		frames += local_frames_per_crit_tier * e.result.crit_tier
	# Rule 3: heavy hits ask for a global stop; the local stop is the fallback.
	if heavy and _request_global(global_frames_heavy * FRAME * mult):
		return
	# Rule 2: local by default. A kill needs none - the enemy is about to go.
	if not e.killed:
		_request_local(e.target, frames * FRAME * mult)


## Heavy by the attack's own metadata (no spell names): roll, multiplier, crit.
func _is_heavy(e: HitEvent) -> bool:
	if e.result != null and (e.result.amount >= heavy_min_damage or e.result.crit_tier >= heavy_min_crit_tier):
		return true
	return e.spell != null and e.spell.hit_stop >= heavy_min_multiplier


## Several hits per cast: more than one projectile, a piercing shot, a splash.
func _is_multi_hit(spell: Spell) -> bool:
	return spell.projectile_count > 1 or spell.pierce_hits > 0 or spell.splash_radius > 0.0


## Asks for a global stop of `seconds`. Returns true when the world is (now)
## frozen for it - started, or merged into the running impact - and false
## when it was rejected (cooldown, budget, or a stop already running past its
## impact window). A rejected request is dropped, never queued.
func _request_global(seconds: float) -> bool:
	if seconds <= 0.0:
		return false
	var cap := global_cap_frames * FRAME
	if _active:
		if _elapsed > impact_window:
			# A running freeze is never restarted or stretched by later hits.
			return false
		# Same impact: merge by max remaining time, capped from the start.
		var wanted := minf(_elapsed + seconds, cap)
		var extra := wanted - _stop_length
		if extra <= 0.0:
			return true
		var granted := minf(extra, global_budget_left())
		if granted < FRAME * 0.5:
			return true # the running stop already covers this impact
		_stop_length += granted
		_budget_log.append(Vector2(_now, granted))
		return true
	if _now - _last_global_start < global_cooldown:
		return false
	var allowed := minf(minf(seconds, cap), global_budget_left())
	if allowed < FRAME * 0.5:
		return false
	_active = true
	_elapsed = 0.0
	_stop_length = allowed
	_last_global_start = _now
	_budget_log.append(Vector2(_now, allowed))
	_claim_sweep()
	return true


## Asks for a local stop of `seconds` on one enemy. Max-merges into a running
## local stop (capped from its start); respects the re-arm gap; skips an enemy
## the global stop already holds.
func _request_local(target: Node, seconds: float) -> void:
	if seconds <= 0.0 or not target.has_method(&"set_frozen"):
		return
	var cap := local_cap_frames * FRAME
	if _local.has(target):
		var st: Dictionary = _local[target]
		var wanted := minf(float(st["elapsed"]) + seconds, cap)
		st["len"] = maxf(float(st["len"]), wanted)
		return
	if _now < float(_local_gate.get(target, -1.0)):
		return
	if _active and _claimed.has(target):
		return
	_local[target] = {"elapsed": 0.0, "len": minf(seconds, cap)}
	target.call(&"set_frozen", true)
	var on_exit := _on_local_tree_exiting.bind(target)
	if not target.tree_exiting.is_connected(on_exit):
		target.tree_exiting.connect(on_exit, CONNECT_ONE_SHOT)


func _tick_local(real_delta: float) -> void:
	if _local.is_empty():
		return
	for target in _local.keys():
		if not is_instance_valid(target):
			_local.erase(target)
			continue
		var st: Dictionary = _local[target]
		st["elapsed"] = float(st["elapsed"]) + real_delta
		if float(st["elapsed"]) >= float(st["len"]):
			target.call(&"set_frozen", false)
			_local.erase(target)
			_local_gate[target] = _now + local_regap_frames * FRAME


func _on_local_tree_exiting(target: Node) -> void:
	_local.erase(target)
	_local_gate.erase(target)


## #692: the Sand General (a DesertStatue, not in the "boss" group) gets the
## same finisher on his killing blow.
func _is_defeated_general(target: Node) -> bool:
	return target is DesertStatue and (target as DesertStatue).is_defeated_general()


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
