class_name DesertStatue
extends Enemy

const BODY_RADIUS := 24.0

var arena: Node2D
var possessed := false
var broken := false
var destroyed_once := false
var absorbed := false
var flash := 0.0

func _ready() -> void:
	collision_layer = PhysicsLayers.ENEMY
	collision_mask = 0
	add_to_group(&"enemies")
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
	var stone := Color("c1ad86") if flash <= 0 else Color("ffffff")
	draw_style_box(_box(Color("665743")), Rect2(-26, 16, 52, 12))
	draw_style_box(_box(stone.darkened(0.15)), Rect2(-20, -15, 40, 35))
	draw_style_box(_box(stone), Rect2(-23, -42, 46, 34))
	draw_rect(Rect2(-26, -43, 52, 7), Color("65523b"))
	draw_rect(Rect2(-14, -30, 9, 5), Color("312d31"))
	draw_rect(Rect2(5, -30, 9, 5), Color("312d31"))
	draw_rect(Rect2(-9, -16, 18, 4), Color("65523b"))
	var phase_two := arena is DesertStatueArena and (arena as DesertStatueArena).state == DesertStatueArena.State.PHASE_TWO
	if possessed and not phase_two:
		draw_circle(Vector2(-9, -28), 7, Color(0.64,0.2,1,0.28))
		draw_circle(Vector2(9, -28), 7, Color(0.64,0.2,1,0.28))
		draw_circle(Vector2(-9, -28), 4, Color("bb66ff"))
		draw_circle(Vector2(9, -28), 4, Color("bb66ff"))
	elif hp < max_hp:
		draw_rect(Rect2(-22, 33, 44, 4), Color("3d3432"))
		draw_rect(Rect2(-22, 33, 44.0 * hp / max_hp, 4), Color("ba8161"))

func draw_ellipse_shadow() -> void:
	draw_set_transform(Vector2(0, 24), 0, Vector2(1, 0.35))
	draw_circle(Vector2.ZERO, 34, Color(0.22,0.16,0.1,0.24))
	draw_set_transform(Vector2.ZERO)

func _box(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("594b3a")
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	return style

func _physics_process(_delta: float) -> void:
	velocity = Vector2.ZERO

func knockback(_push: Vector2) -> void:
	pass
