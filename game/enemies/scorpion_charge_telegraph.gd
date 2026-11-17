extends Node2D
## Scorpion-only visual consumer. Geometry and progress come from the owner;
## no visual clock can advance a gameplay state or alter hit dimensions.
const MATERIAL := preload("res://game/enemies/scorpion_charge_telegraph.gdshader")
var enemy: EnemyScorpion
var lane_length := 248.0
var lane_width := 48.0

func _ready() -> void:
	enemy = get_parent() as EnemyScorpion
	z_index = 0
	show_behind_parent = true
	var ink := ShaderMaterial.new()
	ink.shader = MATERIAL
	material = ink
	visible = false

func _process(_delta: float) -> void:
	var lane := enemy.charge_warning() if is_instance_valid(enemy) else {}
	visible = not lane.is_empty()
	if not visible: return
	global_position = lane.origin
	global_rotation = lane.direction.angle()
	lane_length = lane.length
	lane_width = lane.width
	var ink := material as ShaderMaterial
	ink.set_shader_parameter("lane_size",Vector2(lane_length,lane_width))
	ink.set_shader_parameter("progress",lane.progress)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(0,-lane_width/2.0,lane_length,lane_width),Color.WHITE)
