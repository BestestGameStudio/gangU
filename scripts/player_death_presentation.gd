class_name PlayerDeathPresentation
extends CanvasLayer
## #591: presentation only. RunManager owns revival, timing and the full reset.
## Created only AFTER the revive interception has declined the death.

const TITLE := "YOU DIED"
const TITLE_COLOR := Color(0.72, 0.15, 0.12)
var _elapsed := 0.0
var _duration := 1.5
var _veil: ColorRect
var _title: Label
var _rule_top: ColorRect
var _rule_bottom: ColorRect
var _corpse: DeathAsh
var _pose: Node2D
var _start_scale := Vector2.ONE

class DeathAsh extends Node2D:
	var progress := 0.0
	func _draw() -> void:
		var alpha := (1.0 - progress) * 0.65
		for i in 12:
			var a := float(i) * TAU / 12.0
			var at := Vector2(cos(a), sin(a)) * (5.0 + progress * 28.0)
			at.y -= progress * 14.0
			draw_rect(Rect2(at, Vector2(2, 2)), Color(0.55, 0.7, 0.82, alpha))

static func begin(host: Node, player: Player, duration: float) -> PlayerDeathPresentation:
	var effect := PlayerDeathPresentation.new()
	effect.name = "PlayerDeathPresentation"
	effect._duration = maxf(duration, 0.01)
	host.add_child(effect)
	effect._capture_pose(player)
	return effect

func _ready() -> void:
	layer = 90
	add_to_group(&"player_death_presentation")
	_veil = ColorRect.new()
	_veil.color = Color(0.025, 0.018, 0.025, 0.0)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_veil)
	_title = Label.new()
	_title.text = TITLE
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_color", TITLE_COLOR)
	_title.add_theme_color_override("font_outline_color", Color(0.025, 0.01, 0.01, 0.9))
	_title.add_theme_constant_override("outline_size", 3)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)
	_rule_top = _rule()
	_rule_bottom = _rule()
	_layout()
	get_viewport().size_changed.connect(_layout)
	_update_presentation()

func _rule() -> ColorRect:
	var line := ColorRect.new()
	line.color = TITLE_COLOR
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)
	return line

func _layout() -> void:
	var size := get_viewport().get_visible_rect().size
	_veil.size = size
	var font_size := clampi(roundi(size.x * 0.068), 36, 76)
	_title.add_theme_font_size_override("font_size", font_size)
	_title.position = Vector2(0, size.y * 0.5 - float(font_size) * 0.9)
	_title.size = Vector2(size.x, float(font_size) * 1.8)
	var width := minf(size.x * 0.42, 490.0)
	_rule_top.position = Vector2((size.x - width) * 0.5, size.y * 0.5 - font_size * 0.85)
	_rule_bottom.position = Vector2((size.x - width) * 0.5, size.y * 0.5 + font_size * 0.85)
	_rule_top.size = Vector2(width, 1)
	_rule_bottom.size = Vector2(width, 1)

func _capture_pose(player: Player) -> void:
	# A detached pose survives any hit flash or other player visual updates.
	# No collision, player transform, animation state or game clock is changed.
	_corpse = DeathAsh.new()
	player.get_parent().add_child(_corpse)
	_corpse.global_position = player.global_position
	if player.sprite != null:
		var image := Sprite2D.new()
		image.texture = player.sprite.sprite_frames.get_frame_texture(player.sprite.animation, player.sprite.frame)
		image.centered = player.sprite.centered
		image.offset = player.sprite.offset
		image.flip_h = player.sprite.flip_h
		image.texture_filter = player.sprite.texture_filter
		_corpse.add_child(image)
		image.global_transform = player.sprite.global_transform
		_pose = image
		player.sprite.hide()
	else:
		var shape := Polygon2D.new()
		shape.polygon = player.body.polygon
		shape.color = player.body.color
		_corpse.add_child(shape)
		shape.global_transform = player.body.global_transform
		_pose = shape
	player.body.hide()
	player.nose_edge.hide()
	player.aim_indicator.hide()
	_start_scale = _pose.scale

func _process(delta: float) -> void:
	_elapsed += delta
	_update_presentation()

func _update_presentation() -> void:
	var t := _elapsed / _duration * 1.5
	var collapse := smoothstep(0.0, 0.42, t)
	if is_instance_valid(_pose):
		_pose.rotation = collapse * 1.25
		_pose.scale = _start_scale * Vector2(1.0 - collapse * 0.12, 1.0 - collapse * 0.28)
		_pose.position.y = collapse * 8.0
		_pose.modulate = Color(0.7, 0.78, 0.86, 1.0 - smoothstep(0.35, 0.78, t))
	if is_instance_valid(_corpse):
		_corpse.progress = clampf(t / 0.8, 0.0, 1.0)
		_corpse.queue_redraw()
	_veil.color.a = lerpf(0.0, 0.76, smoothstep(0.08, 0.78, t))
	var title_alpha := smoothstep(0.32, 0.66, t)
	_title.modulate.a = title_alpha
	_rule_top.modulate.a = title_alpha * 0.45
	_rule_bottom.modulate.a = title_alpha * 0.45

func _exit_tree() -> void:
	if is_instance_valid(_corpse):
		_corpse.queue_free()
