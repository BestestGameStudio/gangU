class_name EnemyStunHalo
extends AnimatedSprite2D
## Visual consumer only. Gameplay clocks and stun ownership stay on Enemy.
var enemy: Enemy
var _was_stunned := false

func _ready() -> void:
	enemy = get_parent() as Enemy
	sprite_frames = preload("res://data/sprites/stun_halo_frames.tres")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 5
	visible = false

func _process(_delta: float) -> void:
	var active := enemy != null and enemy.is_stunned()
	visible = active
	if active:
		if not _was_stunned:
			position = enemy.stun_halo_position()
			play(&"stun")
	elif _was_stunned:
		stop()
	_was_stunned = active
