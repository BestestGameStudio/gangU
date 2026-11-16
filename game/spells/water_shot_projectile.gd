class_name WaterShotProjectile
extends Projectile
## Hover state belongs to each shot; base Water Shot uses normal Projectile redirect.
var hover_target := Vector2.ZERO
var hovering := false
var released := false
var hover_age := 0.0
var _hover_order := 0
static var _next_order := 0

func prepare_shape() -> void:
	# Match the shared projectile scene without making changes to other projectiles.
	var dart := Polygon2D.new(); dart.name = "Dart"; add_child(dart)
	var visual := Polygon2D.new(); visual.name = "Visual"; add_child(visual)
	var shape := CollisionShape2D.new(); shape.name = "CollisionShape2D"
	shape.shape = CircleShape2D.new(); add_child(shape)

func _physics_process(delta: float) -> void:
	if hovering:
		if freeze.is_frozen(): return
		hover_age += delta
		_life_t += delta
		if spell.water_shot_hover_duration > 0.0 and hover_age >= spell.water_shot_hover_duration:
			queue_free(); return
		# Native body_entered handles contact; sweep also catches bodies already overlapping.
		_sweep_segment(global_position, Vector2.ZERO)
		return
	if not released or spell.water_shot_repeat_redirect:
		var distance := global_position.distance_to(hover_target)
		if distance <= 0.1:
			_enter_hover(); return
		direction = global_position.direction_to(hover_target)
		rotation = direction.angle()
		var travel_delta := minf(delta, distance / maxf(spell.projectile_speed, 0.001))
		super._physics_process(travel_delta)
		if not is_queued_for_deletion() and global_position.distance_to(hover_target) <= 0.1:
			_enter_hover()
	else:
		super._physics_process(delta)

func _enter_hover() -> void:
	hovering = true
	hover_age = 0.0
	_next_order += 1; _hover_order = _next_order
	var others: Array[WaterShotProjectile] = []
	for node in get_tree().get_nodes_in_group(&"projectiles"):
		if node is WaterShotProjectile and node.source == source and node.spell == spell and node.hovering and not node.is_queued_for_deletion():
			others.append(node)
	others.sort_custom(func(a, b): return a._hover_order < b._hover_order)
	while others.size() > spell.water_shot_hover_cap:
		others.pop_front().queue_free()

func release_toward(target: Vector2) -> bool:
	if not hovering and not (released and spell.water_shot_repeat_redirect): return false
	var d := target - global_position
	if d.length_squared() < 0.01: return false
	direction = d.normalized(); rotation = direction.angle()
	if spell.water_shot_repeat_redirect:
		hover_target = global_position + d.limit_length(maxf(spell.range - 1.0, 0.0))
	if hovering: _traveled = 0.0
	hovering = false; released = true
	return true
