class_name EnemyBehaviorScorpion
extends EnemyBehavior
## #855: explicit clocks, aim lock, no contact attacks outside strike windows.
enum State { BURIED, BURROW_RUSH, EMERGE, STING_WINDUP, STING_DASH, MISS_STUN, RECOVER, CHASE, PINCER_WINDUP, PINCER_STRIKE, PINCER_RECOVER, BURY }
@export var wake_range := 300.0
@export var pincer_range := 50.0
@export var sting_range := 180.0
@export var hide_range := 650.0
@export var hide_delay := 2.0
@export var dash_speed := 600.0
@export var dash_distance := 200.0
@export var sting_damage := 25
@export var sting_gap := 1.5
@export var pincer_damage := 15
@export var pincer_gap := 1.0
@export var transition_time := 0.30
const STING_WINDUP := 0.36
## Pincer first pose100ms + held pose420ms = 520ms to impact.
const PINCER_WINDUP := 0.52
const STRIKE_TIME := 0.06
const MISS_STUN_TIME := 0.5
var state: State = State.BURIED
var _time := 0.0
var _far := 0.0
var _sting_cd := 0.0
var _pincer_cd := 0.0
var _aim := Vector2.DOWN
var _remaining := 0.0
var _landed := false
var _path := TerrainPath.new()

func _enter(e: EnemyScorpion, next: State) -> void:
	state = next
	_time = 0.0
	e.velocity = Vector2.ZERO
	e.clear_action()
	match state:
		State.BURIED: e.set_buried(true)
		State.BURROW_RUSH:
			e.set_buried(true)
			_remaining = dash_distance
		State.EMERGE:
			e.set_buried(false)
			e.play_action(&"emerge", true)
		State.STING_WINDUP:
			e.play_action(&"attack", true)
		State.STING_DASH:
			_remaining = dash_distance
			_landed = false
			_sting_cd = sting_gap
			e.play_action(&"attack", true)
			e.sprite.set_frame_and_progress(2,0.0)
			e.sprite.pause()
		State.MISS_STUN:
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
			# Rush toward locked player position, leaving room for the sting tell.
			if not alive or distance <= sting_range or _remaining <= 0.0:
				if alive: _aim = off.normalized()
				e.face_player(_aim)
				_enter(e,State.EMERGE)
			else:
				_move(e,delta,minf(_remaining,maxf(0.0,distance-sting_range)))
		State.EMERGE:
			if _time >= transition_time:
				_enter(e,State.STING_WINDUP)
		State.STING_WINDUP:
			if _time >= STING_WINDUP: _enter(e,State.STING_DASH)
		State.STING_DASH:
			var before := e.stinger_tip()
			_move(e,delta,_remaining)
			if alive and not _landed:
				var near := Geometry2D.get_closest_point_to_segment(player.global_position,before,e.stinger_tip())
				if near.distance_to(player.global_position) <= 24.0:
					_landed = e.deal_hit(player,sting_damage,OnHit.DELIVERY_MELEE) != null
			if _remaining <= 0.0 or _time >= dash_distance/dash_speed:
				_enter(e,State.RECOVER if _landed else State.MISS_STUN)
		State.MISS_STUN:
			if _time >= MISS_STUN_TIME: _enter(e,State.CHASE)
		State.RECOVER:
			if _time >= 0.36: _enter(e,State.CHASE)
		State.CHASE:
			if not alive:
				e.velocity = Vector2.ZERO
				return
			e.face_player(off)
			if distance <= pincer_range and _pincer_cd <= 0.0:
				_aim = off.normalized()
				_enter(e,State.PINCER_WINDUP)
			elif distance > pincer_range and distance <= sting_range and _sting_cd <= 0.0:
				_aim = off.normalized()
				_enter(e,State.STING_WINDUP)
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
