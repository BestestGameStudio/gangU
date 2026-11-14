class_name DesertStatue
extends Enemy

const BODY_RADIUS := 24.0
const STATIONARY_FRAMES: SpriteFrames = preload("res://assets/sprites/stationary_statues_frames.tres")
# Frame 7 is the first source pose after the spear leaves the hand.
const THROW_RELEASE_TIME := 1.17
const THROW_DURATION := 2.14
const STATUE_SHEET: Texture2D = preload("res://assets/sprites/sandstatues.png")

var arena: Node2D
var possessed := false
var broken := false
var destroyed_once := false
var absorbed := false
var flash := 0.0
var _sprite: Sprite2D
var _stationary: AnimatedSprite2D
var _hit_pending := false
var _ring_position := Vector2.ZERO

func throw_windup(cycle: float) -> float:
	return THROW_RELEASE_TIME / _throw_speed(cycle)

func _throw_speed(cycle: float) -> float:
	return THROW_DURATION / minf(THROW_DURATION, maxf(cycle * 0.9, 0.1))

func begin_throw(fires_in: float, cycle: float, direction: Vector2) -> void:
	if broken or absorbed or _phase_two():
		return
	_stationary.play(_throw_animation(direction), _throw_speed(cycle))
	# Account for the physics tick crossing the cue time. Release is still
	# controlled by the arena lane, never by an animation callback.
	_seek_animation(maxf(throw_windup(cycle) - fires_in, 0.0) * _throw_speed(cycle))

func play_hit() -> void:
	if broken or absorbed or _phase_two():
		return
	if String(_stationary.animation).begins_with("throw_") and _stationary.is_playing():
		_hit_pending = true
	else:
		_stationary.play(&"hurt", 1.0)

func play_break() -> void:
	_hit_pending = false
	_stationary.play(&"death", 1.0)

func rebuild() -> void:
	# A returning possession star can revive a statue after rubble was pulled in.
	position = _ring_position
	scale = Vector2.ONE
	absorbed = false
	_hit_pending = false
	_stationary.play(&"idle", 1.0)

func _phase_two() -> bool:
	return arena is DesertStatueArena and (arena as DesertStatueArena).state == DesertStatueArena.State.PHASE_TWO

# The supplied art is directional; pick the pose matching the actual spear
# path so any aim (player, statue or centre) reads correctly.
func _throw_animation(direction: Vector2) -> StringName:
	if absf(direction.x) > absf(direction.y):
		return &"throw_right" if direction.x > 0 else &"throw_left"
	return &"throw_down" if direction.y >= 0 else &"throw_up"

func _seek_animation(seconds: float) -> void:
	for i in STATIONARY_FRAMES.get_frame_count(_stationary.animation):
		var duration := STATIONARY_FRAMES.get_frame_duration(_stationary.animation, i)
		if seconds < duration:
			_stationary.set_frame_and_progress(i, seconds / duration)
			return
		seconds -= duration

func _animation_finished() -> void:
	if broken:
		return # Hold the final rubble pose until absorption.
	if _hit_pending:
		_hit_pending = false
		_stationary.play(&"hurt", 1.0)
	else:
		_stationary.play(&"idle", 1.0)

func _ready() -> void:
	collision_layer = PhysicsLayers.ENEMY
	collision_mask = 0
	add_to_group(&"enemies")
	_sprite = Sprite2D.new()
	_sprite.name = "StatueSprite"
	_sprite.texture = STATUE_SHEET
	_sprite.hframes = 4
	_sprite.vframes = 2
	_sprite.scale = Vector2(1.22, 1.22)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.z_index = -1
	add_child(_sprite)
	_ring_position = position
	_stationary = AnimatedSprite2D.new()
	_stationary.name = "StationaryStatueSprite"
	_stationary.sprite_frames = STATIONARY_FRAMES
	_stationary.scale = Vector2(1.22, 1.22)
	_stationary.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_stationary.z_index = -1
	_stationary.animation_finished.connect(_animation_finished)
	add_child(_stationary)
	_stationary.play(&"idle")
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = BODY_RADIUS
	shape.shape = circle
	add_child(shape)

