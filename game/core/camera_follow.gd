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

## #678: the zoom the camera returns to after a boss-stop punch; captured at
## ready so a punch always lands back on neutral, whatever the scene sets.
var _base_zoom := Vector2.ONE
var _punch_tween: Tween = null

func _ready() -> void:
	make_current()
	_base_zoom = zoom
	if target:
		global_position = target.global_position

## #678: boss-stop zoom punch. Zooms to _base_zoom * amount with a fast
## attack, then eases back to neutral as play resumes. Composes with the
## follow offset (position lerp is untouched); a new punch restarts cleanly.
func zoom_punch(amount: float, in_time: float, out_time: float) -> void:
	if _punch_tween != null and _punch_tween.is_running():
		_punch_tween.kill()
	zoom = _base_zoom
	if amount <= 0.0:
		return
	_punch_tween = create_tween()
	_punch_tween.tween_property(self, ^"zoom", _base_zoom * amount, in_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_punch_tween.tween_property(self, ^"zoom", _base_zoom, out_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _physics_process(delta: float) -> void:
	if target:
		# Frame-rate independent exponential smoothing toward the target.
		var weight := 1.0 - exp(-follow_speed * delta)
		global_position = global_position.lerp(target.global_position, weight)
