class_name EnemyScorpion
extends Enemy
## #855: type-local concealment, shell query and pose-matched stinger geometry.
@export var shell_reduction := 0.8
@export var weakspot_radius := 12.0
## Isolated policy: all landed area hits bypass the shell.
@export var aoe_bypasses_shell := true
var buried := true
var facing := Vector2.DOWN
var _shell: DamageModifier
var _tip_shape: CollisionShape2D
var _body_shape: CollisionShape2D
var _trail: Array[Vector2] = []
var _trail_clock := 0.0
var _pre_stun_pose: Dictionary = {}

func _ready() -> void:
	super._ready()
	_shell = DamageModifier.reduction(shell_reduction)
	damage_modifiers.add(_shell)
	_body_shape = get_node("CollisionShape2D")
	_tip_shape = get_node("StingerShape")
	sprite.frame_changed.connect(_sync_tip_shape)
	sprite.animation_changed.connect(_sync_tip_shape)
	set_buried(true)

func stun_halo_position() -> Vector2:
	# Per-pose opaque top preserves a10px gap over the actual larger model.
	return super.stun_halo_position()

func is_combat_targetable() -> bool:
	return not buried and hp > 0

func set_buried(value: bool) -> void:
	buried = value
	if _body_shape != null:
		_body_shape.set_deferred("disabled", value)
	if _tip_shape != null:
		_tip_shape.set_deferred("disabled", value)
	if sprite != null:
		sprite.visible = not value
	var shadow := get_node_or_null("Shadow") as CanvasItem
	if shadow != null: shadow.visible = not value

func modifiers_for_hit(hit: HitContext) -> DamageModifiers:
	var bypass := (aoe_bypasses_shell and hit.shape == HitContext.Shape.AREA) or (stinger_exposed() and hit.overlaps_circle(stinger_tip(), weakspot_radius))
	if not bypass:
		return damage_modifiers
	var out := DamageModifiers.new()
	for m in damage_modifiers.items():
		if m != _shell: out.add(m)
	return out

func apply_damage(amount: int, crit_tier: int = 0) -> void:
	if buried: return # no mutation/receipt for an underground hit
	# Raw/unlocated calls (including a future DoT) never guess a weak spot.
	var result := DamageCalc.compute(float(amount),null,damage_modifiers,damage_rng)
	super.apply_damage(result.amount,crit_tier)

func apply_calculated_damage(amount: int, crit_tier: int = 0, hit: HitContext = null) -> void:
	if buried or hp <= 0: return
	var tip_hit := hit != null and hit.shape != HitContext.Shape.AREA and stinger_exposed() and hit.overlaps_circle(stinger_tip(),weakspot_radius)
	super.apply_damage(amount,crit_tier)
	if tip_hit and hp > 0 and _behavior is EnemyBehaviorScorpion:
		(_behavior as EnemyBehaviorScorpion).extend_stinger_stun()

func set_frozen(frozen: bool) -> void:
	super.set_frozen(frozen)
	if not freeze.is_frozen() and _behavior is EnemyBehaviorScorpion:
		var state := (_behavior as EnemyBehaviorScorpion).state
		if state in [EnemyBehaviorScorpion.State.MISS_STUN,EnemyBehaviorScorpion.State.STING_DASH]:
			sprite.set_frame_and_progress(2,0.0)
			sprite.pause()

func face_player(direction: Vector2) -> void:
	if direction.length_squared() > 0.001:
		facing = direction.normalized()
		if sprite != null: sprite.face_direction(facing)

## Generated source geometry follows the actual rendered suffix/frame, including
## shake, drop, collapse and transition occlusion. No nearest-pixel guessing.
const PoseGeometry := preload("res://game/enemies/scorpion_pose_geometry.gd")
func _tip_pose(animation: StringName, frame: int) -> Vector3:
	var frames: Array = PoseGeometry.POSES.get(animation,[])
	return frames[frame] if frame >= 0 and frame < frames.size() else Vector3(-1,-1,0)

func _tip_pixel() -> Vector2:
	return _tip_pixel_for(sprite.animation,sprite.frame)

