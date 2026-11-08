class_name BossHead
extends Enemy
## #173: "Head" boss for the RED-gate room (DungeonB), built from the
## user-supplied reference sheet (issue #173 image, sliced to
## assets/sprites/boss_head.png - see assets/sprites/SOURCE.md).
##
## Inherits the Enemy HP/died/reward contract (D7): apply_damage() stays the
## single HP mutation entry, died() fires exactly once at HP 0. The boss
## overrides the damage path only to route HP 0 through the death ANIMATION
## before queue_free - died still emits at the moment HP reaches 0, so the
## DungeonObjective ELIMINATION seam completes exactly like any enemy kill.
##
## Attacks follow the reference sheet (chosen tunings, NOT image facts):
## - PROJECTILE: at range, a telegraphed volley of VOLLEY_COUNT red slashes
##   (attack_projectile anim; bolts are scenes/boss_projectile.tscn).
## - AOE PULSE: up close, a telegraph ring grows over AOE_TELEGRAPH seconds
##   (reference AOE ring, engine-drawn from the sheet's VFX circle), then the
##   pulse damages the player if still inside AOE_RADIUS.
## - HURT plays on hits taken outside attacks; STUN triggers after
##   STUN_DAMAGE_ACCUMULATED damage since the last stun (vulnerable window);
##   DEATH plays the sheet's 10-frame crumble before despawn.
## All numbers below are CHOSEN gameplay tunings (baseline: plain Enemy is
## 30hp/110speed/10dmg; player 100hp), exported for easy adjustment.

signal boss_attack_started(kind: StringName)

## Chosen tuning: ~4x a plain enemy's 30 HP for a first boss fight.
const BOSS_MAX_HP := 120
## Chosen tuning: slower than a plain enemy (110) - heavy menace, not swarm.
const BOSS_SPEED := 70.0
const BOSS_CONTACT_DAMAGE := 15
const BOSS_CONTACT_RANGE := 56.0
## Chosen tuning: attack cadence and ranges.
const ATTACK_COOLDOWN := 2.2
const AOE_TRIGGER_RANGE := 170.0
const VOLLEY_COUNT := 3
const VOLLEY_SPREAD_DEG := 14.0
const BOLT_SPEED := 260.0
const BOLT_DAMAGE := 10
const BOLT_RANGE := 720.0
const PROJECTILE_WINDUP := 0.55
## Chosen tuning: AOE pulse (telegraph duration is the dodge window).
const AOE_TELEGRAPH := 0.9
const AOE_RADIUS := 150.0
const AOE_DAMAGE := 20
## Chosen tuning: stun window after taking this much damage since last stun.
const STUN_DAMAGE_ACCUMULATED := 40
const STUN_DURATION := 1.5
const Hurt_TIME := 0.3

enum State { CHASE, WINDUP_PROJECTILE, WINDUP_AOE, RECOVER, STUNNED, DYING }

var _state: int = State.CHASE
var _state_t: float = 0.0
var _attack_cd: float = 1.2 ## grace before the first attack
var _stun_accum: float = 0.0
var _facing: StringName = &"down"
var _hurt_t: float = 0.0
var _ring: Sprite2D = null
var _volley_left: int = 0
var _volley_t: float = 0.0
var _contact_timer: float = 0.0

const BossProjectileScene := preload("res://scenes/boss_projectile.tscn")
const RING_REGION := Rect2(192, 832, 96, 64) ## vfx circle in boss_head.png

@onready var sprite: AnimatedSprite2D = $BossSprite

func _ready() -> void:
	# Production explicit wiring (D6): the ELIMINATION seam adds the boss as a
	# child of the area (Main/DungeonB/BossHead), so ../../Player resolves the
	# shared production Player, which is in no group. Tests may still set
	# player_path or use the "player" group fallback in Enemy._ready.
	if player_path == NodePath(""):
		player_path = NodePath("../../Player")
	max_hp = BOSS_MAX_HP
	speed = BOSS_SPEED
	contact_damage = BOSS_CONTACT_DAMAGE
	contact_range = BOSS_CONTACT_RANGE
	super._ready()
	add_to_group("boss")

func _play(anim: StringName) -> void:
	if sprite.animation != anim:
		sprite.play(anim)

func _face(dir: Vector2) -> void:
	# Same dominant-axis 4-way facing convention as the wizard (#137).
	if dir == Vector2.ZERO:
		return
	if absf(dir.x) > absf(dir.y):
		_facing = &"right" if dir.x > 0.0 else &"left"
	else:
		_facing = &"down" if dir.y > 0.0 else &"up"

func _live_player() -> Player:
	if _player != null and is_instance_valid(_player) and _player.hp > 0:
		return _player
	return null

