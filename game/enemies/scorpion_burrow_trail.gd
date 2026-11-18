extends Node2D
## Visual-only source-exported settling wake. Positions stay in world space,
## sampled by ground travel, never rendering frame rate. All clocks freeze
## with their owner. No collision, target or damage behavior here.
const SHEET := preload("res://assets/sprites/scorpion_burrow_trail.png")
const LIFE := 0.6
const SPACING := 20.0
const MAX_STAMPS := 32
var enemy: EnemyScorpion
var stamps: Array[Dictionary] = []
var _last := Vector2.ZERO
var _carry := 0.0
var _active := false

func _ready() -> void:
	enemy = get_parent() as EnemyScorpion
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	show_behind_parent = true
	z_index = -1

func _physics_process(delta: float) -> void:
	if not is_instance_valid(enemy) or enemy.freeze.is_frozen(): return
	for stamp in stamps: stamp.age += delta
	while not stamps.is_empty() and stamps[0].age >= LIFE: stamps.pop_front()
	var pursuing := enemy._behavior is EnemyBehaviorScorpion and (enemy._behavior as EnemyBehaviorScorpion).state in [EnemyBehaviorScorpion.State.BURROW_RUSH,EnemyBehaviorScorpion.State.BURROW_PURSUIT]
	var now := enemy.global_position
	if pursuing:
		if not _active:
			_last = now
			_carry = 0.0
		var off := now-_last
		var distance := off.length()
		if distance > 0.001:
			var direction := off/distance
			# Never connect a teleport/reposition with a screen-wide trail.
			if distance <= 64.0:
				var along := SPACING-_carry
				while along <= distance:
					stamps.append({"point":_last+direction*along,"angle":direction.angle(),"age":0.0})
					if stamps.size() > MAX_STAMPS: stamps.pop_front()
					along += SPACING
				_carry = fmod(_carry+distance,SPACING)
			else: _carry = 0.0
		_last = now
	else: _carry = 0.0
	_active = pursuing
	visible = enemy.seen_by_player()
	queue_redraw()

func _draw() -> void:
	for stamp in stamps:
		var age: float = stamp.age
		var key := 0 if age < 0.12 else (1 if age < 0.27 else (2 if age < 0.45 else 3))
		draw_set_transform(to_local(stamp.point),stamp.angle)
		draw_texture_rect_region(SHEET,Rect2(-24,-19,48,32),Rect2(key*48,0,48,32),Color(1,1,1,1.0-age/LIFE))
	draw_set_transform(Vector2.ZERO)
