class_name DesertPossessionStar
extends Node2D

var arena: Node2D
var origin: DesertStatue
var destination: DesertStatue
var returning := false
var speed := 380.0
var contact_damage := 16
var _time := 0.0
var _touched := false
var _last_shots: Dictionary = {}
var _retarget_left := 0.0
var _broken_target_warned := false
var _trail: Array[Vector2] = []

func intercept() -> void:
	returning = true
	_retarget_left = 0.0

func _physics_process(delta: float) -> void:
	if not arena.visiting:
		return
	_time += delta
	var target := origin if returning else destination
	if not returning and target.broken and not _broken_target_warned:
		# A destroyed destination is not an interception. Keep the star outbound.
		var nearest := INF
		for statue: DesertStatue in arena.statues:
			if statue.broken or statue == origin:
				continue
			var distance := global_position.distance_squared_to(statue.global_position)
			if distance < nearest:
				nearest = distance
				destination = statue
		if nearest == INF and not origin.broken:
			destination = origin
		target = destination
		_broken_target_warned = destination.broken
		_retarget_left = arena.transfer_windup
	var paused := _retarget_left > 0
	_retarget_left = maxf(_retarget_left-delta,0.0)
	var step := 0.0 if paused else speed*delta
	var from := global_position
	var to := from.move_toward(target.global_position + Vector2(0,-20), step)
	if not returning:
		_check_interceptions(from, to)
	var player: Player = arena.player
	if not _touched and _distance_segment(player.global_position, from, to) < 29:
		_touched = true
		player.apply_damage(contact_damage)
		intercept()
	# Interception changes the destination immediately, including the last outbound step.
	target = origin if returning else destination
	if returning:
		step = speed*delta
	to = from.move_toward(target.global_position + Vector2(0,-20), step)
	global_position = to
	_trail.append(global_position)
	if _trail.size() > 12:
		_trail.pop_front()
	if global_position.distance_to(target.global_position + Vector2(0,-20)) < 2:
		arena.star_arrived(returning)
		queue_free()
	queue_redraw()

func _check_interceptions(from: Vector2, to: Vector2) -> void:
	for shield: WaterShield in get_tree().get_nodes_in_group(&"water_shields"):
		if shield.is_active() and _distance_segment(shield.global_position, from, to) < shield.radius + 12:
			intercept()
			return
	for shot: Projectile in get_tree().get_nodes_in_group(&"projectiles"):
		if shot.is_queued_for_deletion():
			continue
		if not is_instance_valid(shot.source) or not (shot.source is Player or shot.source is Summon):
			continue
		var old: Vector2 = _last_shots.get(shot.get_instance_id(), shot.global_position)
		_last_shots[shot.get_instance_id()] = shot.global_position
		var nearest := Geometry2D.get_closest_point_to_segment(shot.global_position, from, to)
		if _distance_segment(nearest, old, shot.global_position) < shot.visual_radius() + 14:
			if not shot.spell.tags.has(SpellTags.PIERCING):
				shot.queue_free()
			intercept()
			return
	var terrain: TerrainMap = arena.player.terrain
	if terrain != null:
		if terrain.projectile_block_t(from, to-from) >= 0.0 or not terrain.is_walkable_at_cell(terrain.world_to_cell(to)):
			intercept()

func _distance_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	return point.distance_to(Geometry2D.get_closest_point_to_segment(point,a,b))

func _draw() -> void:
	var color := Color("ad4dff")
	var target := origin if returning else destination
	if is_instance_valid(target):
		var end := to_local(target.global_position+Vector2(0,-20))
		draw_line(Vector2.ZERO,end,Color(0.7,0.3,1,0.5),0.8,true)
		if end.length() > 20:
			var direction := end.normalized()
			var side := direction.orthogonal()
			draw_polyline(PackedVector2Array([end-direction*8+side*3,end,end-direction*8-side*3]),Color("d9a5ff"),0.8,true)
	for i in range(1,_trail.size()):
		var strength := float(i)/_trail.size()
		draw_line(to_local(_trail[i-1]),to_local(_trail[i]),Color(0.69,0.35,1,strength*0.55),1+strength*4,true)
	var pulse := 1.0+sin(_time*8)*0.08
	draw_circle(Vector2.ZERO,40*pulse,Color(color,0.05))
	draw_circle(Vector2.ZERO,29*pulse,Color(color,0.12))
	draw_circle(Vector2.ZERO,20*pulse,Color(color,0.3))
	var points := PackedVector2Array()
	for i in 10:
		points.append(Vector2.from_angle(-PI/2+i*TAU/10+_time*2)*(15 if i%2 == 0 else 6))
	draw_colored_polygon(points,color)
	points.append(points[0])
	draw_polyline(points,Color("e2b8ff"),1.0,true)
	draw_circle(Vector2.ZERO,6,Color("f6e8ff"))
