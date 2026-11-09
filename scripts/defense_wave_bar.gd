class_name DefenseWaveBar
extends Control
## #369: top-center wave progress bar for DEFENSE missions (#337).
## One icon per wave - an enemy glyph for a regular wave, a skull for a boss
## wave (the #368 hook, DungeonObjective.boss_waves, stays empty until boss
## waves land). Clearing a wave fills the bar; a countdown centered under the
## bar shows when the next wave is about to spawn.
## Visible only while the mounted DungeonObjective is a DEFENSE objective.
## Driven by polling the objective every frame, so no signal wiring is needed
## and area swaps that free the objective simply hide the bar.

const BAR_WIDTH := 360.0
const BAR_HEIGHT := 24.0
const COUNTDOWN_TOP := 28.0
const ICON_R := 7.0
const TRACK_BG := Color(0.06, 0.05, 0.09, 0.85)
const TRACK_BORDER := Color(0.9, 0.85, 0.7, 0.9)
## Amber fill matches the HUD palette (#244).
const TRACK_FILL := Color(0.95, 0.75, 0.25, 0.9)
const ICON_DIM := Color(0.42, 0.38, 0.36, 0.9)
const ICON_LIT := Color(1.0, 0.55, 0.15, 1.0)
const SKULL_DIM := Color(0.55, 0.55, 0.6, 0.9)
const SKULL_LIT := Color(0.94, 0.94, 0.97, 1.0)

var _objective: DungeonObjective
var _countdown: Label

func _ready() -> void:
	custom_minimum_size = Vector2(BAR_WIDTH, COUNTDOWN_TOP + 18.0)
	_countdown = Label.new()
	_countdown.name = "Countdown"
	_countdown.position = Vector2(0, COUNTDOWN_TOP)
	_countdown.size = Vector2(BAR_WIDTH, 18.0)
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown.add_theme_font_size_override("font_size", 14)
	_countdown.add_theme_color_override("font_outline_color", Color.BLACK)
	_countdown.add_theme_constant_override("outline_size", 4)
	add_child(_countdown)
	visible = false

## The HUD mounts the discovered objective (DEFENSE only) or null on an area
## swap / for every other objective type.
func show_objective(objective: DungeonObjective) -> void:
	_objective = objective
	visible = objective != null
	queue_redraw()

func _process(_delta: float) -> void:
	if _objective == null or not is_instance_valid(_objective):
		visible = false
		return
	var remaining := _objective.next_wave_remaining()
	if remaining >= 0.0:
		_countdown.text = "Next wave in %ds" % int(ceili(remaining))
		_countdown.visible = true
	else:
		_countdown.visible = false
	queue_redraw()

## "skull" for a wave marked as a boss wave (#368 marker), else "enemy".
## Exposed for the test harness.
func icon_kind(wave: int) -> String:
	return "skull" if _objective != null and _objective.is_boss_wave(wave) else "enemy"

## Fraction of the bar filled (waves cleared / total). Exposed for tests.
func fill_fraction() -> float:
	if _objective == null or not is_instance_valid(_objective):
		return 0.0
	var p := _objective.progress()
	return clampf(float(p.x) / float(maxi(p.y, 1)), 0.0, 1.0)

func _draw() -> void:
	if _objective == null or not is_instance_valid(_objective):
		return
	var total := _objective.total_waves()
	if total <= 0:
		return
	var track := Rect2(Vector2.ZERO, Vector2(BAR_WIDTH, BAR_HEIGHT))
	draw_rect(track, TRACK_BG)
	var frac := fill_fraction()
	if frac > 0.0:
		draw_rect(Rect2(Vector2.ZERO, Vector2(BAR_WIDTH * frac, BAR_HEIGHT)), TRACK_FILL)
	draw_rect(track, TRACK_BORDER, false, 1.0)
	var cleared := _objective.progress().x
	var seg := BAR_WIDTH / total
	for wave in range(1, total + 1):
		var c := Vector2(seg * (wave - 0.5), BAR_HEIGHT * 0.5)
		if _objective.is_boss_wave(wave):
			_draw_skull(c, SKULL_LIT if wave <= cleared else SKULL_DIM)
		else:
			_draw_enemy(c, ICON_LIT if wave <= cleared else ICON_DIM)

## Regular wave: a little horned imp head.
func _draw_enemy(c: Vector2, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-ICON_R + 1, -4), c + Vector2(-ICON_R - 4, -ICON_R - 3), c + Vector2(-2, -ICON_R)]), color)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(ICON_R - 1, -4), c + Vector2(ICON_R + 4, -ICON_R - 3), c + Vector2(2, -ICON_R)]), color)
	draw_circle(c, ICON_R, color)
	draw_circle(c + Vector2(-2.5, -1), 1.4, Color.BLACK)
	draw_circle(c + Vector2(2.5, -1), 1.4, Color.BLACK)

## Boss wave (#368): a skull.
func _draw_skull(c: Vector2, color: Color) -> void:
	draw_circle(c + Vector2(0, -1), ICON_R, color)
	draw_rect(Rect2(c + Vector2(-4, 4), Vector2(8, 5)), color)
	draw_circle(c + Vector2(-2.5, -2), 1.8, Color.BLACK)
	draw_circle(c + Vector2(2.5, -2), 1.8, Color.BLACK)
	draw_rect(Rect2(c + Vector2(-1, 2), Vector2(2, 2)), Color.BLACK)
