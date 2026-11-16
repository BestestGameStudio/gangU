extends Camera2D
class_name FollowCamera
## Follow camera: keeps the player in view with a smoothed follow - the
## camera trails the player and catches up instead of staying hard-locked
## (#21, requested by Daniel). Snap only on ready so the first frame is
## framed correctly.
## Lives in main.tscn (not player.tscn) to stay independent of the spell
## system's player.tscn changes (#3) and future scene-flow work (#7/#9).

@export var target_path: NodePath = ^"../Player"
## Follow stiffness in 1/seconds. Higher = snappier, lower = looser trail.
@export var follow_speed: float = 5.0

## #29: follow in _physics_process, not _process. The player moves on fixed
## physics ticks; sampling that step-moving target on variable render frames
## made the exponential catch-up oscillate visibly (measured +-2-5px on web).

@onready var target: Node2D = get_node_or_null(target_path)

## #678: the zoom the camera returns to after a boss stop; captured at ready
## so a boss beat always lands back on neutral, whatever the scene sets.
var _base_zoom := Vector2.ONE
## #687: seconds of boss-focus beat left (zoom-in + hold). While > 0 the
## follow lerp holds off so the camera sits on the fallen boss.
var _focus_left := 0.0
var _focus_tween: Tween = null

func _ready() -> void:
	make_current()
	_base_zoom = zoom
	if target:
		global_position = target.global_position

## #687: boss-kill cinematic (Mitra: "zoom in on the boss and stay on it for
## a good second or two before returning... play the death animation and
## zoom out after that"). Drives onto `point` while zooming hard to
## _base_zoom * amount with a fast ease-out attack, holds the frame there
## for hold_time seconds - the death animation plays zoomed - then eases the
## zoom back to neutral over out_time while the normal follow carries the
## camera back to the player. Always lands back on neutral zoom; a new focus
## restarts cleanly.
func boss_focus(point: Vector2, amount: float, in_time: float, hold_time: float, out_time: float) -> void:
	if _focus_tween != null and _focus_tween.is_running():
		_focus_tween.kill()
	if amount <= 0.0:
		return
	_focus_left = in_time + hold_time
	_focus_tween = create_tween()
	# #692: the beat runs in slow-mo; its times are real seconds.
	_focus_tween.set_ignore_time_scale(true)
	_focus_tween.set_parallel(true)
	# #692: a soft S-curve ramp (ease in AND out) so the pan and zoom glide
	# onto the boss instead of snapping.
	_focus_tween.tween_property(self, ^"zoom", _base_zoom * amount, in_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_focus_tween.tween_property(self, ^"global_position", point, in_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_focus_tween.set_parallel(false)
	_focus_tween.tween_interval(hold_time)
	_focus_tween.tween_property(self, ^"zoom", _base_zoom, out_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

func _physics_process(delta: float) -> void:
	if _focus_left > 0.0:
		_focus_left = maxf(_focus_left - delta / maxf(Engine.time_scale, 0.001), 0.0)
		return
	if target:
		# Frame-rate independent exponential smoothing toward the target.
		var weight := 1.0 - exp(-follow_speed * delta)
		global_position = global_position.lerp(target.global_position, weight)