func _physics_process(delta: float) -> void:
	if _state == State.DYING:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	var p := _live_player()
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_hurt_t = maxf(0.0, _hurt_t - delta)
	_contact_timer = maxf(0.0, _contact_timer - delta)
	_state_t += delta
	match _state:
		State.STUNNED:
			velocity = Vector2.ZERO
			move_and_slide()
			_play(&"stun")
			if _state_t >= STUN_DURATION:
				_enter_chase()
			return
		State.WINDUP_PROJECTILE:
			velocity = Vector2.ZERO
			move_and_slide()
			_volley_t -= delta
			if _volley_left > 0 and _state_t >= PROJECTILE_WINDUP and _volley_t <= 0.0:
				_fire_bolt(p)
				_volley_left -= 1
				_volley_t = 0.12
			if _volley_left <= 0 and _state_t >= PROJECTILE_WINDUP + 0.45:
				_enter_recover(0.35)
			return
		State.WINDUP_AOE:
			velocity = Vector2.ZERO
			move_and_slide()
			var k := clampf(_state_t / AOE_TELEGRAPH, 0.0, 1.0)
			if _ring != null:
				_ring.scale = Vector2.ONE * (0.2 + k * (AOE_RADIUS * 2.0 / 96.0))
				_ring.modulate.a = 0.35 + 0.55 * k
			if _state_t >= AOE_TELEGRAPH:
				_pulse(p)
				_enter_recover(0.5)
			return
		State.RECOVER:
			velocity = Vector2.ZERO
			move_and_slide()
			if _state_t >= 0.5:
				_enter_chase()
			return
	# CHASE
	if p == null:
		velocity = Vector2.ZERO
		move_and_slide()
		_play(&"idle")
		return
	var to_player: Vector2 = p.global_position - global_position
	var dist := to_player.length()
	_face(to_player)
	if _attack_cd <= 0.0:
		if dist <= AOE_TRIGGER_RANGE:
			_start_aoe()
			return
		_start_volley(p)
		return
	if dist > contact_range * 0.7:
		velocity = to_player.normalized() * speed
		_play(&"hurt" if _hurt_t > 0.0 else StringName("move_" + String(_facing)))
	else:
		velocity = Vector2.ZERO
		_play(&"hurt" if _hurt_t > 0.0 else StringName("idle"))
	move_and_slide()
	# contact damage (same contract as the chase/contact behavior)
	if dist <= contact_range and _contact_ok():
		p.apply_damage(contact_damage)
		_contact_timer_reset()

func _contact_ok() -> bool:
	if _contact_timer > 0.0:
		return false
	return true
func _contact_timer_reset() -> void:
	_contact_timer = contact_cooldown

func _enter_chase() -> void:
	_state = State.CHASE
	_state_t = 0.0

func _enter_recover(t: float) -> void:
	_state = State.RECOVER
	_state_t = 0.0

func _start_volley(p: Player) -> void:
	_state = State.WINDUP_PROJECTILE
	_state_t = 0.0
	_volley_left = VOLLEY_COUNT
	_volley_t = 0.0
	_attack_cd = ATTACK_COOLDOWN
	if p != null:
		_face(p.global_position - global_position)
	_play(&"attack_projectile")
	boss_attack_started.emit(&"projectile")

func _fire_bolt(p: Player) -> void:
	if p == null:
		return
	var base := (p.global_position - global_position).angle()
	var idx := VOLLEY_COUNT - _volley_left
	var off := deg_to_rad(VOLLEY_SPREAD_DEG) * (idx - (VOLLEY_COUNT - 1) / 2.0)
	var bolt := BossProjectileScene.instantiate()
	bolt.setup(Vector2.from_angle(base + off), BOLT_SPEED, BOLT_DAMAGE, BOLT_RANGE, self)
	bolt.global_position = global_position + Vector2.from_angle(base + off) * 34.0
	get_parent().call_deferred("add_child", bolt)

func _start_aoe() -> void:
	_state = State.WINDUP_AOE
	_state_t = 0.0
	_attack_cd = ATTACK_COOLDOWN
	_play(&"attack_aoe")
	_ring = Sprite2D.new()
	_ring.texture = AtlasTexture.new()
	(_ring.texture as AtlasTexture).atlas = sprite.sprite_frames.get_frame_texture(&"idle", 0).atlas
	(_ring.texture as AtlasTexture).region = RING_REGION
	_ring.z_index = -1
	_ring.modulate = Color(1.0, 0.3, 0.3, 0.4)
	add_child(_ring)
	boss_attack_started.emit(&"aoe_pulse")

func _pulse(p: Player) -> void:
	if _ring != null:
		_ring.queue_free()
		_ring = null
	if p != null and global_position.distance_to(p.global_position) <= AOE_RADIUS:
		p.apply_damage(AOE_DAMAGE)

## Enemy contract override: same single entry point (D7), same died-once at
## HP 0, but the despawn waits for the death animation. Flash/spark/drop
## behavior mirrors enemy.gd; the sheet's crumble replaces the code burst.
func apply_damage(amount: int) -> void:
	if hp <= 0:
		return
	hp = clampi(hp - amount, 0, max_hp)
	health_changed.emit(hp, max_hp)
	if hp == 0:
		_die()
		return
	_hurt_t = Hurt_TIME
	_stun_accum += amount
	if _stun_accum >= STUN_DAMAGE_ACCUMULATED and _state != State.STUNNED:
		_stun_accum = 0.0
		_interrupt_to_stun()
	if _state == State.CHASE:
		_play(&"hurt")
	CombatEffects.hit_spark(get_parent(), global_position)
	modulate = Color(1.6, 1.6, 1.6)
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color.WHITE, 0.15)

func _interrupt_to_stun() -> void:
	if _ring != null:
		_ring.queue_free()
		_ring = null
	_volley_left = 0
	_state = State.STUNNED
	_state_t = 0.0
	_play(&"stun")

func _die() -> void:
	_state = State.DYING
	velocity = Vector2.ZERO
	if _ring != null:
		_ring.queue_free()
		_ring = null
	# died at HP 0 (contract) - the ELIMINATION objective completes here;
	# the crumble animation is presentation only.
	died.emit()
	_spawn_reward_drop()
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	_play(&"death")
	sprite.animation_finished.connect(_on_death_anim_finished, CONNECT_ONE_SHOT)

func _on_death_anim_finished() -> void:
	queue_free()
