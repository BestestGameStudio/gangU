class_name SpiritMeter
extends Node2D
## gangU #460: spirit bar + hold-to-heal.
##
## The player has no other way to heal mid-run, so spirit builds up from the
## player's own LANDED hits on enemies and is spent on a channelled heal:
##   - Every OnHit.hit_landed event whose attacker is the owning Player and
##     whose target is an Enemy adds spirit_per_hit. Refused hits (dead
##     targets, iframes) never emit, so they never fill the bar. Hits on
##     containers/cores, summon hits and hits taken by the player do not count.
##   - With the bar FULL, holding H for channel_time heals heal_fraction of
##     max HP (rounded up) and empties the bar. Releasing H early cancels the
##     channel and keeps the spirit. The channel will not start at full HP or
##     while dead, and death cancels a running channel.
## The numbers are provisional tunings (the issue only fixed the 20% heal):
## 25 hits fill the bar, and the hold lasts 1 second.
##
## Mounted as a child of Player (game/player/player.tscn); the HUD finds it by
## name. Draws a progress ring around the player while channelling.

signal spirit_changed(current: float, max_spirit: float)
signal channel_started()
## progress is 0..1 of channel_time.
signal channel_progress(progress: float)
## completed is true when the heal landed, false when it was cancelled.
signal channel_ended(completed: bool)
signal healed(amount: int)

const HEAL_ACTION := &"heal"
const HEAL_KEY := KEY_H

@export var max_spirit: float = 100.0
@export var spirit_per_hit: float = 4.0
@export_range(0.0, 1.0) var heal_fraction: float = 0.2
@export var channel_time: float = 1.0

const RING_RADIUS := 30.0
const RING_COLOR := Color(0.55, 1.0, 0.75, 0.9)
const RING_TRACK := Color(0.1, 0.2, 0.15, 0.5)

var spirit: float = 0.0
var _channel_left := 0.0
var _channelling := false
var _player: Player


func _ready() -> void:
	_player = get_parent() as Player
	if _player == null:
		push_warning("SpiritMeter: parent is not a Player; meter inert.")
	if not InputMap.has_action(HEAL_ACTION):
		InputMap.add_action(HEAL_ACTION)
		var ev := InputEventKey.new()
		ev.physical_keycode = HEAL_KEY
		InputMap.action_add_event(HEAL_ACTION, ev)
	OnHit.bus().hit_landed.connect(_on_hit_landed)
	z_index = 5


func _on_hit_landed(e: HitEvent) -> void:
	if _player == null or e.attacker != _player or not (e.target is Enemy):
		return
	add_spirit(spirit_per_hit)


## Adds spirit, clamped to max_spirit. Emits spirit_changed only on change.
func add_spirit(amount: float) -> void:
	if amount <= 0.0:
		return
	var before := spirit
	spirit = minf(spirit + amount, max_spirit)
	if spirit != before:
		spirit_changed.emit(spirit, max_spirit)


func is_full() -> bool:
	return spirit >= max_spirit


func is_channelling() -> bool:
	return _channelling


## 0..1 of the current channel (0 when not channelling).
func channel_fraction() -> float:
	if not _channelling or channel_time <= 0.0:
		return 0.0
	return clampf(1.0 - _channel_left / channel_time, 0.0, 1.0)


## HP the heal restores right now: heal_fraction of max HP, rounded up.
func heal_amount() -> int:
	if _player == null:
		return 0
	return maxi(ceili(_player.max_hp * heal_fraction), 1)


## True when a channel may start: full bar, alive and missing HP.
func can_heal() -> bool:
	return _player != null and is_full() and _player.hp > 0 and _player.hp < _player.max_hp


func _physics_process(delta: float) -> void:
	tick_channel(delta, Input.is_action_pressed(HEAL_ACTION))


## Advance the hold-to-heal channel. `held` is whether H is down this frame.
## Public so harnesses can step it deterministically.
func tick_channel(delta: float, held: bool) -> void:
	if _channelling:
		if not held or _player == null or _player.hp <= 0:
			_end_channel(false)
			return
		_channel_left = maxf(_channel_left - delta, 0.0)
		channel_progress.emit(channel_fraction())
		queue_redraw()
		if _channel_left == 0.0:
			_finish_heal()
		return
	if held and can_heal():
		_channelling = true
		_channel_left = channel_time
		channel_started.emit()
		channel_progress.emit(0.0)
		queue_redraw()
		if channel_time <= 0.0:
			_finish_heal()


func _finish_heal() -> void:
	var amount := heal_amount()
	_player.heal(amount)
	spirit = 0.0
	spirit_changed.emit(spirit, max_spirit)
	healed.emit(amount)
	_end_channel(true)


func _end_channel(completed: bool) -> void:
	_channelling = false
	_channel_left = 0.0
	queue_redraw()
	channel_ended.emit(completed)


func _process(_delta: float) -> void:
	# The player node rotates with aim; keep the ring's start point fixed.
	global_rotation = 0.0


func _draw() -> void:
	if not _channelling:
		return
	draw_arc(Vector2.ZERO, RING_RADIUS, 0.0, TAU, 48, RING_TRACK, 4.0, true)
	var frac := channel_fraction()
	if frac > 0.0:
		draw_arc(Vector2.ZERO, RING_RADIUS, -PI / 2.0, -PI / 2.0 + TAU * frac, 48, RING_COLOR, 4.0, true)
