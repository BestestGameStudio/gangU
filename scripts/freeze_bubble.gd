class_name FreezeBubble
extends Area2D
## Spirit Punch Signature tier: an expanding bubble at a fixed radius that
## greyscales everything inside it. Only the player can move; enemies,
## summons and projectiles (existing and newly spawned) are frozen for the
## duration, then released.
##
## Owner decision (#305): the bubble stays ANCHORED where it was cast.
##
## Freeze contract: any body or area inside the bubble that implements
## set_frozen(frozen: bool) is frozen while inside and unfrozen on exit or
## when the bubble ends. The player (ActorCollision.PLAYER_GROUP) is never
## frozen. Actors without set_frozen are unaffected.

signal ended

const GREYSCALE_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

void fragment() {
	vec2 c = UV - vec2(0.5);
	float d = length(c);
	vec4 s = texture(screen_tex, SCREEN_UV);
	float g = dot(s.rgb, vec3(0.299, 0.587, 0.114));
	float m = 1.0 - smoothstep(0.48, 0.5, d);
	// Slight darkening inside + a pale rim at the boundary so the bubble
	// edge stays readable on already-grey floors.
	float rim = smoothstep(0.42, 0.485, d) * (1.0 - smoothstep(0.485, 0.5, d));
	vec3 col = mix(vec3(g) * 0.7, vec3(0.95), rim * 0.85);
	// Screen-texture alpha is unreliable (often 0); carry our own mask.
	COLOR = vec4(col, m);
}
"""

@export var radius := 220.0
## Freeze duration in seconds. Owner decision: 5s.
@export var duration := 5.0
@export var expand_time := 0.25
@export var fade_time := 0.3

var _frozen: Array[Node] = []
var _elapsed := 0.0
var _shape: CircleShape2D
var _collision: CollisionShape2D
var _visual: ColorRect
var _back_buffer: BackBufferCopy
var _releasing := false


static func spawn(parent: Node, anchor: Vector2, p_radius: float, p_duration: float) -> FreezeBubble:
	var bubble := FreezeBubble.new()
	bubble.radius = p_radius
	bubble.duration = p_duration
	parent.add_child(bubble)
	bubble.global_position = anchor
	return bubble


func _ready() -> void:
	add_to_group(&"freeze_bubbles")
	_collision = CollisionShape2D.new()
	_shape = CircleShape2D.new()
	_shape.radius = 0.0
	_collision.shape = _shape
	add_child(_collision)

	_back_buffer = BackBufferCopy.new()
	# VIEWPORT mode: rect-mode copies sample uninitialised (black) outside
	# their rect under the Compatibility renderer.
	_back_buffer.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	# Above every actor (default z 0): entities spawned AFTER the bubble
	# must also draw under the veil, or they stay in color inside the rim.
	_back_buffer.z_index = 100
	add_child(_back_buffer)

	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = GREYSCALE_SHADER
	mat.shader = shader
	_visual = ColorRect.new()
	_visual.material = mat
	_visual.size = Vector2(radius * 2.0, radius * 2.0)
	_visual.position = Vector2(-radius, -radius)
	_visual.scale = Vector2.ZERO
	_visual.pivot_offset = Vector2(radius, radius)
	_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visual.z_index = 100
	add_child(_visual)

	body_entered.connect(_on_node_entered)
	area_entered.connect(_on_node_entered)
	body_exited.connect(_on_node_exited)
	area_exited.connect(_on_node_exited)


func _physics_process(delta: float) -> void:
	_elapsed += delta
	var active_elapsed := _elapsed

	if active_elapsed < expand_time:
		var t := active_elapsed / expand_time
		_shape.radius = radius * t
		_visual.scale = Vector2(t, t)
	elif not _releasing:
		_shape.radius = radius
		_visual.scale = Vector2.ONE
		if active_elapsed >= expand_time + duration:
			_begin_release()

	if not _releasing:
		# Catch actors spawned inside the bubble between signal ticks
		# (e.g. deferred projectile volleys).
		for body in get_overlapping_bodies():
			_try_freeze(body)
		for area in get_overlapping_areas():
			_try_freeze(area)


func _begin_release() -> void:
	_releasing = true
	monitoring = false
	monitorable = false
	for node in _frozen:
		if is_instance_valid(node):
			node.set_frozen(false)
	_frozen.clear()
	var tween := create_tween()
	tween.tween_property(_visual, "modulate:a", 0.0, fade_time)
	tween.tween_callback(_finish)


func _finish() -> void:
	ended.emit()
	queue_free()


func is_frozen_actor(node: Node) -> bool:
	return _frozen.has(node)


## Spawn hook (#305): a newly spawned actor inside my CURRENT radius asks
## to be claimed. Area2D overlap registration lags up to a physics frame,
## so the scan/signal path alone can miss a body spawned mid-frame; this
## closes the gap. Once-per-pair: _try_freeze already tracks held nodes.
func claim(node: Node) -> void:
	if _releasing:
		return
	if node is Node2D and global_position.distance_to(node.global_position) <= _shape.radius:
		_try_freeze(node)


func _on_node_entered(node: Node) -> void:
	if _releasing:
		return
	_try_freeze(node)


func _on_node_exited(node: Node) -> void:
	_unfreeze(node)


func _try_freeze(node: Node) -> void:
	if node.is_in_group(ActorCollision.PLAYER_GROUP):
		return
	if not node.has_method(&"set_frozen"):
		return
	if _frozen.has(node):
		return
	_frozen.append(node)
	node.set_frozen(true)
	node.tree_exiting.connect(_on_frozen_tree_exiting.bind(node), CONNECT_ONE_SHOT)


func _unfreeze(node: Node) -> void:
	if not _frozen.has(node):
		return
	_frozen.erase(node)
	if is_instance_valid(node):
		node.set_frozen(false)


func _on_frozen_tree_exiting(node: Node) -> void:
	_frozen.erase(node)
