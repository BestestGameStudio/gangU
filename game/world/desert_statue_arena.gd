class_name DesertStatueArena
extends Node2D
## Sunbound Sanctum. Run-owned state persists until the normal death reset.
## Initial balance values are tunable placeholders.
## Phase 2 tell/attack alignment is tracked in #666.

enum State { DORMANT, POSSESSED, STUNNED, PREPARING, TRANSFERRING, PHASE_TWO }
var arena_radius := 0.0
var statue_radius := 0.0
var barrier_radius := 0.0
var player_limit_radius := 0.0
var activation_radius := 0.0
var _sized := false
@export var spear_radius := 1.5
@export var arena_diameter_screen_heights := 1.7
@export var boss_max_hp := 2400
@export var statue_max_hp := 90
@export var spear_damage := 10
## World-space screen widths per second at the unchanged normal zoom.
@export var spear_screen_speed := 1.15
@export var volley_interval := 1.5
@export var volley_delay := 1.5
@export var lane_delay_max := 0.2
@export var ray_growth_duration := 0.7
@export var vision_angle_degrees := 150.0
@export var vision_range_ring_fraction := 0.6
@export var stun_duration := 1.0
@export var transfer_speed := 380.0
@export var transfer_windup := 0.35
@export var star_damage := 16
@export var phase_two_damage_per_statue := 0.08
@export var phase_two_speed_per_statue := 0.06
@export var phase_two_heal_per_statue := 16
## Phase-two attack and arena hazard tuning are PLACEHOLDERS.
@export var phase_two_hazard_duration := 48.0
@export var phase_two_attack_damage := 18
@export var phase_two_attack_gap := 0.65
@export var phase_two_shield_heal_per_second := 12.0
@export var victory_coins := 500

var hp := 2400
var _won := false
var state: State = State.DORMANT
var statues: Array[DesertStatue] = []
var _ring_points: Array[Vector2] = []
var possessed: DesertStatue
var star: DesertPossessionStar
var player: Player
var visiting := false
var broken_count := 0
class SpearLane:
	extends RefCounted
	var shooter: DesertStatue
	var target: DesertStatue
	var start := Vector2.ZERO
	var end := Vector2.ZERO

	var starts_at := 0.0
	var fires_at := 0.0
	var finished := false
	var animation_started := false

class SpearVolley:
	extends RefCounted
	var starts_at := 0.0
	var counted := false
	var aims_at_player := false
	var lanes: Array[SpearLane] = []

var volleys_left := 0
var _attack_time := 0.0
var _next_volley_at := 0.0
var _pending_volleys: Array[SpearVolley] = []
var _screen_world_size := Vector2.ZERO
var _previous_targets: Dictionary = {}
var phase_two_damage_multiplier := 1.0
var phase_two_speed_multiplier := 1.0
var phase_two_recovered_hp := 0
var _stun_left := 0.0
var _hit_stun_used := false
var _episode_host: DesertStatue
var _force_hop := false
var _phase_time := 0.0
# One clock/shape contract drives tell, release, actor posing and hit checks.
# Timing is PLACEHOLDER tuning: final windup third locks aim for a fair dodge.
const MOVE_WINDUP := [0.8, 0.7, 0.95, 1.0, 0.75, 0.85, 0.75]
const MOVE_RELEASE := [1.25, 2.05, 1.3, 1.55, 1.15, 1.25, 1.1]
const MOVE_CUE := [0.0, 0.22, 0.12, 0.4, 0.0, 0.0, 0.0]
const FAN_COUNT := 19
const FAN_RELEASE_DURATION := 0.36
const FAN_HALF_ANGLE := PI*0.5
const SWEEP_RADIUS := 245.0
const SWEEP_HALF_ANGLE := acos(0.35)
const SLAM_RADIUS := 145.0
const DASH_HIT_RADIUS := 56.0
const BASH_HIT_RADIUS := 66.0
var general_height := 0.0
var _phase_two_locked := false
var _phase_two_origin := Vector2.ZERO
var _phase_two_direction := Vector2.DOWN
var _phase_two_next_other := 1
var _phase_two_attack_time := 0.0
var _phase_two_attack_index := 0
var _phase_two_attack_done := false
var _phase_two_release_done := false
var _phase_two_dash_count := 0
var _phase_two_dash_hit := false
var _phase_two_aim := Vector2.ZERO
var _phase_two_boss_position := Vector2.ZERO
var _phase_two_impact_time := 0.0
var _phase_two_impact_position := Vector2.ZERO
var _phase_two_impact_duration := 0.55
var _phase_two_impact_radius := 145.0
var _phase_two_bash_start := Vector2.ZERO
var _phase_two_bash_direction := Vector2.DOWN
var _phase_two_bash_hit := false
var _phase_two_shield: StaticBody2D
var _phase_two_shield_time := 0.0
var _phase_two_shield_heal_fraction := 0.0
var _phase_two_bombardment: DesertBombardment
var _transfer_target: DesertStatue
var _transfer_left := 0.0
class EnemyBoundary:
	extends RefCounted
	var inside := false
	var radius := 16.0
	var direction := Vector2.RIGHT
	var previous: Callable
	var position := Vector2.ZERO
var _enemy_boundaries: Dictionary = {}
var _ui: CanvasLayer
var _title: Label
var _details: Label
var _bar: ProgressBar
var _rng := RandomNumberGenerator.new()
var audio: DesertStatueAudio
const CombatEffects := preload("res://game/combat/combat_effects.gd")
const SPEAR_VISUAL := preload("res://game/world/desert_spear_visual.gd")
const PROJECTILE := preload("res://game/spells/projectile.tscn")
const BOMBARDMENT := preload("res://game/world/desert_bombardment.gd")

func _ready() -> void:
	configure_size()
	_rng.randomize()
	hp = boss_max_hp
	player = get_parent().get_parent().get_node_or_null("Player") as Player
	var player_shape := player.get_node("CollisionShape2D") as CollisionShape2D
	var player_radius := (player_shape.shape as CircleShape2D).radius
	player_limit_radius = barrier_radius-player_radius-2.0
	z_index = -10
	for i in 12:
		var statue := DesertStatue.new()
		statue.name = "Statue%02d" % (i+1)
		statue.arena = self
		statue.player_path = NodePath("../" + String(get_path_to(player)))
		var definition := EnemyDefinition.new()
		definition.max_hp = statue_max_hp
		definition.speed = 0
		statue.definition = definition
		statue.hp = statue_max_hp
		statue.terrain = get_parent().get_node_or_null("Terrain") as TerrainMap
		statue.position = _statue_position(i)
		_ring_points.append(statue.position)
		statue.z_index = 10
		add_child(statue)
		statues.append(statue)
	audio = DesertStatueAudio.new()
	add_child(audio)
	_make_ui()
	get_tree().node_added.connect(_watch_enemy_spawn)

