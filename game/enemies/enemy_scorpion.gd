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
var _pose_pixels: Dictionary = {}

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
	return Vector2(0,-16)

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

## Geometry follows the rendered suffix/frame, not player aim. Transition
## coordinates reproduce the same anatomy/drop/shake as the SpriteU generator.
func _tip_pixel() -> Vector2:
	var name := String(sprite.animation)
	var anim := name.get_slice("_",0)
	var suffix := name.get_slice("_",1)
	var di := ["s","se","e","ne","n","nw","w","sw"].find(suffix)
	if di < 0: return Vector2(INF,INF)
	var k := sprite.frame
	var transition := anim == "emerge" or anim == "bury"
	var transition_phase := 5-k if anim == "bury" else k
	if transition:
		if transition_phase == 0: return Vector2(INF,INF)
		if transition_phase == 5:
			anim = "idle"
			k = 0
	var count := sprite.sprite_frames.get_frame_count(sprite.animation)
	var phase := float(k)/maxf(count,1)*TAU
	var sway := sin(phase)*(0.6 if anim == "idle" else 0.8 if anim == "walk" else 0.0)
	var shake := 0.0
	var drop := 0.0
	var cutoff := 63.0
	if transition and transition_phase in [1,2,3,4]:
		sway = sin(float(transition_phase)/6.0*TAU)*0.8 + [0.0,-1.8,1.8,-1.2,0.5,0.0][transition_phase]
		shake = [0.0,-1.0,1.0,-1.0,1.0,0.0][transition_phase]
		drop = [0.0,13.0,7.0,2.0,0.0][transition_phase]
		cutoff = [0.0,44.0,47.0,52.0,61.0][transition_phase]
	var strike: float = [0.0,0.18,1.0,0.32,0.0][mini(k,4)] if anim == "attack" else 0.0
	var x := 7.0+sway
	var f: float = -3.0+strike*12.0
	var z: float = 23.0-strike*11.0
	if strike > 0.0:
		x = lerpf(x,0.0,strike)
		f = lerpf(f,22.0,strike)
		z = lerpf(z,5.0,strike)
	f += 5.0+strike*2.0-(1.0 if anim == "hurt" and k == 0 else 0.0)
	z -= 5.0
	var angle := float(di)*PI/4.0
	var co := cos(angle)
	var si := sin(angle)
	var bob := 1.0 if anim == "idle" and k in [1,2] else 0.0
	var pixel := Vector2(round(32.0+x*co+f*si+shake),round(41.0+(-x*si+f*co)*0.66-z+bob)+drop)
	return pixel if pixel.y <= cutoff else Vector2(INF,INF)

func stinger_exposed() -> bool:
	if buried or sprite == null: return false
	var key := "%s:%d" % [sprite.animation,sprite.frame]
	if not _pose_pixels.has(key):
		var pixel := _tip_pixel()
		var exposed := pixel.is_finite()
		if exposed:
			# A transition can occlude the projected tip with sand/debris.
			# Inspect the shipped frame once, not merely the mathematical rig.
			var image := sprite.sprite_frames.get_frame_texture(sprite.animation,sprite.frame).get_image()
			var color := image.get_pixelv(Vector2i(pixel))
			exposed = color.a > 0.0 and color.r < 0.68 and color.b > color.r
		_pose_pixels[key] = exposed
	return bool(_pose_pixels[key])

func stinger_tip() -> Vector2:
	var pixel := _tip_pixel() if sprite != null else Vector2(INF,INF)
	return sprite.to_global(pixel-Vector2(32,32)) if pixel.is_finite() else global_position

func _sync_tip_shape() -> void:
	if _tip_shape == null: return
	_tip_shape.set_deferred("disabled",not stinger_exposed())
	if not buried: _tip_shape.position = to_local(stinger_tip())

func _hold_grounded_stinger() -> void:
	if not is_stunned() or sprite == null: return
	if sprite.current_action() != &"attack" or sprite.frame != 2:
		play_action(&"attack",true)
		sprite.set_frame_and_progress(2,0.0)
	sprite.pause()

func stun(seconds: float) -> void:
	super.stun(seconds)
	_hold_grounded_stinger()
	_sync_tip_shape()

func _physics_process(delta: float) -> void:
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
