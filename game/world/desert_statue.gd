class_name DesertStatue
extends Enemy

const BODY_RADIUS := 24.0
const STATUE_SHEET: Texture2D = preload("res://assets/sprites/sandstatues.png")

var arena: Node2D
var possessed := false
var broken := false
var destroyed_once := false
var absorbed := false
var flash := 0.0
var _sprite: Sprite2D

func _ready() -> void:
	collision_layer = PhysicsLayers.ENEMY
	collision_mask = 0
	add_to_group(&"enemies")
	_sprite = Sprite2D.new()
	_sprite.name = "StatueSprite"
	_sprite.texture = STATUE_SHEET
	_sprite.hframes = 4
	_sprite.vframes = 2
	_sprite.scale = Vector2(1.22, 1.22)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.z_index = -1
	add_child(_sprite)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = BODY_RADIUS
	shape.shape = circle
	add_child(shape)

func apply_damage_from(amount: int, projectile: Node, crit_tier: int = 0) -> void:
	var source: Variant = projectile.get(&"source")
	if is_instance_valid(source) and (source is Player or source is Summon):
		apply_damage(amount, crit_tier)

func apply_damage(amount: int, crit_tier: int = 0) -> void:
	if not broken:
		arena.damage_statue(self, amount, crit_tier)

func _process(delta: float) -> void:
	flash = maxf(flash - delta, 0.0)
	_update_sprite()
	_sprite.visible = not broken and not absorbed
	_sprite.modulate = Color(1.6,1.6,1.6,1.0) if flash > 0.0 else Color.WHITE
	# Destroyed stone is drawn as rubble and pulled into the arena centre as
	# soon as the statue breaks. Phase two can then simply absorb whatever
	# rubble remains instead of starting this animation for every statue.
	if broken and not absorbed:
		position = position.move_toward(Vector2.ZERO, delta * 250.0)
		scale = scale.move_toward(Vector2.ONE * 0.12, delta * 0.9)
		if position.length() < 8.0:
			absorbed = true
	queue_redraw()

func _draw() -> void:
	if absorbed:
		return
	draw_ellipse_shadow()
	if broken:
		for i in 5:
			var p := Vector2.from_angle(float(i) * 2.4) * (8.0 + i * 3.0)
			draw_rect(Rect2(p - Vector2(7, 5), Vector2(14, 10)), Color("82715a"))
		return
	if arena is DesertStatueArena and (arena as DesertStatueArena).state == DesertStatueArena.State.PHASE_TWO and (arena as DesertStatueArena).possessed == self:
		_draw_sand_shield()
	if hp < max_hp:
		draw_rect(Rect2(-22, 33, 44, 4), Color("3d3432"))
		draw_rect(Rect2(-22, 33, 44.0 * hp / max_hp, 4), Color("ba8161"))

func _update_sprite() -> void:
	if not is_instance_valid(_sprite):
		return
	var direction := Vector2.DOWN
	if arena is DesertStatueArena and is_instance_valid((arena as DesertStatueArena).player):
		direction = (arena as DesertStatueArena).player.global_position-global_position
	if direction.is_zero_approx():
		direction = Vector2.DOWN
	var angle := direction.angle()
	var frame := 0
	if angle >= -PI*0.25 and angle < PI*0.25:
		frame = 1 # right
	elif angle >= PI*0.25 and angle < PI*0.75:
		frame = 0 # toward
	elif angle >= -PI*0.75 and angle < -PI*0.25:
		frame = 3 # away
	else:
		frame = 2 # left
	_sprite.frame_coords = Vector2i(frame, 1 if possessed else 0)
	# Turn by switching to the closest cardinal pose. Keep the pixel art upright.
	_sprite.rotation = 0.0

func _draw_sand_shield() -> void:
	var general_arena := arena as DesertStatueArena
	if general_arena._phase_two_attack_index != 4:
		return
	var facing := general_arena._phase_two_bash_direction
	draw_set_transform(facing*34.0+Vector2(0,8), facing.angle(), Vector2.ONE)
	var shield := PackedVector2Array([Vector2(-15,-20),Vector2(8,-17),Vector2(20,-9),Vector2(19,10),Vector2(8,24),Vector2(-8,24),Vector2(-19,10),Vector2(-20,-9)])
	draw_colored_polygon(shield,Color("b86b35"))
	var shield_outline := PackedVector2Array([Vector2(-15,-20),Vector2(8,-17),Vector2(20,-9),Vector2(19,10),Vector2(8,24),Vector2(-8,24),Vector2(-19,10),Vector2(-20,-9),Vector2(-15,-20)])
	draw_polyline(shield_outline,Color("ffe3a0"),3.0,true)
	draw_line(Vector2(0,-12),Vector2(0,17),Color("f2c76f"),3.0,true)
	draw_set_transform(Vector2.ZERO)

func draw_ellipse_shadow() -> void:
	draw_set_transform(Vector2(0, 24), 0, Vector2(1, 0.35))
	draw_circle(Vector2.ZERO, 34, Color(0.22,0.16,0.1,0.24))
	draw_set_transform(Vector2.ZERO)

func _physics_process(_delta: float) -> void:
	velocity = Vector2.ZERO

func knockback(_push: Vector2) -> void:
	pass
