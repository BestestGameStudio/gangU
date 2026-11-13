class_name DesertStatueArena
extends Node2D
## Sunbound Sanctum. Run-owned state persists until the normal death reset.
## Initial balance values are tunable placeholders.

enum State { DORMANT, POSSESSED, STUNNED, TRANSFERRING, PHASE_TWO }
var arena_radius := 0.0
var statue_radius := 0.0
var barrier_radius := 0.0
var player_limit_radius := 0.0
var activation_radius := 0.0
var _sized := false
@export var spear_radius := 5.5
@export var arena_diameter_screen_heights := 1.7
@export var boss_max_hp := 2400
@export var statue_max_hp := 90
@export var spear_damage := 10
## World-space screen widths per second at the unchanged normal zoom.
@export var spear_screen_speed := 1.15
@export var volley_interval := 1.0
@export var volley_delay := 1.0
@export var lane_delay_max := 0.2
@export var ray_growth_duration := 0.7
@export var vision_angle_degrees := 150.0
@export var vision_range_ring_fraction := 0.6
@export var stun_duration := 1.0
@export var transfer_speed := 380.0
@export var star_damage := 16
@export var phase_two_damage_per_statue := 0.08
@export var phase_two_speed_per_statue := 0.06
@export var phase_two_heal_per_statue := 16

var hp := 2400
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
var _ui: CanvasLayer
var _title: Label
var _details: Label
var _bar: ProgressBar
var _rng := RandomNumberGenerator.new()
const CombatEffects := preload("res://game/combat/combat_effects.gd")
const SPEAR_VISUAL := preload("res://game/world/desert_spear_visual.gd")
const PROJECTILE := preload("res://game/spells/projectile.tscn")

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
	_make_ui()

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
	# Direct scripted repositioning also remains on the inner side of the ring.
	player.global_position = constrain_player_position(player.global_position)
	if state == State.PHASE_TWO:
		_phase_time += delta
		for statue in statues:
			if statue.broken and not statue.absorbed:
				statue.position = statue.position.move_toward(Vector2.ZERO,delta*250)
				statue.scale = statue.scale.move_toward(Vector2.ONE*0.12,delta*0.9)
				if statue.position.length() < 8:
					statue.absorbed = true
	elif state == State.STUNNED:
		_stun_left -= delta
		if _stun_left <= 0:
			if _force_hop:
				begin_transfer.call_deferred()
			else:
				state = State.POSSESSED
	if state != State.PHASE_TWO:
		_advance_volleys(delta)
	_update_ui()
	queue_redraw()

func start_encounter() -> void:
	if state != State.DORMANT:
		return
	player.movement_constraint = Callable(self,"constrain_player_position")
	_possess(statues[_rng.randi_range(0,11)])

func is_active() -> bool:
	return state != State.DORMANT and is_instance_valid(player) and player.hp > 0

func constrain_player_position(destination: Vector2) -> Vector2:
	if not is_active() or not is_visible_in_tree():
		return destination
	var offset := destination-global_position
	return global_position+offset.limit_length(player_limit_radius)

func _exit_tree() -> void:
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

func damage_statue(statue: DesertStatue, amount: int, crit_tier: int) -> void:
	if not visiting or state == State.PHASE_TWO or state == State.DORMANT or amount <= 0:
		return
	statue.flash = 0.15
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
			statue.collision_layer = 0
			if not statue.destroyed_once:
				statue.destroyed_once = true
				broken_count += 1
	CombatEffects.damage_number(get_parent(),statue.global_position,amount,crit_tier)

func apply_damage(amount: int) -> void:
	hp = maxi(hp-maxi(amount,0),0)
	if hp <= boss_max_hp/2 and state != State.PHASE_TWO:
		_enter_phase_two()

func heal(amount: int) -> void:
	hp = mini(hp+maxi(amount,0),boss_max_hp)

func _stun(force_hop: bool) -> void:
	_hit_stun_used = true
	state = State.STUNNED
	_stun_left = stun_duration
	_force_hop = force_hop

func begin_transfer() -> void:
	if state == State.PHASE_TWO or state == State.TRANSFERRING or (state == State.STUNNED and _stun_left > 0) or not visiting:
		return
	var choices: Array[DesertStatue] = []
	for statue in statues:
		if not statue.broken and statue != possessed:
			choices.append(statue)
	if choices.is_empty():
		_possess(possessed)
		return
	state = State.TRANSFERRING
	star = DesertPossessionStar.new()
	star.arena = self
	star.origin = possessed
	star.destination = choices.pick_random()
	star.speed = transfer_speed
	star.contact_damage = star_damage
	star.position = possessed.position+Vector2(0,-20)
	possessed.possessed = false
	possessed = null
	star.z_index = 15
	add_child(star)

