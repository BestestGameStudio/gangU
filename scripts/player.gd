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

## #198: Shift dash. A short burst along the held WASD direction (or the last
## movement direction when standing still). Terrain rules still apply because
## the dash velocity goes through TerrainMotion.resolve like walking does.
## No stamina cost and no iframes (the issue left both open).
signal dash_started(direction: Vector2)
signal dash_ended()

@export var dash_speed: float = 900.0
@export var dash_duration: float = 0.15
@export var dash_cooldown: float = 0.6

var _dash_time_left := 0.0
var _dash_cooldown_left := 0.0
var _dash_dir := Vector2.DOWN
var _last_move_dir := Vector2.DOWN

var terrain: TerrainMap = null

var hp: int
var damage_modifiers := DamageModifiers.new()
var damage_rng := RandomNumberGenerator.new()

## #268: run-scoped stat modifiers (HP, damage amp, armor, move speed,
## cooldown reduction). Formulas, caps and expiry live in player_stats.gd.
## `max_hp` stays the EFFECTIVE max (HUD, clamps); `base_max_hp` is the
## unmodified value captured from the export at _ready. `speed` stays the
## base move speed; read the modified value with move_speed().
var stats := PlayerStats.new()
var base_max_hp: int
## Damage amp and armor reach DamageCalc through these two entries in
## damage_modifiers; they are present only while the stat is non-zero.
var _amp_bridge := DamageModifier.amp(0.0)
var _armor_bridge := DamageModifier.reduction(0.0)

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
	base_max_hp = max_hp
	hp = max_hp
	damage_rng.randomize()
	# #290: players never physically block or push enemies. The "players"
	# group is collision-only (targeting still uses explicit wiring / the
	# legacy "player" group); deferred so same-frame enemies are registered.
	add_to_group(ActorCollision.PLAYER_GROUP)
	ActorCollision.ignore_group.call_deferred(self, ActorCollision.ENEMY_GROUP)
	stats.changed.connect(_on_stat_changed)
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

## #268: final stat values (modifiers applied, caps enforced).
func move_speed() -> float:
	return stats.value(PlayerStats.MOVE_SPEED, speed)

func damage_amp() -> float:
	return stats.value(PlayerStats.DAMAGE_AMP, 0.0)

func armor() -> float:
	return stats.value(PlayerStats.ARMOR, 0.0)

func cooldown_reduction() -> float:
	return stats.value(PlayerStats.COOLDOWN_REDUCTION, 0.0)

## Spell cooldown after cooldown reduction. Applied when a cast STARTS a
## cooldown; cooldowns already running keep their length.
func effective_cooldown(base: float) -> float:
	return maxf(base * (1.0 - cooldown_reduction()), 0.0)


func _on_stat_changed(stat: StringName) -> void:
	match stat:
		PlayerStats.MAX_HP:
			_refresh_max_hp()
		PlayerStats.DAMAGE_AMP:
			_sync_bridge(_amp_bridge, damage_amp())
		PlayerStats.ARMOR:
			_sync_bridge(_armor_bridge, armor())


## #268 max HP rule: raising max HP also heals by the same amount (so a
## "+max HP on kill" spell is felt at once); lowering it only clamps HP down
## and never kills. A dead player gets no HP from a max HP change.
func _refresh_max_hp() -> void:
	var new_max := maxi(roundi(stats.value(PlayerStats.MAX_HP, base_max_hp)), 1)
	if new_max == max_hp:
		return
	var gained := new_max - max_hp
	max_hp = new_max
	if hp > 0:
		hp = clampi(hp + maxi(gained, 0), 1, max_hp)
	health_changed.emit(hp, max_hp)


func _sync_bridge(bridge: DamageModifier, amount: float) -> void:
	bridge.amount = amount
	var present := damage_modifiers.items().has(bridge)
	if amount != 0.0 and not present:
		damage_modifiers.add(bridge)
	elif amount == 0.0 and present:
		damage_modifiers.remove(bridge)


func _physics_process(delta: float) -> void:
	stats.tick(delta)
	if hp <= 0:
		velocity = Vector2.ZERO
		if _dash_time_left > 0.0:
			_dash_time_left = 0.0
			_end_dash()
		return
	var input_dir := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if input_dir != Vector2.ZERO:
		_last_move_dir = input_dir.normalized()
	_dash_cooldown_left = maxf(_dash_cooldown_left - delta, 0.0)
	if Input.is_action_just_pressed(&"dash"):
		try_dash(input_dir)
	var desired := input_dir * move_speed()
	if _dash_time_left > 0.0:
		desired = _dash_dir * dash_speed
		_dash_time_left = maxf(_dash_time_left - delta, 0.0)
		_spawn_dash_ghost()
		if _dash_time_left == 0.0:
			_end_dash()
	velocity = TerrainMotion.resolve(terrain, global_position, velocity, desired, delta, can_swim)
	move_and_slide()
	if sprite != null:
		if input_dir != Vector2.ZERO:
			# 8-way -> 4-way: dominant axis wins, exact diagonals face vertically.
			if absf(input_dir.x) > absf(input_dir.y):
				facing = &"right" if input_dir.x > 0.0 else &"left"
			else:
				facing = &"down" if input_dir.y > 0.0 else &"up"
		_update_sprite(input_dir != Vector2.ZERO or is_dashing())

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

## #198: start a dash if not dead, not already dashing and off cooldown.
## `input_dir` zero falls back to the last movement direction. Returns whether
## a dash started.
func try_dash(input_dir: Vector2 = Vector2.ZERO) -> bool:
	if hp <= 0 or _dash_time_left > 0.0 or _dash_cooldown_left > 0.0:
		return false
	_dash_dir = input_dir.normalized() if input_dir != Vector2.ZERO else _last_move_dir
	_dash_time_left = dash_duration
	_dash_cooldown_left = dash_cooldown
	if sprite != null:
		sprite.modulate = Color(0.75, 0.9, 1.6)
	dash_started.emit(_dash_dir)
	return true


func is_dashing() -> bool:
	return _dash_time_left > 0.0


func dash_cooldown_remaining() -> float:
	return _dash_cooldown_left


func _end_dash() -> void:
	if sprite != null:
		sprite.modulate = Color.WHITE
	dash_ended.emit()


## Afterimage trail: a fading copy of the current wizard frame left behind each
## physics frame of the dash. Skipped for bare player.tscn (no sprite).
func _spawn_dash_ghost() -> void:
	if sprite == null or sprite.sprite_frames == null or get_parent() == null:
		return
	var tex := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if tex == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = tex
	ghost.centered = sprite.centered
	ghost.offset = sprite.offset
	ghost.flip_h = sprite.flip_h
	ghost.texture_filter = sprite.texture_filter
	ghost.global_transform = sprite.global_transform
	ghost.modulate = Color(0.55, 0.8, 1.0, 0.6)
	ghost.z_index = z_index - 1
	get_parent().add_child(ghost)
	var tween := ghost.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, 0.25)
	tween.tween_callback(ghost.queue_free)


## #137: drive idle_<dir>/walk_<dir> from the retained facing + movement.
func _update_sprite(walking: bool) -> void:
	var prefix := "walk_" if walking else "idle_"
	var anim := StringName(prefix + String(facing))
	if sprite.animation != anim or not sprite.is_playing():
		sprite.play(anim)