func _tip_pixel_for(animation: StringName, frame: int) -> Vector2:
	var pose := _tip_pose(animation,frame)
	return Vector2(pose.x,pose.y) if pose.x >= 0.0 else Vector2(INF,INF)

func stinger_exposed() -> bool:
	return not buried and sprite != null and _tip_pose(sprite.animation,sprite.frame).z > 0.0

func stinger_tip() -> Vector2:
	var pixel := _tip_pixel() if sprite != null else Vector2(INF,INF)
	return sprite.to_global(pixel-Vector2(64,64)) if pixel.is_finite() else global_position

func _sync_tip_shape() -> void:
	if _tip_shape == null: return
	_tip_shape.set_deferred("disabled",not stinger_exposed())
	if not buried: _tip_shape.position = to_local(stinger_tip())

func _restore_stun_pose() -> void:
	if _pre_stun_pose.is_empty() or sprite == null: return
	sprite._action = _pre_stun_pose.action
	sprite._hold = _pre_stun_pose.hold
	sprite.animation = _pre_stun_pose.animation
	sprite.set_frame_and_progress(_pre_stun_pose.frame,_pre_stun_pose.progress)
	if _pre_stun_pose.playing: sprite.play()
	else: sprite.pause()
	_pre_stun_pose.clear()

func _hold_grounded_stinger() -> void:
	if sprite == null: return
	if not is_stunned():
		_restore_stun_pose()
		return
	if sprite.current_action() != &"attack" or sprite.frame != 2:
		play_action(&"attack",true)
		sprite.set_frame_and_progress(2,0.0)
	sprite.pause()

func stun(seconds: float) -> void:
	if seconds > 0.0 and stun_left <= 0.0 and sprite != null:
		_pre_stun_pose = {"action":sprite.current_action(),"hold":sprite._hold,
			"animation":sprite.animation,"frame":sprite.frame,
			"progress":sprite.frame_progress,"playing":sprite.is_playing()}
	super.stun(seconds)
	_hold_grounded_stinger()
	_sync_tip_shape()

func _physics_process(delta: float) -> void:
	# Restore before the first resumed AI step, so its new action wins.
	if not freeze.is_frozen() and stun_left > 0.0 and stun_left <= delta:
		_restore_stun_pose()
	else:
		_hold_grounded_stinger()
	super._physics_process(delta)
	_sync_tip_shape()

func _process(delta: float) -> void:
	_hold_grounded_stinger()
	super._process(delta)
	_sync_tip_shape()
	if freeze.is_frozen(): return
	if _behavior is EnemyBehaviorScorpion and (_behavior as EnemyBehaviorScorpion).state == EnemyBehaviorScorpion.State.BURROW_RUSH:
		_trail_clock += delta
		if _trail_clock >= 0.025:
			_trail_clock = 0.0
			_trail.append(global_position)
			if _trail.size() > 12: _trail.pop_front()
	elif not _trail.is_empty():
		_trail.pop_front()
	queue_redraw()

func _draw() -> void:
	for i in _trail.size():
		var p := to_local(_trail[i])
		var a := float(i+1)/float(_trail.size())
		draw_circle(p, 3.0+4.0*a, Color(0.73,0.59,0.37,0.5*a))
		draw_line(p+Vector2(-7,2),p+Vector2(7,2),Color(0.92,0.8,0.56,0.65*a),2.0)

## Warning covers the future grounded-tip sweep plus the existing24px
## target proximity, not a body-centered guess or the raised windup tip.
## Consumer is visual-only; locked aim and damage geometry remain unchanged.
func charge_warning() -> Dictionary:
	if buried or hp <= 0 or is_stunned() or not _behavior is EnemyBehaviorScorpion: return {}
	var b := _behavior as EnemyBehaviorScorpion
	if b.state != EnemyBehaviorScorpion.State.STING_WINDUP: return {}
	var tip := sprite.to_global(_tip_pixel_for(sprite._variant(&"attack"),2)-Vector2(64,64))
	return {"origin":tip-b._aim*24.0,"direction":b._aim,
		"length":b.dash_distance+48.0,"width":48.0,
		"progress":clampf(b._time/b.sting_windup_duration(),0.0,1.0)}