func star_arrived(returned: bool) -> void:
	if state != State.TRANSFERRING or not is_instance_valid(star):
		return
	var host: DesertStatue = star.origin if returned else star.destination
	# The star can rebuild its return host, or the last host if all statues broke.
	if host.broken:
		host.broken = false
		host.hp = host.max_hp
		host.collision_layer = PhysicsLayers.ENEMY
	_possess(host)
	if returned:
		_stun(false)
	star = null

func _cancel_star() -> void:
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
				if candidate != shooter and not candidate.broken:
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
			endpoint = target.position+Vector2(0,-20)
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
			draw_line(lane.start,tip,Color(0.3,0.04,0.03,0.2),3.5,true)
			draw_line(lane.start,tip,Color(0.95,0.12,0.12,0.65+fraction*0.3),1.5,true)
			if lane.start.distance_to(tip) < 20:
				continue
			var direction := (lane.end-lane.start).normalized()
			var side := direction.orthogonal()
			draw_polyline(PackedVector2Array([tip-direction*9+side*4.5,tip,tip-direction*9-side*4.5]),Color(1,0.35,0.25,0.9),1.5,true)

func _next_spear_delay() -> float:
	var remaining := INF
	for volley in _pending_volleys:
		for lane in volley.lanes:
			if not lane.finished and not lane.shooter.broken:
				remaining = minf(remaining,lane.fires_at-_attack_time)
	return maxf(remaining,0)

func _enter_phase_two() -> void:
	state = State.PHASE_TWO
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

func _update_ui() -> void:
	_bar.value = hp
	_title.text = "SUNBOUND SOVEREIGN  ·  %d / %d" % [hp,boss_max_hp]
	if state == State.PHASE_TWO:
		_title.text = "PHASE 2  ·  THE SOVEREIGN AWAKENS"
		_details.text = "%d absorbed  |  Damage +%d%%  |  Speed +%d%%  |  Recovered %d HP" % [broken_count,roundi((phase_two_damage_multiplier-1)*100),roundi((phase_two_speed_multiplier-1)*100),phase_two_recovered_hp]
	elif not _pending_volleys.is_empty():
		_details.text = "NEXT SPEARS IN %.1fs   |   Dodge the marked paths" % _next_spear_delay()
	elif state == State.STUNNED:
		_details.text = "POSSESSION STUNNED  ·  %.1fs   |   Broken statues: %d" % [_stun_left,broken_count]
	elif state == State.TRANSFERRING:
		_details.text = "INTERCEPT THE GOLDEN STAR   |   Broken statues: %d" % broken_count
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
	_circle(arena_radius-12,Color("d9be87"))
	for i in 650:
		var a := float(i)*2.399963
		var at := Vector2.from_angle(a)*sqrt(float(i)/650)*(arena_radius-15)
		draw_arc(at,8+i%12,0.2,1.6,8,Color(0.52,0.38,0.22,0.15),1)
	_circle(statue_radius,Color(0.59,0.39,0.2,0.35),2)
	for i in 12:
		var at := _ring_points[i]
		draw_circle(at,48,Color(0.65,0.48,0.27,0.25))
	_draw_volley()
	if state != State.DORMANT:
		var alpha := 0.65+sin(Time.get_ticks_msec()*0.003)*0.15
		_circle(barrier_radius,Color(1,0.79,0.3,alpha),4)
		_circle(barrier_radius-4,Color(1,0.86,0.49,0.2),8)
	if state == State.PHASE_TWO:
		var pulse := 55+sin(_phase_time*3)*5
		draw_circle(Vector2.ZERO,pulse,Color(0.9,0.6,0.15,0.2))
		draw_arc(Vector2.ZERO,pulse,0,TAU,64,Color("ffd274"),3)
		draw_string(ThemeDB.fallback_font,Vector2(-53,6),"PHASE 2",HORIZONTAL_ALIGNMENT_LEFT,-1,24,Color("fff0c4"))
	if state == State.DORMANT:
		draw_string(ThemeDB.fallback_font,Vector2(-arena_radius+80,-35),"SUNBOUND SANCTUM",HORIZONTAL_ALIGNMENT_LEFT,-1,23,Color("ffe7b4"))
		draw_string(ThemeDB.fallback_font,Vector2(-arena_radius+80,-10),"Walk east to the central seal",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("fff1d5"))
		draw_arc(Vector2.ZERO,activation_radius,0,TAU,80,Color(0.94,0.77,0.4,0.6),2)
		draw_string(ThemeDB.fallback_font,Vector2(-140,58),"SUNBOUND SANCTUM",HORIZONTAL_ALIGNMENT_LEFT,-1,23,Color("ffe7b4"))
		draw_string(ThemeDB.fallback_font,Vector2(-126,82),"Approach the seal to challenge",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("fff1d5"))