func _make_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 6
	add_child(_ui)
	var panel := VBoxContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.offset_left = -240
	panel.offset_right = 240
	panel.offset_top = 42
	panel.offset_bottom = 122
	_ui.add_child(panel)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size",22)
	_title.add_theme_color_override("font_color",Color("ffe3a0"))
	panel.add_child(_title)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(480,15)
	_bar.show_percentage = false
	_bar.max_value = boss_max_hp
	var track := StyleBoxFlat.new()
	track.bg_color = Color("342c2c")
	track.border_color = Color("8c744c")
	track.set_border_width_all(2)
	track.set_corner_radius_all(5)
	_bar.add_theme_stylebox_override("background",track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("d9a94b")
	fill.set_corner_radius_all(5)
	_bar.add_theme_stylebox_override("fill",fill)
	panel.add_child(_bar)
	_details = Label.new()
	_details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_details.add_theme_font_size_override("font_size",14)
	panel.add_child(_details)
	_ui.hide()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	var inside := player.global_position.distance_to(global_position) < activation_radius
	if state == State.DORMANT and inside:
		start_encounter()
	var next_visit := state != State.DORMANT and player.hp > 0 and is_visible_in_tree()
	if visiting != next_visit:
		visiting = next_visit
	_ui.visible = visiting
	if not visiting:
		return
	for enemy in _enemy_boundaries.keys():
		if is_instance_valid(enemy):
			enemy.global_position = constrain_enemy_position(enemy.global_position,enemy)
	# Direct scripted repositioning also remains on the inner side of the ring.
	player.global_position = constrain_player_position(player.global_position)
	if state == State.PHASE_TWO:
		_phase_time += delta
		_phase_two_step(delta)
	elif state == State.STUNNED:
		_stun_left -= delta
		if _stun_left <= 0:
			if _force_hop:
				begin_transfer.call_deferred()
			else:
				state = State.POSSESSED
	elif state == State.PREPARING:
		_update_transfer_preparation(delta)
	if state != State.PHASE_TWO:
		_advance_volleys(delta)
	_update_ui()
	queue_redraw()

func start_encounter() -> void:
	if state != State.DORMANT:
		return
	player.movement_constraint = Callable(self,"constrain_player_position")
	_possess(statues[_rng.randi_range(0,11)])
	for enemy in get_tree().get_nodes_in_group(&"enemies"):
		_register_enemy(enemy)

func is_active() -> bool:
	# A won fight is over: state stays PHASE_TWO on the kneeling general, so
	# without the _won check hub travel stays refused forever (AreaLoader
	# blocks the hub gate while an encounter is active).
	return not _won and state != State.DORMANT and is_instance_valid(player) and player.hp > 0

func constrain_player_position(destination: Vector2) -> Vector2:
	if _won or not is_active() or not is_visible_in_tree():
		return destination
	var offset := destination-global_position
	return global_position+offset.limit_length(player_limit_radius)

func _watch_enemy_spawn(node: Node) -> void:
	if node is Enemy and not (node is DesertStatue):
		_register_enemy.call_deferred(node)

func _register_enemy(candidate: Variant) -> void:
	if not is_instance_valid(candidate) or not (candidate is Enemy) or candidate is DesertStatue:
		return
	var enemy := candidate as Enemy
	if not is_active() or not is_visible_in_tree() or not get_parent().is_ancestor_of(enemy) or _enemy_boundaries.has(enemy):
		return
	var boundary := EnemyBoundary.new()
	var offset := enemy.global_position-global_position
	boundary.position = enemy.global_position
	boundary.inside = offset.length() < barrier_radius
	boundary.direction = offset.normalized() if not offset.is_zero_approx() else Vector2.RIGHT
	var shape := enemy.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape != null and shape.shape != null:
		var size := shape.shape.get_rect().size*enemy.scale.abs()
		boundary.radius = maxf(size.x,size.y)*0.5
	boundary.previous = enemy.movement_constraint
	_enemy_boundaries[enemy] = boundary
	enemy.movement_constraint = Callable(self,"constrain_enemy_position").bind(enemy)
	enemy.tree_exiting.connect(_release_enemy.bind(enemy),CONNECT_ONE_SHOT)

func constrain_enemy_position(destination: Vector2, enemy: Enemy) -> Vector2:
	if not _enemy_boundaries.has(enemy):
		return destination
	var boundary: EnemyBoundary = _enemy_boundaries[enemy]
	var offset := destination-global_position
	if not is_active() or not is_visible_in_tree():
		boundary.position = destination
		boundary.inside = offset.length() < barrier_radius
		return destination
	if not offset.is_zero_approx():
		boundary.direction = offset.normalized()
	var result := destination
	if boundary.inside:
		result = global_position+offset.limit_length(barrier_radius-boundary.radius-2.0)
	else:
		var limit := barrier_radius+boundary.radius+2.0
		var from := boundary.position-global_position
		if from.length() < limit:
			from = from.normalized()*limit if not from.is_zero_approx() else boundary.direction*limit
		var motion := offset-from
		var length_squared := motion.length_squared()
		var dot := from.dot(motion)
		var discriminant := dot*dot-length_squared*(from.length_squared()-limit*limit)
		if length_squared > 0.000001 and discriminant >= 0:
			var contact := (-dot-sqrt(discriminant))/length_squared
			if contact >= 0 and contact <= 1:
				result = global_position+from+motion*contact
		if (result-global_position).length() < limit-0.01:
			result = global_position+from.normalized()*limit
	boundary.position = result
	return result

func _release_enemy(enemy: Enemy) -> void:
	if not _enemy_boundaries.has(enemy):
		return
	if is_instance_valid(enemy) and enemy.movement_constraint == Callable(self,"constrain_enemy_position").bind(enemy):
		var boundary: EnemyBoundary = _enemy_boundaries[enemy]
		enemy.movement_constraint = boundary.previous
	_enemy_boundaries.erase(enemy)

func _exit_tree() -> void:
	for enemy in _enemy_boundaries.keys():
		_release_enemy(enemy)
	if is_instance_valid(player) and player.movement_constraint == Callable(self,"constrain_player_position"):
		player.movement_constraint = Callable()

func _possess(statue: DesertStatue) -> void:
	if statue != _episode_host:
		_hit_stun_used = false
		_episode_host = statue
	if possessed != null:
		possessed.possessed = false
	possessed = statue
	possessed.possessed = true
	volleys_left = _rng.randi_range(1,5)
	state = State.POSSESSED
	audio.possess(possessed.global_position)

func damage_statue(statue: DesertStatue, amount: int, crit_tier: int) -> void:
	if _won:
		return # The defeated general kneels; hits must not flash, play hit sfx or spawn damage numbers.
	if state == State.PHASE_TWO and general_height > 120.0:
		return # Airborne actor is off the floor, never an invisible target.
	if not visiting or state == State.DORMANT or amount <= 0:
		return
	statue.flash = 0.15
	statue.play_hit()
	audio.damage(statue.global_position)
	if state == State.PHASE_TWO:
		if statue == possessed:
			var boss_before := hp
			apply_damage(amount)
			OnHit.record(statue, boss_before, hp)
			CombatEffects.damage_number(get_parent(), statue.global_position, amount, crit_tier)
		return
	if statue == possessed:
		var before := hp
		apply_damage(amount)
		OnHit.record(statue,before,hp)
		if state != State.PHASE_TWO and not _hit_stun_used:
			_cancel_star()
			_stun(true)
	else:
		var before := statue.hp
		statue.hp = maxi(statue.hp-amount,0)
		OnHit.record(statue,before,statue.hp)
		if statue.hp == 0:
			statue.broken = true
			statue.play_break()
			statue.collision_layer = 0
			audio.death(statue.global_position)
			if not statue.destroyed_once:
				statue.destroyed_once = true
				broken_count += 1
	CombatEffects.damage_number(get_parent(),statue.global_position,amount,crit_tier)

func apply_damage(amount: int) -> void:
	hp = maxi(hp-maxi(amount,0),0)
	if state == State.PHASE_TWO and is_instance_valid(possessed):
		possessed.hp = hp
		possessed.health_changed.emit(hp, boss_max_hp)
	if hp <= boss_max_hp*3/4 and state != State.PHASE_TWO:
		_enter_phase_two()
	if hp <= 0 and state == State.PHASE_TWO:
		_phase_two_bombardment.active = false
		_details.text = "THE SAND GENERAL IS DEFEATED"
		_win()

func _win() -> void:
	if _won:
		return
	_won = true
	_remove_phase_two_shield()
	# _phase_two_step halts on hp<=0, so a slam shockwave telegraph live at the
	# kill would freeze mid-expansion and keep drawing its ring forever.
	_phase_two_impact_time = 0.0
	# The bombardment never stops on its own: on the win path it would keep
	# washing the arena red and drawing its gold safe-circle boundary forever,
	# which reads as a wall after the barrier is gone. The lose path already
	# stops it; do the same here.
	if is_instance_valid(_phase_two_bombardment):
		_phase_two_bombardment.active = false
		_phase_two_bombardment.queue_redraw()
	# The barrier falls with the general: the way out of the arena opens.
	if is_instance_valid(player) and player.movement_constraint == Callable(self,"constrain_player_position"):
		player.movement_constraint = Callable()
	_drop_reward.call_deferred()
	queue_redraw()

func _drop_reward() -> void:
	var origin: Vector2 = possessed.global_position if is_instance_valid(possessed) else global_position
	var drop: RewardDrop = preload("res://game/economy/reward_drop.tscn").instantiate()
	var coins := RewardEntry.new()
	coins.kind = RewardEntry.Kind.CURRENCY
	coins.currency_amount = victory_coins
	drop.setup(coins)
	get_parent().add_child(drop)
	drop.global_position = origin
	# #686: this custom path skipped the boss token table, so the general
	# dropped coins only. Roll the shared boss_token_table like any boss
	# (Enemy._spawn_reward_drop); the pool keeps tokens re-eligible per kill.
	# _win() guards on _won and post-defeat hits return early in
	# damage_statue, so this fires exactly once per defeat.
	var table: RewardTable = preload("res://data/rewards/boss_token_table.tres")
	var pool := Run.reward_pool()
	var granted: Array = pool.granted() if pool != null else []
	var entry := table.roll(granted)
	if entry == null:
		return
	var token_drop: RewardDrop = preload("res://game/economy/reward_drop.tscn").instantiate()
	token_drop.setup(entry)
	get_parent().add_child(token_drop)
	# Offset like Enemy.BOSS_RELIC_OFFSET so the two pickups do not overlap.
	token_drop.global_position = origin + Vector2(96, 0)

func heal(amount: int) -> void:
	var before := hp
	hp = mini(hp+maxi(amount,0),boss_max_hp)
	if hp != before and state == State.PHASE_TWO and is_instance_valid(possessed):
		possessed.hp = hp
		possessed.health_changed.emit(hp, boss_max_hp)

func _stun(force_hop: bool) -> void:
	_transfer_target = null
	_hit_stun_used = true
	state = State.STUNNED
	_stun_left = stun_duration
	_force_hop = force_hop

func _choose_transfer_target() -> DesertStatue:
	var choices: Array[DesertStatue] = []
	for statue in statues:
		if not statue.broken and statue != possessed:
			choices.append(statue)
	return null if choices.is_empty() else choices.pick_random()

func begin_transfer() -> void:
	if state in [State.PHASE_TWO,State.PREPARING,State.TRANSFERRING] or (state == State.STUNNED and _stun_left > 0) or not visiting:
		return
	_transfer_target = _choose_transfer_target()
	if _transfer_target == null:
		_possess(possessed)
		return
	state = State.PREPARING
	_transfer_left = transfer_windup

func _update_transfer_preparation(delta: float) -> void:
	if _transfer_target == null or _transfer_target.broken:
		_transfer_target = _choose_transfer_target()
		if _transfer_target == null:
			_possess(possessed)
			return
		_transfer_left = transfer_windup
		return
	_transfer_left -= delta
	if _transfer_left <= 0:
		_launch_star.call_deferred()

func _launch_star() -> void:
	if state != State.PREPARING:
		return
	if _transfer_target == null or _transfer_target.broken:
		_update_transfer_preparation(0)
		return
	state = State.TRANSFERRING
	star = DesertPossessionStar.new()
	star.arena = self
	star.origin = possessed
	star.destination = _transfer_target
	star.speed = transfer_speed
	star.contact_damage = star_damage
	star.position = possessed.position+Vector2(0,-20)
	possessed.possessed = false
	possessed = null
	_transfer_target = null
	star.z_index = 15
	add_child(star)

func star_arrived(returned: bool) -> void:
	if state != State.TRANSFERRING or not is_instance_valid(star):
		return
	var host: DesertStatue = star.origin if returned else star.destination
	# The star can rebuild its return host, or the last host if all statues broke.
	if host.broken:
		host.broken = false
		host.rebuild()
		host.hp = host.max_hp
		host.collision_layer = PhysicsLayers.ENEMY
	_possess(host)
	if returned:
		_stun(false)
	star = null

func _cancel_star() -> void:
	_transfer_target = null
	if is_instance_valid(star):
		star.queue_free()
	star = null

func _advance_volleys(delta: float) -> void:
	_attack_time += delta
	while _next_volley_at <= _attack_time+0.000001:
		_plan_volley(_next_volley_at)
		_next_volley_at += volley_interval
	var pending: Array[SpearVolley] = []
	for volley in _pending_volleys:
		var unfinished := false
		for lane in volley.lanes:
			if lane.finished:
				continue
			if lane.shooter.broken:
				lane.finished = true
			elif lane.fires_at <= _attack_time+0.000001:
				lane.finished = true
				_fire_lane.call_deferred(lane,volley)
			else:
				if not lane.animation_started and lane.fires_at - _attack_time <= lane.shooter.throw_windup(volley_interval):
					lane.animation_started = true
					lane.shooter.begin_throw(lane.fires_at - _attack_time, volley_interval, (lane.end - lane.start).normalized())
				unfinished = true
		if unfinished:
			pending.append(volley)
	_pending_volleys = pending

func statue_sees_point(statue: DesertStatue, point: Vector2) -> bool:
	if statue.broken:
		return false
	var offset := point-statue.global_position
	if offset.length() > statue_radius*vision_range_ring_fraction:
		return false
	if offset.is_zero_approx():
		return true
	var inward := (global_position-statue.global_position).normalized()
	return inward.dot(offset.normalized()) >= cos(deg_to_rad(vision_angle_degrees)*0.5)

func player_is_watched() -> bool:
	for statue in statues:
		if statue_sees_point(statue,player.global_position):
			return true
	return false

func _plan_volley(starts_at: float) -> void:
	var volley := SpearVolley.new()
	volley.starts_at = starts_at
	volley.aims_at_player = player_is_watched()
	var player_target := to_local(player.global_position)
	for shooter in statues:
		if shooter.broken:
			continue
		var target: DesertStatue
		var endpoint := player_target
		if not volley.aims_at_player:
			var choices: Array[DesertStatue] = []
			for candidate in statues:
				if candidate != shooter:
					choices.append(candidate)
			if choices.size() > 1:
				choices.erase(_previous_targets.get(shooter))
			if choices.is_empty():
				continue
			# Prefer crossing the interior instead of tracing adjacent ring edges.
			var across: Array[DesertStatue] = []
			for candidate in choices:
				if shooter.position.normalized().dot(candidate.position.normalized()) < -0.25:
					across.append(candidate)
			target = choices.pick_random() if across.is_empty() else across.pick_random()
			_previous_targets[shooter] = target
			# Broken statues' rubble moves inward, but the warning stays aimed at
			# the statue's original ring position for the full volley.
			endpoint = _ring_points[statues.find(target)]+Vector2(0,-20)
		else:
			# Aim through the frozen player position and keep flying to the arena edge.
			var direction := (player_target-(shooter.position+Vector2(0,-20))).normalized()
			var start := shooter.position+Vector2(0,-20)
			var projection := -start.dot(direction)
			var edge_distance := projection+sqrt(maxf(projection*projection+arena_radius*arena_radius-start.length_squared(),0.0))
			endpoint = start+direction*edge_distance
		var lane := SpearLane.new()
		lane.shooter = shooter
		lane.target = target
		lane.start = shooter.position+Vector2(0,-20)
		lane.end = endpoint
		lane.starts_at = starts_at+_rng.randf_range(0,lane_delay_max)
		lane.fires_at = lane.starts_at+volley_delay
		volley.lanes.append(lane)
	if not volley.lanes.is_empty():
		_pending_volleys.append(volley)

func _fire_lane(lane: SpearLane, volley: SpearVolley) -> void:
	if not visiting or state == State.PHASE_TWO or lane.shooter.broken:
		return
	var spell := Spell.new()
	spell.damage = spear_damage
	spell.projectile_speed = _screen_world_size.x*spear_screen_speed
	spell.range = lane.start.distance_to(lane.end)
	spell.radius = spear_radius
	spell.projectile_color = Color("dc734e")
	if volley.aims_at_player:
		spell.tags.append(SpellTags.PIERCING)
	var shot := PROJECTILE.instantiate() as Projectile
	shot.setup(spell,lane.end-lane.start,lane.shooter)
	shot.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.PLAYER | PhysicsLayers.SUMMON
	shot.position = lane.start
	shot.z_index = 12
	shot.visual_override = SPEAR_VISUAL.new()
	add_child(shot)
	# The first surviving spear counts this volley once, including during transit.
	if not volley.counted:
		volley.counted = true
		audio.spear(lane.shooter.global_position)
		if state == State.POSSESSED:
			volleys_left -= 1
			if volleys_left <= 0:
				begin_transfer()

func _ray_fraction(lane: SpearLane) -> float:
	return clampf((_attack_time-lane.starts_at)/ray_growth_duration,0,1)

func _draw_volley() -> void:
	# Newer rays draw first, leaving the imminent paths on top.
	for index in range(_pending_volleys.size()-1,-1,-1):
		for lane in _pending_volleys[index].lanes:
			if lane.finished or lane.shooter.broken:
				continue
			var fraction := _ray_fraction(lane)
			if fraction <= 0:
				continue
			var tip := lane.start.lerp(lane.end,fraction)
			draw_line(lane.start,tip,Color(0.3,0.04,0.03,0.18),2.5,true)
			draw_line(lane.start,tip,Color(0.95,0.12,0.12,0.65+fraction*0.3),1.0,true)
			if lane.start.distance_to(tip) < 20:
				continue
			var direction := (lane.end-lane.start).normalized()
			var side := direction.orthogonal()
			draw_polyline(PackedVector2Array([tip-direction*7+side*3,tip,tip-direction*7-side*3]),Color(1,0.35,0.25,0.9),1.0,true)

func _next_spear_delay() -> float:
	var remaining := INF
	for volley in _pending_volleys:
		for lane in volley.lanes:
			if not lane.finished and not lane.shooter.broken:
				remaining = minf(remaining,lane.fires_at-_attack_time)
	return maxf(remaining,0)

func _enter_phase_two() -> void:
	state = State.PHASE_TWO
	_phase_two_boss_position = Vector2(0, -arena_radius + 100.0)
	_phase_two_attack_time = 0.0
	_phase_two_attack_index = 0
	_phase_two_bombardment = BOMBARDMENT.new() as DesertBombardment
	_phase_two_bombardment.name = "PhaseTwoBombardment"
	_phase_two_bombardment.shrink_duration = phase_two_hazard_duration
	_phase_two_bombardment.max_progress = 1.0
	_phase_two_bombardment.start(arena_radius)
	_phase_two_bombardment.bombardment_due.connect(_on_bombardment_due)
	add_child.call_deferred(_phase_two_bombardment)
	# Reuse the encounter's hit receiver as the general's target so player
	# spells keep their normal collision and OnHit flow.
	if is_instance_valid(possessed):
		possessed.position = _phase_two_boss_position
		possessed.hp = hp
		possessed.max_hp = boss_max_hp
		possessed.broken = false
		possessed.absorbed = false
		possessed.collision_layer = PhysicsLayers.ENEMY
		possessed.collision_mask = 0
	for statue in statues:
		if statue != possessed:
			statue.absorbed = true
			statue.collision_layer = 0
	_pending_volleys.clear()
	_cancel_star()
	phase_two_damage_multiplier = 1.0 + broken_count*phase_two_damage_per_statue
	phase_two_speed_multiplier = 1.0 + broken_count*phase_two_speed_per_statue
	var before := hp
	heal(broken_count*phase_two_heal_per_statue)
	phase_two_recovered_hp = hp-before
	for shot: Projectile in get_tree().get_nodes_in_group(&"projectiles"):
		if shot.source is DesertStatue and (shot.source as DesertStatue).arena == self:
			shot.queue_free()
	queue_redraw()

## PHASE 2 boss loop: each move has a readable windup, release, then recovery.
## The sand general is arena-owned (like phase-one possession), so its HP
## remains the encounter HP and all attacks use the normal Player damage path.
func _phase_two_step(delta: float) -> void:
	_phase_two_impact_time = maxf(_phase_two_impact_time-delta, 0.0)
	if _phase_two_shield_time > 0.0:
		_phase_two_shield_time -= delta
		if _phase_two_shield_time <= 0.0:
			_remove_phase_two_shield()
	if hp <= 0:
		return
	if _phase_two_shield_time > 0.0:
		_phase_two_shield_heal_fraction += phase_two_shield_heal_per_second*delta
		var healing := floori(_phase_two_shield_heal_fraction)
		if healing > 0:
			heal(healing)
			_phase_two_shield_heal_fraction -= healing
	if _phase_two_bombardment != null:
		_phase_two_bombardment.advance(delta)
		_phase_two_boss_position = _constrain_boss_position(_phase_two_boss_position)
	if is_instance_valid(possessed):
		possessed.position = _phase_two_boss_position
	_phase_two_attack_time += delta*phase_two_speed_multiplier
	var move := _phase_two_attack_index
	var windup: float = MOVE_WINDUP[move]
	var release: float = MOVE_RELEASE[move]
	if _phase_two_attack_time < 0.0:
		return
	if not _phase_two_locked:
		_phase_two_origin = _phase_two_boss_position
		_phase_two_aim = _constrain_boss_position(to_local(player.global_position))
		_phase_two_direction = (_phase_two_aim-_phase_two_origin).normalized()
		if _phase_two_direction.is_zero_approx():
			_phase_two_direction = Vector2.DOWN
		if _phase_two_attack_time >= windup*0.65:
			_phase_two_locked = true
	if move == 3:
		# Lift the entire actor above the current camera view, move only while
		# off screen, then descend onto the locked ring. Damage waits for feet.
		var height := maxf(_screen_world_size.y*1.4, 900.0)
		if _phase_two_attack_time < 0.25:
			general_height = 0.0
		elif _phase_two_attack_time < 0.6:
			general_height = height*ease(clampf((_phase_two_attack_time-0.25)/0.35,0.0,1.0),0.5)
		elif _phase_two_attack_time < windup+0.18:
			general_height = height
			if _phase_two_locked:
				_phase_two_boss_position = _phase_two_aim
		else:
			general_height = height*(1.0-pow(clampf((_phase_two_attack_time-windup-0.18)/0.22,0.0,1.0),2.0))
	if is_instance_valid(possessed):
		possessed.position = _phase_two_boss_position
		possessed.collision_layer = 0 if general_height > 120.0 else PhysicsLayers.ENEMY
	if _phase_two_attack_time < windup:
		return
	var attack_time: float = _phase_two_attack_time-windup
	if not _phase_two_attack_done:
		_phase_two_attack_done = true
		_phase_two_dash_count = -1
		_phase_two_dash_hit = false
		_phase_two_release_done = false
		_phase_two_bash_start = _phase_two_origin
		_phase_two_bash_direction = _phase_two_direction
		_phase_two_bash_hit = false
	_phase_two_execute(move, attack_time, delta)
	if is_instance_valid(possessed):
		possessed.position = _phase_two_boss_position
	if attack_time >= release:
		_phase_two_attack_time = -phase_two_attack_gap
		_phase_two_attack_done = false
		_phase_two_release_done = false
		_phase_two_locked = false
		general_height = 0.0
		# Fan may follow ANY other move, rather than occupying one cycle slot.
		# Other moves still rotate so every tell stays represented. No overlap.
		if move != 0 and _rng.randf() < 0.4:
			_phase_two_attack_index = 0
		else:
			_phase_two_attack_index = _phase_two_next_other
			_phase_two_next_other = _phase_two_next_other%6+1

func _fan_direction(index: int) -> Vector2:
	return _phase_two_direction.rotated(lerpf(-FAN_HALF_ANGLE,FAN_HALF_ANGLE,float(index)/float(FAN_COUNT-1)))

func _general_spear(start: Vector2, direction: Vector2, damage: int, distance: float, radius: float) -> Projectile:
	var shot := _spawn_general_projectile(start, direction, damage, distance, radius)
	var sprite := Sprite2D.new()
	sprite.texture = preload("res://assets/sprites/roman_general_spear.png")
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(1.6,1.6)
	# Source art points right, exactly like the shared projectile's +X axis.
	shot.visual_override = sprite
	return shot

func _phase_two_execute(attack: int, t: float, _delta: float) -> void:
	var target_offset := to_local(player.global_position)
	var attack_damage := maxi(roundi(phase_two_attack_damage*phase_two_damage_multiplier), 1)
	match attack:
		0: # 19 spears, one every ten degrees, leave the general in the locked, warned semicircle.
			while _phase_two_dash_count < FAN_COUNT-1 and t >= float(_phase_two_dash_count+1)*FAN_RELEASE_DURATION/float(FAN_COUNT-1):
				_phase_two_dash_count += 1
				var direction := _fan_direction(_phase_two_dash_count)
				_general_spear(_phase_two_origin+direction*45.0,direction,attack_damage,arena_radius*1.6,9.0)
		1: # Three short dashes. Each follow-up warns, locks, then moves.
			var slot := mini(floori(t/0.56),2)
			var beat := t-float(slot)*0.56
			if slot > _phase_two_dash_count:
				_phase_two_dash_count = slot
				_phase_two_dash_hit = false
				_phase_two_bash_start = _phase_two_boss_position
				if slot > 0:
					_phase_two_aim = _constrain_boss_position(target_offset)
					_phase_two_direction = (_phase_two_aim-_phase_two_boss_position).normalized()
			if beat >= 0.22 and beat < 0.46:
				var destination := _phase_two_bash_start.move_toward(_phase_two_aim,81.6*clampf((beat-0.22)/0.24,0.0,1.0))
				_phase_two_boss_position = _constrain_boss_position(destination)
				if not _phase_two_dash_hit and _phase_two_boss_position.distance_to(target_offset) < DASH_HIT_RADIUS:
					player.apply_damage(attack_damage)
					_phase_two_dash_hit = true
		2: # Visible broad slash uses the SAME sector as its warning.
			if t >= MOVE_CUE[2] and not _phase_two_release_done:
				_phase_two_release_done = true
				var to_player := target_offset-_phase_two_origin
				if to_player.length() < SWEEP_RADIUS and _phase_two_direction.dot(to_player.normalized()) > cos(SWEEP_HALF_ANGLE):
					player.apply_damage(attack_damage)
		3: # Feet land at t=.4; no remote damage while still in the sky.
			if t >= MOVE_CUE[3] and not _phase_two_release_done:
				_phase_two_release_done = true
				general_height = 0.0
				_phase_two_boss_position = _phase_two_aim
				_show_phase_two_impact(_phase_two_aim,SLAM_RADIUS,0.55)
				if target_offset.distance_to(_phase_two_aim) < SLAM_RADIUS:
					player.apply_damage(attack_damage+5)
		4: # Shield-first lunge, aligned to the warned capsule.
			var dash_progress := clampf(t/0.42,0.0,1.0)
			var eased_progress := 1.0-pow(1.0-dash_progress,3.0)
			_phase_two_boss_position = _constrain_boss_position(_phase_two_bash_start+_phase_two_bash_direction*175.0*eased_progress)
			if t <= 0.42 and not _phase_two_bash_hit and _phase_two_boss_position.distance_to(target_offset) < BASH_HIT_RADIUS:
				_phase_two_bash_hit = true
				_show_phase_two_impact(target_offset,68.0,0.32)
				player.apply_damage(attack_damage)
				player.launch(Vector2.DOWN,520.0,0.34)
			if t > 0.42:
				var retreat := clampf((t-0.42)/0.24,0.0,1.0)
				_phase_two_boss_position = _constrain_boss_position(_phase_two_bash_start+_phase_two_bash_direction*175.0*(1.0-retreat))
		5: # Single knockback spear follows its locked warning, never retargets.
			if not _phase_two_release_done:
				_phase_two_release_done = true
				var shot := _general_spear(_phase_two_origin+_phase_two_direction*45.0,_phase_two_direction,attack_damage+4,arena_radius*1.8,12.0)
				shot.hit.connect(_on_spear_throw_hit)
		6:
			if not _phase_two_release_done:
				_phase_two_release_done = true
				var between := _phase_two_origin.lerp(_phase_two_aim,0.56)
				var safe_position := _constrain_boss_position(between)
				_plant_phase_two_shield(safe_position,_phase_two_aim-safe_position)
	queue_redraw()

func _constrain_boss_position(destination: Vector2) -> Vector2:
	var safe_radius_limit := maxf(arena_radius-45.0, 1.0)
	if _phase_two_bombardment == null:
		return destination.limit_length(safe_radius_limit)
	var safe_boss_radius := maxf(_phase_two_bombardment.safe_radius-45.0, 0.0)
	return destination.limit_length(minf(safe_boss_radius, safe_radius_limit))

func _plant_phase_two_shield(local_position: Vector2, toward_player: Vector2) -> void:
	_remove_phase_two_shield()
	var shield := StaticBody2D.new()
	shield.name = "GeneralPlantedShield"
	shield.collision_layer = PhysicsLayers.WORLD
	shield.collision_mask = 0
	shield.position = local_position
	shield.rotation = toward_player.angle()+PI*0.5
	shield.z_index = 8
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(88.0, 24.0)
	collision.shape = shape
	shield.add_child(collision)
	# Visual-only Roman shield replacement. The 88x24 wall, placement, facing,
	# five-second lifetime and regeneration are unchanged.
	var face := AnimatedSprite2D.new()
	face.name = "RomanPlantedShield"
	face.sprite_frames = preload("res://assets/sprites/roman_planted_shield_frames.tres")
	face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	face.scale = Vector2(2.0, 2.0)
	face.play(&"idle")
	shield.add_child(face)
	_phase_two_shield = shield
	_phase_two_shield_time = 5.0
	_phase_two_shield_heal_fraction = 0.0
	add_child.call_deferred(shield)

func _remove_phase_two_shield() -> void:
	_phase_two_shield_time = 0.0
	_phase_two_shield_heal_fraction = 0.0
	if is_instance_valid(_phase_two_shield):
		_phase_two_shield.queue_free()
	_phase_two_shield = null

func _show_phase_two_impact(at: Vector2, radius: float, duration: float) -> void:
	_phase_two_impact_position = at
	_phase_two_impact_radius = radius
	_phase_two_impact_duration = duration
	_phase_two_impact_time = duration

func _spawn_general_projectile(local_start: Vector2, direction: Vector2, damage: int, max_range: float, radius: float) -> Projectile:
	var spell := Spell.new()
	spell.damage = damage
	spell.projectile_speed = maxf(_screen_world_size.x*0.78, 450.0)
	spell.range = max_range
	spell.radius = radius
	spell.projectile_color = Color("f0bd53")
	var shot := PROJECTILE.instantiate() as Projectile
	shot.setup(spell, direction, self)
	shot.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.PLAYER
	shot.position = local_start
	shot.z_index = 12
	add_child.call_deferred(shot)
	return shot

func _on_spear_throw_hit(body: Node2D) -> void:
	if body == player and is_instance_valid(player):
		player.launch(Vector2.DOWN, 650.0, 0.46)

func _on_bombardment_due() -> void:
	if is_instance_valid(player) and not _phase_two_bombardment.is_safe(player.global_position, global_position):
		player.apply_damage(maxi(roundi(phase_two_attack_damage*0.55*phase_two_damage_multiplier), 1))

func _update_ui() -> void:
	_bar.value = hp
	_title.text = "SUNBOUND SOVEREIGN  ·  %d / %d" % [hp,boss_max_hp]
	if state == State.PHASE_TWO and hp <= 0:
		_title.text = "THE SAND GENERAL IS DEFEATED"
		_details.text = "The Sunbound Sanctum is quiet"
	elif state == State.PHASE_TWO:
		_title.text = "PHASE 2  ·  THE SOVEREIGN AWAKENS"
		_details.text = "%d absorbed  |  Damage +%d%%  |  Speed +%d%%  |  Recovered %d HP" % [broken_count,roundi((phase_two_damage_multiplier-1)*100),roundi((phase_two_speed_multiplier-1)*100),phase_two_recovered_hp]
		if _phase_two_attack_time >= 0.0:
			var names := ["SPEAR FAN", "TRIPLE DASH", "FRONTAL CLEAVE", "SKYFALL", "SHIELD RUSH", "SPEAR THROW", "SHIELD PLANT"]
			var cue: float = MOVE_WINDUP[_phase_two_attack_index]+MOVE_CUE[_phase_two_attack_index]
			var tell := "AIM LOCKED" if _phase_two_locked else "TRACKING"
			if _phase_two_attack_time >= cue:
				tell = "RELEASE" if _phase_two_attack_time < cue+0.45 else "RECOVERING"
			_details.text = names[_phase_two_attack_index]+"  |  "+tell
		if _phase_two_shield_time > 0.0:
			_details.text += "  |  SHIELD REGENERATING"
	elif not _pending_volleys.is_empty():
		_details.text = "NEXT SPEARS IN %.1fs   |   Dodge the marked paths" % _next_spear_delay()
	elif state == State.STUNNED:
		_details.text = "POSSESSION STUNNED  ·  %.1fs   |   Broken statues: %d" % [_stun_left,broken_count]
	elif state == State.PREPARING:
		_details.text = "POSSESSION PATH  ·  %.1fs" % maxf(_transfer_left,0)
	elif state == State.TRANSFERRING:
		_details.text = "INTERCEPT THE PURPLE STAR   |   Broken statues: %d" % broken_count
	else:
		_details.text = "Strike the glowing eyes   |   Broken statues: %d" % broken_count

## Snapshot normal world-space screen dimensions once, before ground/cave placement.
## Resizing later preserves encounter walls, targets and terrain for this run.
func configure_size() -> void:
	if _sized:
		return
	var camera := get_viewport().get_camera_2d()
	var camera_zoom := camera.zoom if camera != null else Vector2.ONE
	_screen_world_size = get_viewport_rect().size / camera_zoom
	arena_radius = _screen_world_size.y * arena_diameter_screen_heights * 0.5
	statue_radius = arena_radius*0.75
	barrier_radius = statue_radius-DesertStatue.BODY_RADIUS
	activation_radius = minf(220.0,arena_radius*0.25)
	_sized = true

func shape_decor(ground: OverworldGround) -> void:
	configure_size()
	ground.decor = ground.decor.filter(func(d: Dictionary) -> bool:
		return not contains_footprint(d["at"], 140+float(d["r"])))

## Used before ready by the ground builder, keeping art and collision clear together.
func contains_footprint(point: Vector2, margin: float = 0.0) -> bool:
	configure_size()
	return point.distance_to(position) <= arena_radius+margin

func _statue_position(index: int) -> Vector2:
	return Vector2.from_angle(-PI/2 + TAU*index/12)*statue_radius

func _circle(radius: float, color: Color, width: float = -1.0) -> void:
	if width < 0:
		draw_circle(Vector2.ZERO,radius,color)
	else:
		draw_arc(Vector2.ZERO,radius,0,TAU,128,color,width,true)

func _draw() -> void:
	for i in 9:
		_circle(arena_radius+100-i*10,Color("bda076").lerp(Color("d8bd86"),float(i)/8))
	_circle(arena_radius-12,Color("b39a70"))
	for i in 650:
		var a := float(i)*2.399963
		var at := Vector2.from_angle(a)*sqrt(float(i)/650)*(arena_radius-15)
		draw_arc(at,8+i%12,0.2,1.6,8,Color(0.52,0.38,0.22,0.15),1)
	_circle(statue_radius,Color(0.59,0.39,0.2,0.35),2)
	for i in 12:
		var at := _ring_points[i]
		draw_circle(at,48,Color(0.65,0.48,0.27,0.25))
	_draw_volley()
	if state == State.PREPARING and _transfer_target != null:
		var from := possessed.position+Vector2(0,-20)
		var to := _transfer_target.position+Vector2(0,-20)
		draw_line(from,to,Color(0.65,0.22,1,0.85),1.0,true)
		var direction := (to-from).normalized()
		var side := direction.orthogonal()
		draw_polyline(PackedVector2Array([to-direction*9+side*3,to,to-direction*9-side*3]),Color("d9a5ff"),1.0,true)
	if state != State.DORMANT and not _won:
		var alpha := 0.65+sin(Time.get_ticks_msec()*0.003)*0.15
		_circle(barrier_radius,Color(1,0.79,0.3,alpha),4)
		_circle(barrier_radius-4,Color(1,0.86,0.49,0.2),8)
	if state == State.PHASE_TWO:
		if _phase_two_shield_time > 0.0:
			var heal_pulse := 54.0+sin(Time.get_ticks_msec()*0.01)*5.0
			draw_arc(_phase_two_boss_position,heal_pulse,0,TAU,64,Color(0.38,1.0,0.54,0.8),3.0,true)
			draw_string(ThemeDB.fallback_font,_phase_two_boss_position+Vector2(-5,-54),"+",HORIZONTAL_ALIGNMENT_LEFT,-1,25,Color("9dffad"))
		_draw_phase_two_telegraph()
	if state == State.DORMANT:
		draw_string(ThemeDB.fallback_font,Vector2(-arena_radius+80,-35),"SUNBOUND SANCTUM",HORIZONTAL_ALIGNMENT_LEFT,-1,23,Color("ffe7b4"))
		draw_string(ThemeDB.fallback_font,Vector2(-arena_radius+80,-10),"Walk east to the central seal",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("fff1d5"))
		draw_arc(Vector2.ZERO,activation_radius,0,TAU,80,Color(0.94,0.77,0.4,0.6),2)
		draw_string(ThemeDB.fallback_font,Vector2(-140,58),"SUNBOUND SANCTUM",HORIZONTAL_ALIGNMENT_LEFT,-1,23,Color("ffe7b4"))
		draw_string(ThemeDB.fallback_font,Vector2(-126,82),"Approach the seal to challenge",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("fff1d5"))

func _draw_phase_two_telegraph() -> void:
	if _phase_two_impact_time > 0.0:
		var impact_progress := 1.0-_phase_two_impact_time/_phase_two_impact_duration
		var impact_radius := 18.0+impact_progress*_phase_two_impact_radius
		var impact_alpha := clampf(_phase_two_impact_time/_phase_two_impact_duration, 0.0, 1.0)
		draw_circle(_phase_two_impact_position, _phase_two_impact_radius*0.46*(1.0-impact_progress*0.72), Color(1.0,0.82,0.39,0.42*impact_alpha))
		draw_arc(_phase_two_impact_position, impact_radius, 0, TAU, 72, Color(1.0,0.91,0.59,impact_alpha), 9.0*(1.0-impact_progress*0.55), true)
		draw_arc(_phase_two_impact_position, impact_radius*0.78, 0, TAU, 64, Color(1.0,0.3,0.08,impact_alpha*0.9), 3.0, true)
		for i in 8:
			var angle := TAU*float(i)/8.0+0.18
			var direction := Vector2.from_angle(angle)
			draw_line(_phase_two_impact_position+direction*24, _phase_two_impact_position+direction*(impact_radius*0.86), Color(0.28,0.12,0.07,impact_alpha), 4.0, true)
	if _phase_two_attack_time < 0.0 or hp <= 0:
		return
	var move := _phase_two_attack_index
	var cue: float = MOVE_WINDUP[move]+MOVE_CUE[move]
	var time := _phase_two_attack_time
	var progress := clampf(time/cue,0.0,1.0) if cue > 0.0 else 1.0
	var active := time >= cue
	var fade := clampf(1.0-(time-cue)/0.4,0.0,1.0) if active else 1.0
	var ink := Color("fff1bc") if active else Color("ffc66e")
	ink.a = fade*(0.95 if _phase_two_locked else 0.65)
	if move == 6:
		ink = Color(0.55,0.96,0.74,fade*0.9)
	var fill := Color(ink,0.1*fade)
	var origin := _phase_two_origin
	var aim := _phase_two_aim
	var direction := _phase_two_direction
	match move:
		0:
			# Sector is coverage, rays are the actual spear trajectories.
			var reach := arena_radius*1.6+45.0
			_sector(origin,direction,reach,FAN_HALF_ANGLE,fill,ink,progress)
			for i in FAN_COUNT:
				var ray := _fan_direction(i)
				_arrow(origin+ray*45.0,origin+ray*reach,Color(ink,ink.a*0.7),2.0)
		1:
			var start := _phase_two_bash_start if _phase_two_attack_done else origin
			var beat := fmod(maxf(time-MOVE_WINDUP[1],0.0),0.56)
			if _phase_two_attack_done:
				ink = Color("fff1bc") if beat >= 0.22 and beat < 0.46 else Color("ffc66e")
				ink.a = 0.9 if time < MOVE_WINDUP[1]+1.58 else 0.0
				fill = Color(ink,ink.a*0.1)
			var end := _constrain_boss_position(start.move_toward(aim,81.6))
			_capsule(start,end,DASH_HIT_RADIUS,fill,ink)
			_arrow(start,end,ink,3.0)
		2:
			_sector(origin,direction,SWEEP_RADIUS,SWEEP_HALF_ANGLE,fill,ink,progress)
			if active and fade > 0.0:
				# A bright moving blade arc, not an inert warning rectangle.
				var angle := direction.angle()+lerpf(-SWEEP_HALF_ANGLE,SWEEP_HALF_ANGLE,1.0-fade)
				var blade := Vector2.from_angle(angle)
				draw_line(origin+blade*35.0,origin+blade*SWEEP_RADIUS,Color(1,0.96,0.79,fade),12.0,true)
				draw_arc(origin,SWEEP_RADIUS*0.88,angle-0.3,angle,16,Color(0.83,0.56,1,fade),18.0,true)
		3:
			if not active:
				draw_circle(aim,SLAM_RADIUS,fill)
				draw_arc(aim,SLAM_RADIUS,0,TAU,80,ink,3.0,true)
				draw_arc(aim,SLAM_RADIUS*(1.7-progress*0.7),0,TAU,80,Color(ink,ink.a*0.7),2.0,true)
				for i in 4:
					var ray := Vector2.from_angle(PI*0.5*i)
					_arrow(aim+ray*(SLAM_RADIUS+18),aim+ray*(SLAM_RADIUS-8),ink,3.0)
		4:
			var end := _constrain_boss_position(origin+direction*175.0)
			_capsule(origin,end,BASH_HIT_RADIUS,fill,ink)
			_arrow(origin,end,ink,4.0)
		5:
			var start := origin+direction*45.0
			_capsule(start,start+direction*arena_radius*1.8,12.0,fill,ink)
			_arrow(start,start+direction*minf(arena_radius*1.8,300.0),ink,3.0)
		6:
			var center := _constrain_boss_position(origin.lerp(aim,0.56))
			var side := direction.orthogonal()*44.0
			var depth := direction*12.0
			var points := PackedVector2Array([center-side-depth,center+side-depth,center+side+depth,center-side+depth,center-side-depth])
			draw_polyline(points,ink,3.0,true)
			draw_line(center-side*0.45,center+side*0.45,ink,3.0,true)
	# One progress tick-ring at the source. It fills, then disappears on release.
	if not active and move != 3:
		draw_arc(origin,44.0,-PI*0.5,-PI*0.5+TAU*progress,48,ink,3.0,true)

func _arrow(start: Vector2, end: Vector2, ink: Color, width: float) -> void:
	if ink.a <= 0.0 or start.distance_squared_to(end) < 1.0:
		return
	var direction := (end-start).normalized()
	var side := direction.orthogonal()*7.0
	draw_line(start,end,ink,width,true)
	draw_polyline(PackedVector2Array([end-direction*14.0+side,end,end-direction*14.0-side]),ink,width,true)

func _sector(origin: Vector2, direction: Vector2, radius: float, half_angle: float, fill: Color, ink: Color, progress: float) -> void:
	if ink.a <= 0.0:
		return
	var angle := direction.angle()
	var points := PackedVector2Array([origin])
	for i in 49:
		points.append(origin+Vector2.from_angle(angle-half_angle+half_angle*2.0*float(i)/48.0)*radius)
	draw_colored_polygon(points,fill)
	draw_arc(origin,radius,angle-half_angle,angle+half_angle,64,ink,3.0,true)
	for edge in [-half_angle,half_angle]:
		var ray := Vector2.from_angle(angle+edge)
		draw_line(origin,origin+ray*radius,ink,2.0,true)
	draw_arc(origin,radius*progress,angle-half_angle,angle+half_angle,48,Color(ink,ink.a*0.45),2.0,true)

func _capsule(start: Vector2, end: Vector2, radius: float, fill: Color, ink: Color) -> void:
	if ink.a <= 0.0:
		return
	var direction := (end-start).normalized()
	if direction.is_zero_approx():
		direction = Vector2.DOWN
	var points := PackedVector2Array()
	var angle := direction.angle()
	for i in 25:
		points.append(end+Vector2.from_angle(angle-PI*0.5+PI*float(i)/24.0)*radius)
	for i in 25:
		points.append(start+Vector2.from_angle(angle+PI*0.5+PI*float(i)/24.0)*radius)
	draw_colored_polygon(points,fill)
	points.append(points[0])
	draw_polyline(points,ink,2.0,true)
