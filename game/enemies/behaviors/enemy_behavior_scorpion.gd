class_name EnemyBehaviorScorpion
extends EnemyBehavior
## #855: explicit clocks, aim lock, no contact attacks outside strike windows.
enum State { CHARGE_WINDUP, CHARGE, BURIED, BURROW_RUSH, EMERGE, STING_WINDUP, STING_HOP, STING_STRIKE, MISS_STUN, RECOVER, CHASE, PINCER_WINDUP, PINCER_STRIKE, PINCER_RECOVER, BURY }
@export var wake_range := 300.0
@export var pincer_range := 50.0
@export var sting_range := 110.0
@export var charge_range := 300.0
@export var hide_range := 650.0
@export var hide_delay := 2.0
@export var dash_speed := 900.0
@export var dash_distance := 200.0
@export var sting_damage := 25
@export var sting_gap := 1.5
@export var pincer_damage := 15
@export var pincer_gap := 1.0
@export var transition_time := 0.30
const STING_WINDUP := 0.36
## Initial-only fast reaction window, after the full0.30s emerge.
const INITIAL_CHARGE_WINDUP := 0.18
## Pincer first pose100ms + held pose420ms = 520ms to impact.
const PINCER_WINDUP := 0.52
const STRIKE_TIME := 0.06
const MISS_STUN_TIME := 1.0
const MISS_HIT_BONUS := 2.0
const HOP_TIME := 0.10
const HOP_DISTANCE := 60.0
const HOP_STOP_DISTANCE := 52.0
var state: State = State.BURIED
var _time := 0.0
var _far := 0.0
var _sting_cd := 0.0
var _pincer_cd := 0.0
var _aim := Vector2.DOWN
var _remaining := 0.0
var _landed := false
var _miss_duration := MISS_STUN_TIME
var _miss_extended := false
var _path := TerrainPath.new()
var _initial_charge := false
var _charge_cd := 0.0
var _charge_length := 0.0
const CHARGE_HIT_RADIUS := 24.0

func _enter(e: EnemyScorpion, next: State) -> void:
	state = next
	_time = 0.0
	e.velocity = Vector2.ZERO
	e.clear_action()
	e.set_hop_height(0.0)
	match state:
		State.BURIED: e.set_buried(true)
		State.BURROW_RUSH:
			e.set_buried(true)
			_remaining = dash_distance
		State.CHARGE_WINDUP:
			_charge_length = e.charge_travel(_aim,dash_distance)
			e.play_action(&"pincer",true)
			e.sprite.set_frame_and_progress(1,0.0)
			e.sprite.pause()
		State.CHARGE:
			_initial_charge = false
			_remaining = _charge_length
			_landed = false
			_charge_cd = sting_gap
			e.play_action(&"pincer",true)
			e.sprite.set_frame_and_progress(1,0.0)
			e.sprite.pause()
		State.EMERGE:
			_initial_charge = true
			e.set_buried(false)
			e.play_action(&"emerge", true)
		State.STING_WINDUP:
			_initial_charge = false
			e.play_action(&"attack", true)
			e.sprite.pause()
		State.STING_HOP:
			e.play_action(&"attack",true)
			e.sprite.set_frame_and_progress(1,0.0)
			e.sprite.pause()
		State.STING_STRIKE:
			_initial_charge = false
			_landed = false
			_sting_cd = sting_gap
			e.play_action(&"attack", true)
			e.sprite.set_frame_and_progress(2,0.0)
			e.sprite.pause()
		State.MISS_STUN:
			_miss_duration = MISS_STUN_TIME
			_miss_extended = false
			e.play_action(&"attack", true)
			e.sprite.set_frame_and_progress(2,0.0)
			e.sprite.pause()
		State.RECOVER:
			e.play_action(&"attack", true)
			e.sprite.set_frame_and_progress(3,0.0)
		State.PINCER_WINDUP:
			_pincer_cd = pincer_gap
			e.play_action(&"pincer", true)
		State.PINCER_STRIKE:
			_pincer_cd = pincer_gap
			_landed = false
			e.play_action(&"pincer", true)
			e.sprite.set_frame_and_progress(2,0.0)
		State.PINCER_RECOVER:
			e.play_action(&"pincer", true)
			e.sprite.set_frame_and_progress(3,0.0)
		State.BURY:
			e.play_action(&"bury", true)