func apply_damage_from(amount: int, projectile: Node, crit_tier: int = 0) -> void:
	var source: Variant = projectile.get(&"source")
	if is_instance_valid(source) and (source is Player or source is Summon):
		apply_damage(amount, crit_tier)

func apply_damage(amount: int, crit_tier: int = 0) -> void:
	if not broken:
		arena.damage_statue(self, amount, crit_tier)

func _process(delta: float) -> void:
	flash = maxf(flash - delta, 0.0)
	var phase_two := _phase_two()
	_sprite.visible = phase_two and not broken and not absorbed
	_stationary.visible = not phase_two and not absorbed
	if phase_two:
		_update_sprite()
		_sprite.modulate = Color(1.6,1.6,1.6,1.0) if flash > 0.0 else Color.WHITE
	else:
		# Retain a distinct possessed host without replacing the supplied art.
		_stationary.modulate = Color(1.35,1.1,0.7) if possessed else Color.WHITE
	# Finish the supplied crumble before the original visual-only pull inward.
	if broken and not absorbed and not _stationary.is_playing():
		position = position.move_toward(Vector2.ZERO, delta * 250.0)
		scale = scale.move_toward(Vector2.ONE * 0.12, delta * 0.9)
		if position.length() < 8.0:
			absorbed = true
	queue_redraw()

func _draw() -> void:
	if absorbed:
		return
	draw_ellipse_shadow()
	if broken:
		return # The supplied death animation supplies the rubble.
	if arena is DesertStatueArena and (arena as DesertStatueArena).state == DesertStatueArena.State.PHASE_TWO and (arena as DesertStatueArena).possessed == self:
		_draw_sand_shield()
	if hp < max_hp:
		draw_rect(Rect2(-22, 33, 44, 4), Color("3d3432"))
		draw_rect(Rect2(-22, 33, 44.0 * hp / max_hp, 4), Color("ba8161"))

func _update_sprite() -> void:
	if not is_instance_valid(_sprite):
		return
	var direction := Vector2.DOWN
	if arena is DesertStatueArena and is_instance_valid((arena as DesertStatueArena).player):
		direction = (arena as DesertStatueArena).player.global_position-global_position
	if direction.is_zero_approx():
		direction = Vector2.DOWN
	var angle := direction.angle()
	var frame := 0
	if angle >= -PI*0.25 and angle < PI*0.25:
		frame = 1 # right
	elif angle >= PI*0.25 and angle < PI*0.75:
		frame = 0 # toward
	elif angle >= -PI*0.75 and angle < -PI*0.25:
		frame = 3 # away
	else:
		frame = 2 # left
	_sprite.frame_coords = Vector2i(frame, 1 if possessed else 0)
	# Turn by switching to the closest cardinal pose. Keep the pixel art upright.
	_sprite.rotation = 0.0

func _draw_sand_shield() -> void:
	var general_arena := arena as DesertStatueArena
	if general_arena._phase_two_attack_index != 4:
		return
	var facing := general_arena._phase_two_bash_direction
	draw_set_transform(facing*34.0+Vector2(0,8), facing.angle(), Vector2.ONE)
	var shield := PackedVector2Array([Vector2(-15,-20),Vector2(8,-17),Vector2(20,-9),Vector2(19,10),Vector2(8,24),Vector2(-8,24),Vector2(-19,10),Vector2(-20,-9)])
	draw_colored_polygon(shield,Color("b86b35"))
	var shield_outline := PackedVector2Array([Vector2(-15,-20),Vector2(8,-17),Vector2(20,-9),Vector2(19,10),Vector2(8,24),Vector2(-8,24),Vector2(-19,10),Vector2(-20,-9),Vector2(-15,-20)])
	draw_polyline(shield_outline,Color("ffe3a0"),3.0,true)
	draw_line(Vector2(0,-12),Vector2(0,17),Color("f2c76f"),3.0,true)
	draw_set_transform(Vector2.ZERO)

func draw_ellipse_shadow() -> void:
	draw_set_transform(Vector2(0, 24), 0, Vector2(1, 0.35))
	draw_circle(Vector2.ZERO, 34, Color(0.22,0.16,0.1,0.24))
	draw_set_transform(Vector2.ZERO)

func _physics_process(_delta: float) -> void:
	velocity = Vector2.ZERO

func knockback(_push: Vector2) -> void:
	pass
