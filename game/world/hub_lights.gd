extends Node2D
## Hub-only presentation. No clock, interaction, collision or travel changes.
## Mood references: Royal Crypt's quiet open floor and Kibyra's warm lamps.
var _time := 0.0
var _portal_pool: Sprite2D
var _lamp_light: PointLight2D

func _ready() -> void:
	z_index = 1 # Draw the counter lantern above the shop sprite.
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.2, 0.55, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0.65),
		Color(1, 1, 1, 0.38), Color(1, 1, 1, 0.10), Color(1, 1, 1, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 256
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1, 0.5)
	_portal_pool = _pool(texture, Vector2(576, 272), Vector2(1.60, 0.80), 0.55)
	_pool(texture, Vector2(814, 596), Vector2(0.86, 0.44), 0.42)
	_lamp_light = PointLight2D.new()
	_lamp_light.position = Vector2(814, 556)
	_lamp_light.texture = texture
	_lamp_light.texture_scale = 0.9
	_lamp_light.color = Color("ffc078")
	_lamp_light.energy = 0.55
	_lamp_light.shadow_enabled = false
	add_child(_lamp_light)
	queue_redraw()

func _pool(texture: Texture2D, at: Vector2, spread: Vector2, alpha: float) -> Sprite2D:
	var pool := Sprite2D.new()
	pool.texture = texture
	pool.position = at
	pool.scale = spread
	pool.z_as_relative = false
	pool.z_index = -70 # Above brick, below every prop and actor.
	pool.modulate = Color(1.0, 0.52, 0.18, alpha)
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	pool.material = material
	add_child(pool)
	return pool

func _draw() -> void:
	# Small bronze lantern on the counter's left edge, behind no hitbox.
	var p := Vector2(814, 556)
	draw_rect(Rect2(p + Vector2(-6, -10), Vector2(12, 16)), Color("231f1b"))
	draw_rect(Rect2(p + Vector2(-4, -8), Vector2(8, 12)), Color("ae7439"))
	draw_rect(Rect2(p + Vector2(-2, -6), Vector2(4, 8)), Color("ffce83"))
	draw_rect(Rect2(p + Vector2(-6, -12), Vector2(12, 3)), Color("62513a"))
	draw_rect(Rect2(p + Vector2(-6, 5), Vector2(12, 3)), Color("62513a"))
	draw_arc(p + Vector2(0, -12), 4, PI, TAU, 8, Color("62513a"), 2)

func _process(delta: float) -> void:
	_time += delta
	var pulse := 1.0 + 0.025 * sin(_time * 2.0)
	_portal_pool.modulate.a = 0.55 * pulse
	_lamp_light.energy = 0.55 * (1.0 + 0.018 * sin(_time * 3.1))
