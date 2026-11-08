class_name DamageNumber
extends Node2D
## Floating damage readout over an enemy. Visual only: rises, fades, frees
## itself. Spawned into the enemy's parent so a killing hit's number outlives
## the enemy.

const LIFETIME: float = 0.7
const RISE: float = 36.0
const FONT_SIZE: int = 16
const OUTLINE_SIZE: int = 5
const TEXT_COLOR: Color = Color(1.0, 0.93, 0.45)
const OUTLINE_COLOR: Color = Color(0.08, 0.06, 0.04)
const LABEL_WIDTH: float = 60.0
const LABEL_LIFT: float = 30.0
## Cycled per spawn so rapid hits fan out instead of stacking on one spot.
const X_OFFSETS: Array[float] = [0.0, 14.0, -14.0]

static var _spawned: int = 0

var _t: float = 0.0
var _start_y: float = 0.0

static func create(at: Vector2, amount: int) -> DamageNumber:
	var n: DamageNumber = DamageNumber.new()
	n.position = at
	n.z_index = 5
	var label: Label = Label.new()
	label.text = str(amount)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	label.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	label.size = Vector2(LABEL_WIDTH, FONT_SIZE + 8)
	var x_off: float = X_OFFSETS[_spawned % X_OFFSETS.size()]
	_spawned += 1
	label.position = Vector2(-LABEL_WIDTH * 0.5 + x_off, -LABEL_LIFT)
	n.add_child(label)
	return n

func _ready() -> void:
	_start_y = position.y

func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFETIME:
		queue_free()
		return
	var f: float = _t / LIFETIME
	position.y = _start_y - RISE * (1.0 - (1.0 - f) * (1.0 - f))
	modulate.a = 1.0 - f * f
