extends CharacterBody2D
class_name Player
## gangU player controller (#2).
## WASD movement + cursor aim. Manual aim only, no aim assist.
## Consumes shared input actions from project.godot:
## move_up/move_down/move_left/move_right (WASD).

signal died()
signal health_changed(current: int, max_hp: int)

@export var speed: float = 320.0
@export var max_hp: int = 100
@export var can_swim: bool = true

var terrain: TerrainMap = null

var hp: int
var damage_modifiers := DamageModifiers.new()
var damage_rng := RandomNumberGenerator.new()

## #205: spell-triggered invincibility window. Default OFF. Future spell code
## opens and closes it with set_invulnerable() around the spell phases that
## grant iframes. Taking a hit never opens it. No durations live here: each
## spell owns its own timing.
var _invulnerable := false

## #137: wizard sprite facing state. The 8-way movement vector collapses to
## 4-way facing on the dominant axis (exact diagonals resolve vertically) and
## the last facing is retained while idle. Down is the at-rest facing.
var facing: StringName = &"down"

@onready var aim_indicator: Node2D = $AimIndicator
@onready var body: Polygon2D = $Body
@onready var nose_edge: Polygon2D = $NoseEdge
## #137: AnimatedSprite2D wizard, added by main.tscn's Player subtree. Null in
## bare player.tscn instances (test arenas), which keep the legacy Body dart.
@onready var sprite: AnimatedSprite2D = get_node_or_null("WizardSprite")

func _ready() -> void:
	hp = max_hp
	damage_rng.randomize()
	if sprite != null:
		# Legacy dart hull + its nose accent both retire when the wizard art
		# carries the player visual; the AimIndicator is aim, not hull, and
		# stays. Bare player.tscn instances keep all three legacy visuals.
		body.visible = false
		nose_edge.visible = false
		_update_sprite(false)

## #5 contract: single damage entry point. Clamps HP at 0 and emits
## health_changed ONLY from inside here, so HP can never change silently.
func apply_damage(amount: int) -> void:
	if _invulnerable:
		# #205: window open - ignore the hit entirely (no HP change, no
		# health_changed, no died).
		return
	if hp <= 0:
		return
	hp = clampi(hp - amount, 0, max_hp)
	health_changed.emit(hp, max_hp)
	if hp == 0:
		died.emit()


## #205: open (true) or close (false) the spell-triggered invincibility window.
## Called by future spell code for specific spell phases.
func set_invulnerable(active: bool) -> void:
	_invulnerable = active


func is_invulnerable() -> bool:
	return _invulnerable


## #12 contract: single heal entry point. Clamps at max_hp and emits
## health_changed ONLY from inside here, mirroring apply_damage, so HP can
## never change silently. Works from hp == 0 (revive path); died() has already
## fired by then and the HUD recovers via health_changed.
func heal(amount: int) -> void:
	hp = clampi(hp + amount, 0, max_hp)
	health_changed.emit(hp, max_hp)

func _physics_process(delta: float) -> void:
	if hp <= 0:
		velocity = Vector2.ZERO
		return
	var input_dir := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	velocity = TerrainMotion.resolve(terrain, global_position, velocity, input_dir * speed, delta, can_swim)
	move_and_slide()
	if sprite != null:
		if input_dir != Vector2.ZERO:
			# 8-way -> 4-way: dominant axis wins, exact diagonals face vertically.
			if absf(input_dir.x) > absf(input_dir.y):
				facing = &"right" if input_dir.x > 0.0 else &"left"
			else:
				facing = &"down" if input_dir.y > 0.0 else &"up"
		_update_sprite(input_dir != Vector2.ZERO)

func _process(_delta: float) -> void:
	# Face the mouse cursor; manual aim only.
	var aim_dir := global_position.direction_to(get_global_mouse_position())
	if aim_dir.length_squared() > 0.0:
		rotation = aim_dir.angle()
	if sprite != null:
		# Aim rotation stays on the player node (cast/aim contract, #137):
		# the wizard art itself must stay upright - its facing comes from
		# directional animation frames, not node rotation.
		sprite.global_rotation = 0.0

## #137: drive idle_<dir>/walk_<dir> from the retained facing + movement.
func _update_sprite(walking: bool) -> void:
	var prefix := "walk_" if walking else "idle_"
	var anim := StringName(prefix + String(facing))
	if sprite.animation != anim or not sprite.is_playing():
		sprite.play(anim)
