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

func _ready() -> void:
	super._ready()
	_shell = DamageModifier.reduction(shell_reduction)
	damage_modifiers.add(_shell)
	_body_shape = get_node("CollisionShape2D")
	_tip_shape = get_node("StingerShape")
	set_buried(true)

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
	var bypass := (aoe_bypasses_shell and hit.shape == HitContext.Shape.AREA) or hit.overlaps_circle(stinger_tip(), weakspot_radius)
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

func apply_calculated_damage(amount: int, crit_tier: int = 0) -> void:
	if not buried: super.apply_damage(amount,crit_tier)

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

## Same anatomy projection as scorpion_pose_source.py. The stinger triangle's
## actual tip, including idle/walk sway, hurt offset and held strike frame.
func stinger_tip() -> Vector2:
	if sprite == null: return global_position
	var anim := String(sprite.animation).get_slice("_", 0)
	var k := sprite.frame
	var count := sprite.sprite_frames.get_frame_count(sprite.animation)
	var phase := float(k) / maxf(count, 1) * TAU
	var sway := sin(phase) * (0.6 if anim == "idle" else 0.8 if anim == "walk" else 0.0)
	var strike: float = [0.0,0.18,1.0,0.32,0.0][mini(k,4)] if anim == "attack" else 0.0
	var x := 7.0 + sway
	var f: float = -3.0 + strike * 12.0
	var z: float = 23.0 - strike * 11.0
	if strike > 0.0:
		x = lerpf(x, 0.0, strike)
		f = lerpf(f, 22.0, strike)
		z = lerpf(z, 5.0, strike)
	f += 5.0 + strike * 2.0 - (1.0 if anim == "hurt" and k == 0 else 0.0)
	z -= 5.0
	var octant := int(round(facing.angle() / (PI/4.0))) & 7
	var angle := (PI/2.0) - float(octant)*PI/4.0
	var co := cos(angle)
	var si := sin(angle)
	var bob := 1.0 if anim == "idle" and k in [1,2] else 0.0
	var pixel := Vector2(round(32.0 + x*co + f*si), round(41.0 + (-x*si + f*co)*0.66 - z + bob))
	return sprite.to_global(pixel - Vector2(32,32))

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _tip_shape != null and not buried:
		_tip_shape.position = to_local(stinger_tip())

func _process(delta: float) -> void:
	super._process(delta)
	if _tip_shape != null and not buried:
		_tip_shape.position = to_local(stinger_tip())
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
