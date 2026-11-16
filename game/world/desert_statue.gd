class_name DesertStatue
extends Enemy

const BODY_RADIUS := 24.0
const STATIONARY_FRAMES: SpriteFrames = preload("res://assets/sprites/stationary_statues_frames.tres")
# Frame 7 is the first source pose after the spear leaves the hand.
const THROW_RELEASE_TIME := 1.17
const THROW_DURATION := 2.14
const GENERAL_FRAMES: SpriteFrames = preload("res://assets/sprites/roman_general_frames.tres")
# Visual-only sampling of the arena clock. Damage, projectiles and movement
# remain owned by DesertStatueArena, never by animation callbacks.
const GENERAL_MOVES := ["projectile", "triple_slash", "charged_slash", "ground_slam", "shield_bash", "spear_throw", "shield_plant"]
const GENERAL_IMPACT_FRAMES := [[7], [4, 7, 10], [8], [8], [5], [7], [4]]
const GENERAL_IMPACT_TIMES := [[0.0], [0.22, 0.78, 1.34], [0.12], [0.4], [0.0], [0.0], [0.0]]

var arena: Node2D
var possessed := false
var broken := false
var destroyed_once := false
var absorbed := false
var flash := 0.0
var _sprite: AnimatedSprite2D
var _general_facing := "front"
var _death_time := -1.0
var _general_mirror := false
var _general_last_position := Vector2.ZERO
var _general_locomotion_time := 0.0
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
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "RomanGeneralSprite"
	_sprite.sprite_frames = GENERAL_FRAMES
	_sprite.scale = Vector2(2.0, 2.0)
	# Native feet are at y=55. Keep them at the existing ground/shadow y=24.
	_sprite.position.y = -22.0
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.z_index = -1
	add_child(_sprite)
	_general_last_position = position
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
		_sprite.modulate = Color(1.6,1.6,1.6,1.0) if flash > 0.0 else Color.WHITE
		_update_sprite(delta)
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
	if hp < max_hp and (not _phase_two() or (arena as DesertStatueArena).general_height <= 120.0):
		draw_rect(Rect2(-22, 33, 44, 4), Color("3d3432"))
		draw_rect(Rect2(-22, 33, 44.0 * hp / max_hp, 4), Color("ba8161"))

func _general_direction(direction: Vector2) -> void:
	if direction.is_zero_approx():
		return
	_general_mirror = false
	if absf(direction.x) > absf(direction.y):
		_general_facing = "right"
		_general_mirror = direction.x < 0.0
	else:
		_general_facing = "front" if direction.y >= 0.0 else "back"

func _general_frame_start(anim: StringName, index: int) -> float:
	var seconds := 0.0
	for i in index:
		seconds += GENERAL_FRAMES.get_frame_duration(anim, i)
	return seconds

func _sample_general(anim: StringName, seconds: float) -> void:
	_sprite.animation = anim
	_sprite.flip_h = _general_mirror
	for i in GENERAL_FRAMES.get_frame_count(anim):
		var duration := GENERAL_FRAMES.get_frame_duration(anim, i)
		if seconds < duration:
			_sprite.set_frame_and_progress(i, clampf(seconds / duration, 0.0, 1.0))
			return
		seconds -= duration
	_sprite.set_frame_and_progress(GENERAL_FRAMES.get_frame_count(anim)-1, 1.0)

func _update_sprite(delta: float) -> void:
	var general_arena := arena as DesertStatueArena
	var movement := position-_general_last_position
	_general_last_position = position
	if not is_instance_valid(general_arena):
		return
	var attack := general_arena._phase_two_attack_index
	var clock := general_arena._phase_two_attack_time
	_sprite.position.y = -22.0-general_arena.general_height
	_sprite.z_index = 100 if general_arena.general_height > 0.0 else -1
	if is_instance_valid(general_arena.player):
		# Follow aim during windup, then keep it locked through the strike.
		# Triple slash retargets each dash in the arena and turns with travel.
		if clock < 0.0 or attack >= GENERAL_MOVES.size() or not general_arena._phase_two_locked:
			_general_direction(general_arena._phase_two_direction if clock >= 0.0 else general_arena.player.global_position-global_position)
		elif attack == 1 and movement.length_squared() > 0.001:
			_general_direction(movement)
	if general_arena.hp <= 0:
		# The death art carries the dim: play it once and hold the last frame.
		if _death_time < 0.0:
			_death_time = 0.0
		_sample_general(StringName("death_"+_general_facing), _death_time)
		_death_time += delta
		return
	_death_time = -1.0
	if clock < 0.0 or attack >= GENERAL_MOVES.size():
		_general_locomotion_time += delta
		var move := "idle"
		if movement.length() > delta*10.0:
			move = "run" if movement.length() > delta*220.0 else "walk"
		var anim := StringName(move+"_"+_general_facing)
		var duration := _general_frame_start(anim, GENERAL_FRAMES.get_frame_count(anim))
		_sample_general(anim, fmod(_general_locomotion_time, duration))
		return
	_general_locomotion_time = 0.0
	var anim := StringName(GENERAL_MOVES[attack]+"_"+_general_facing)
	var windup: float = general_arena.MOVE_WINDUP[attack]
	# Piecewise map source impact poses to the existing gameplay cues. The
	# original slower GIF wind-down must not delay the next real attack.
	if attack == 3:
		# Source key poses: crouch, extended takeoff, tucked air, landing.
		var times := [0.0,0.25,0.6,windup+0.18,windup+0.4,windup+general_arena.MOVE_RELEASE[3]]
		var frames := [0,3,5,7,8,GENERAL_FRAMES.get_frame_count(anim)-1]
		for i in range(1,times.size()):
			if clock <= times[i]:
				var fraction := clampf(inverse_lerp(times[i-1],times[i],clock),0.0,1.0)
				_sample_general(anim,lerpf(_general_frame_start(anim,frames[i-1]),_general_frame_start(anim,frames[i]),fraction))
				return
	var target_times: Array[float] = [0.0]
	var source_times: Array[float] = [_general_frame_start(anim, 1)]
	for cue in GENERAL_IMPACT_FRAMES[attack].size():
		target_times.append(windup+GENERAL_IMPACT_TIMES[attack][cue])
		source_times.append(_general_frame_start(anim, GENERAL_IMPACT_FRAMES[attack][cue]))
	target_times.append(windup+general_arena.MOVE_RELEASE[attack])
	source_times.append(_general_frame_start(anim, GENERAL_FRAMES.get_frame_count(anim))-0.001)
	for i in range(1, target_times.size()):
		if clock <= target_times[i]:
			var progress := inverse_lerp(target_times[i-1], target_times[i], clock)
			_sample_general(anim, lerpf(source_times[i-1], source_times[i], clampf(progress, 0.0, 1.0)))
			return
	_sample_general(anim, source_times[-1])

func draw_ellipse_shadow() -> void:
	if _phase_two() and (arena as DesertStatueArena).general_height > 120.0:
		return
	draw_set_transform(Vector2(0, 24), 0, Vector2(1, 0.35))
	draw_circle(Vector2.ZERO, 34, Color(0.22,0.16,0.1,0.24))
	draw_set_transform(Vector2.ZERO)

func _physics_process(_delta: float) -> void:
	velocity = Vector2.ZERO

func knockback(_push: Vector2) -> void:
	pass
