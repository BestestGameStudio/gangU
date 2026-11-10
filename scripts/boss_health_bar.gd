class_name BossHealthBar
extends Node2D
## #177: small world-space HP bar over the Mustache Warlord (visual only).
## Listens to the parent Enemy's health_changed; turns hot when the boss is
## enraged (<= 50% HP, matching EnemyBehaviorWarlord). Drawn in local space
## above the sprite; the boss root never rotates.

const WIDTH: float = 64.0
const HEIGHT: float = 5.0
const BG: Color = Color(0.06, 0.05, 0.09, 0.85)
const FILL: Color = Color(0.62, 0.9, 0.24)
const FILL_ENRAGED: Color = Color(1.0, 0.55, 0.15)
## #173: per-boss bar colours (defaults: the Warlord's green / hot orange).
@export var fill_color: Color = FILL
@export var fill_enraged_color: Color = FILL_ENRAGED
const LAG_COLOR: Color = Color(1.0, 1.0, 0.85, 0.8)
const LAG_RATE: float = 0.8 ## fraction of the bar per second the damage trail drains

var _ratio: float = 1.0
var _lag: float = 1.0

func _ready() -> void:
	var body: Node = get_parent()
	if body != null and body.has_signal("health_changed"):
		body.connect("health_changed", _on_health_changed)

func _on_health_changed(current: int, max_hp: int) -> void:
	_ratio = clampf(float(current) / float(maxi(max_hp, 1)), 0.0, 1.0)
	queue_redraw()

func _process(delta: float) -> void:
	if _lag > _ratio:
		_lag = maxf(_ratio, _lag - LAG_RATE * delta)
		queue_redraw()

func _draw() -> void:
	var origin := Vector2(-WIDTH * 0.5, 0.0)
	draw_rect(Rect2(origin - Vector2(1, 1), Vector2(WIDTH + 2, HEIGHT + 2)), BG)
	draw_rect(Rect2(origin, Vector2(WIDTH * _lag, HEIGHT)), LAG_COLOR)
	draw_rect(Rect2(origin, Vector2(WIDTH * _ratio, HEIGHT)), fill_enraged_color if _ratio <= 0.5 else fill_color)
