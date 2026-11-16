extends Node2D
## Original ruin props. Presentation only: no bodies, navigation, encounter
## state or world-clock changes. Warm pools stay outside the playable floor.
const BRAZIER := preload("res://assets/sprites/desert_brazier.png")
const PILLAR := preload("res://assets/sprites/desert_lantern_pillar.png")
var arena_radius := 0.0
var barrier_radius := 0.0
var _lights: Array[PointLight2D] = []
var _base_energy: Array[float] = []
var _time := 0.0
var _step := 0.0
var _clock: DayNightClock
var _glow: GradientTexture2D

func _ready() -> void:
	_clock = DayNightClock.find_clock(get_tree())
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.18, 0.5, 1.0])
	gradient.colors = PackedColorArray([Color(1,1,1,0.8), Color(1,1,1,0.58), Color(1,1,1,0.16), Color(1,1,1,0)])
	_glow = GradientTexture2D.new()
	_glow.gradient = gradient
	_glow.width = 256
	_glow.height = 256
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5,0.5)
	_glow.fill_to = Vector2(1,0.5)
	var frames := SpriteFrames.new()
	frames.set_animation_speed("default", 7.0)
	for i in 4:
		var frame := AtlasTexture.new()
		frame.atlas = BRAZIER
		frame.region = Rect2(i * 64, 0, 64, 80)
		frames.add_frame("default", frame)
	# Between the twelve statues, outside the fight boundary. Leave the
	# west entrance empty, with lantern pillars framing a broad clear path.
	for i in 12:
		var angle := -PI / 2.0 + TAU * (float(i) + 0.5) / 12.0
		if absf(angle_difference(angle, PI)) < 0.55:
			continue
		var at := Vector2.from_angle(angle) * maxf(arena_radius * 0.98, barrier_radius + 128.0)
		var sprite := AnimatedSprite2D.new()
		sprite.sprite_frames = frames
		sprite.position = at + Vector2(0,-32)
		sprite.play()
		sprite.frame = i % 4
		add_child(sprite)
		_light(at + Vector2(0,-45), 1.65, 0.84)
	for side in [-1.0, 1.0]:
		var at := Vector2(-arena_radius * 0.91, side * 132.0)
		var pillar := Sprite2D.new()
		pillar.texture = PILLAR
		pillar.position = at + Vector2(0,-52)
		add_child(pillar)
		_light(at + Vector2(0,-64), 1.32, 0.70)
	# Subtle pools under the scattered entrance slabs, not a bright line
	# that could be mistaken for the gold encounter barrier.
	for side in [-1.0, 1.0]:
		_light(Vector2(-arena_radius * 0.93, side * 68.0), 0.58, 0.17)

func _light(at: Vector2, spread: float, energy: float) -> void:
	var light := PointLight2D.new()
	light.position = at
	light.texture = _glow
	light.texture_scale = spread
	light.color = Color("ffc273")
	light.energy = energy
	light.shadow_enabled = false
	add_child(light)
	_lights.append(light)
	_base_energy.append(energy)

func _process(delta: float) -> void:
	_time += delta
	_step += delta
	if _step < 0.08:
		return
	_step = 0.0
	# One low-rate clock for all lamps; no new particles or shadow passes.
	var daylight := _clock.tint_color().r if is_instance_valid(_clock) else 1.0
	var strength := lerpf(1.0, 0.22, inverse_lerp(0.30, 1.0, daylight))
	for i in _lights.size():
		_lights[i].energy = _base_energy[i] * strength * (1.0 + 0.035 * sin(_time * 7.0 + float(i) * 2.4) + 0.018 * sin(_time * 13.0 + float(i)))
