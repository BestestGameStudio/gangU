class_name WaterRain
extends Node2D
## #331 Water Ball splash Signature (Heavy Rain): a rain zone anchored where
## it was cast. Every spell.rain_interval seconds for spell.rain_duration
## seconds it drops a WaterSplash straight down at a random point inside
## spell.rain_radius; each drop deals the spell's damage within
## spell.splash_radius when it lands.

signal ended

const DROP_HEIGHT := 140.0
const DROP_FALL_TIME := 0.3
const FADE_TIME := 0.4

var spell: Spell
var source: Node2D
var rng := RandomNumberGenerator.new()

var _elapsed := 0.0
var _next_drop := 0.0
var drops := 0
var _ending := false

static func spawn(parent: Node, p_spell: Spell, p_source: Node2D, at: Vector2) -> WaterRain:
	var r := WaterRain.new()
	r.spell = p_spell
	r.source = p_source
	parent.add_child(r)
	r.global_position = at
	return r

func _ready() -> void:
	add_to_group(&"water_rain")
	rng.randomize()
	z_index = -1

func _physics_process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()
	if _ending:
		if _elapsed >= spell.rain_duration + FADE_TIME:
			ended.emit()
			queue_free()
		return
	if _elapsed >= spell.rain_duration:
		_ending = true
		return
	_next_drop -= delta
	while _next_drop <= 0.0:
		_next_drop += maxf(spell.rain_interval, 0.02)
		_drop()

func _drop() -> void:
	var a := rng.randf() * TAU
	var d := sqrt(rng.randf()) * spell.rain_radius
	var p := global_position + Vector2(cos(a), sin(a)) * d
	drops += 1
	WaterSplash.spawn(get_parent(), spell, source, p, p, DROP_HEIGHT, DROP_FALL_TIME)

func _draw() -> void:
	# Dark rain-cloud footprint with falling streaks, fading in and out.
	var alpha := clampf(_elapsed / 0.25, 0.0, 1.0)
	if _ending:
		alpha = clampf(1.0 - (_elapsed - spell.rain_duration) / FADE_TIME, 0.0, 1.0)
	var r := spell.rain_radius
	draw_circle(Vector2.ZERO, r, Color(0.15, 0.3, 0.55, 0.22 * alpha))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(0.55, 0.8, 1.0, 0.5 * alpha), 2.0)
	var streak_rng := RandomNumberGenerator.new()
	streak_rng.seed = 331
	for i in 18:
		var x := (streak_rng.randf() * 2.0 - 1.0) * r * 0.9
		var phase := fmod(_elapsed * 2.5 + streak_rng.randf(), 1.0)
		var y := -r + phase * r * 1.8
		if Vector2(x, y).length() > r:
			continue
		draw_line(Vector2(x, y - 10.0), Vector2(x - 2.0, y), Color(0.75, 0.9, 1.0, 0.6 * alpha), 1.5)