func physics_step(enemy: Enemy, player, delta: float) -> void:
	var e := enemy as EnemyScorpion
	if e == null: return
	_time += delta
	_sting_cd = maxf(0.0,_sting_cd-delta)
	_charge_cd = maxf(0.0,_charge_cd-delta)
	_pincer_cd = maxf(0.0,_pincer_cd-delta)
	var alive: bool = player != null and is_instance_valid(player) and player.hp > 0
	var off: Vector2 = player.global_position-e.global_position if alive else Vector2.ZERO
	var distance := off.length() if alive else INF
	if state == State.CHASE:
		_far = _far+delta if distance > hide_range else 0.0
		if _far >= hide_delay:
			_far = 0.0
			_enter(e,State.BURY)
			return
	match state:
		State.BURIED:
			if alive and distance <= wake_range:
				_aim = off.normalized()
				e.face_player(_aim)
				_enter(e,State.BURROW_RUSH)
		State.BURROW_RUSH:
			# Rush toward locked player position, leaving room for the body charge tell.
			if not alive or distance <= 180.0 or _remaining <= 0.0:
				if alive: _aim = off.normalized()
				e.face_player(_aim)
				_enter(e,State.EMERGE)
			else:
				_move(e,delta,minf(_remaining,maxf(0.0,distance-180.0)))
		State.EMERGE:
			if _time >= transition_time:
				if alive and distance <= sting_range:
					_initial_charge = false
					_aim = off.normalized()
					e.face_player(_aim)
					_enter(e,State.STING_WINDUP)
				else:
					_enter(e,State.CHARGE_WINDUP)
		State.CHARGE_WINDUP:
			_charge_length = e.charge_travel(_aim,dash_distance)
			if _time >= sting_windup_duration():
				if alive and distance <= sting_range:
					_aim = off.normalized()
					e.face_player(_aim)
					_enter(e,State.STING_WINDUP)
				elif alive:
					_enter(e,State.CHARGE)
				else: _enter(e,State.CHASE)
		State.CHARGE:
			var before := e.global_position
			var step := minf(dash_speed*delta,_remaining)
			var allowed := e.charge_travel(_aim,step)
			var externally_moved := is_instance_valid(e.displacement_owner)
			if externally_moved:
				# Enemy runs this branch only to sample self-propulsion. The
				# reel/stack combines that drive with force and owns the sole move.
				e.submit_external_motion(before+_aim*allowed,delta)
			elif allowed > 0.001:
				e.move_and_collide(_aim*allowed)
			var traveled := maxf(0.0,(e.global_position-before).dot(_aim))
			# A held charge spends its propulsion budget, not the reel's net
			# displacement. Opposing pulls must not extend the attack forever.
			var spent := allowed if externally_moved else traveled
			_remaining = maxf(0.0,_remaining-spent)
			if alive and not _landed:
				var near := Geometry2D.get_closest_point_to_segment(player.global_position,before,e.global_position)
				if near.distance_to(player.global_position) <= CHARGE_HIT_RADIUS:
					_landed = e.deal_hit(player,sting_damage,OnHit.DELIVERY_MELEE) != null
			if _remaining <= 0.001 or spent < step-0.01:
				if alive:
					_aim = (player.global_position-e.global_position).normalized()
					e.face_player(_aim)
				_enter(e,State.PINCER_STRIKE)
		State.STING_WINDUP:
			if _time >= 0.1:
				e.sprite.set_frame_and_progress(1,0.0)
			if _time >= STING_WINDUP:
				# Toward-only spacing hop, never pass through a close player.
				if alive:
					_aim = off.normalized()
					e.face_player(_aim)
				_remaining = minf(HOP_DISTANCE,maxf(0.0,distance-HOP_STOP_DISTANCE)) if alive else 0.0
				_enter(e,State.STING_HOP)
		State.STING_HOP:
			var budget := minf(HOP_DISTANCE/HOP_TIME*delta,_remaining)
			var allowed := e.charge_travel(_aim,budget)
			if is_instance_valid(e.displacement_owner):
				e.submit_external_motion(e.global_position+_aim*allowed,delta)
			elif allowed > 0.001:
				e.move_and_collide(_aim*allowed)
			_remaining = maxf(0.0,_remaining-allowed)
			if _time+0.000001 >= HOP_TIME: _enter(e,State.STING_STRIKE)
			else: e.set_hop_height(12.0*sin(PI*clampf(_time/HOP_TIME,0.0,1.0)))
		State.STING_STRIKE:
			# Stationary tail strike, independent of the body charge.
			if alive and not _landed and distance <= sting_range:
				if e.stinger_tip().distance_to(player.global_position) <= 24.0:
					_landed = e.deal_hit(player,sting_damage,OnHit.DELIVERY_MELEE) != null
			if _time >= STRIKE_TIME:
				_enter(e,State.RECOVER if _landed else State.MISS_STUN)
		State.MISS_STUN:
			if _time >= _miss_duration: _enter(e,State.CHASE)
		State.RECOVER:
			if _time >= 0.36: _enter(e,State.CHASE)
		State.CHASE:
			if not alive:
				e.velocity = Vector2.ZERO
				return
			e.face_player(off)
			if distance <= sting_range and _sting_cd <= 0.0:
				_aim = off.normalized()
				_enter(e,State.STING_WINDUP)
			elif distance > sting_range and distance <= charge_range and _charge_cd <= 0.0:
				_aim = off.normalized()
				_enter(e,State.CHARGE_WINDUP)
			elif distance <= pincer_range and _pincer_cd <= 0.0:
				_aim = off.normalized()
				_enter(e,State.PINCER_WINDUP)
			elif distance > pincer_range:
				e.velocity = _path.steer(e.terrain,e.global_position,e.velocity,off.normalized()*e.speed,player.global_position,e.speed,delta,false,true)
				e.terrain_move_and_slide()
			else: e.velocity = Vector2.ZERO
		State.PINCER_WINDUP:
			if _time >= PINCER_WINDUP: _enter(e,State.PINCER_STRIKE)
		State.PINCER_STRIKE:
			if alive and not _landed and distance <= pincer_range and off.normalized().dot(_aim) >= 0.25:
				_landed = e.deal_hit(player,pincer_damage,OnHit.DELIVERY_MELEE) != null
			if _time >= STRIKE_TIME: _enter(e,State.PINCER_RECOVER)
		State.PINCER_RECOVER:
			if _time >= 0.32: _enter(e,State.CHASE)
		State.BURY:
			if _time >= transition_time: _enter(e,State.BURIED)

func _move(e: EnemyScorpion, delta: float, budget: float) -> void:
	var step := minf(dash_speed*delta,budget)
	e.velocity = _aim*step/maxf(delta,0.000001)
	e.terrain_move_and_slide()
	_remaining = maxf(0.0,_remaining-step)

func is_stunned() -> bool:
	return state == State.MISS_STUN

## Called from an accepted Player OnHit event, never from modifier queries.
func extend_miss_stun() -> void:
	if state == State.MISS_STUN and not _miss_extended:
		_miss_extended = true
		_miss_duration += MISS_HIT_BONUS

func sting_windup_duration() -> float:
	return INITIAL_CHARGE_WINDUP if _initial_charge else STING_WINDUP
