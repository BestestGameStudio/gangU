extends CharacterBody2D
class_name Player
## gangU player controller (#2).
## WASD movement + cursor aim. Manual aim only, no aim assist.
## Consumes shared input actions from project.godot:
## move_up/move_down/move_left/move_right (WASD).

signal died()
signal health_changed(current: int, max_hp: int)
## #388: shields - temporary health beyond max HP. Emitted ONLY from
## add_shield / clear_shield / apply_damage / tick_shield_decay, so the pool
## never changes silently.
signal shield_changed(current: int)

@export var speed: float = 320.0
@export var max_hp: int = 100
@export var can_swim: bool = true

## #198: Shift dash. A short burst along the held WASD direction (or the last
## movement direction when standing still). Terrain rules still apply because
## the dash velocity goes through TerrainMotion.resolve like walking does.
## No stamina cost and no iframes (the issue left both open).
signal dash_started(direction: Vector2)
signal dash_ended()

## #305: spell launch (Mastery: the player is launched forward BEFORE
## attacking). Same contract shape as the dash: a started/ended pair, plus
## cancelled when death interrupts the launch so a pending attack is dropped.
signal launch_started(direction: Vector2)
signal launch_ended()
signal launch_cancelled()

## #450: dash range nerfed 40% (135 px -> 81 px) by shortening the duration
## only; speed and cooldown are unchanged. 900 x 0.09 = 81 px is the flat base
## dash distance that any future range scaling applies on top of.
@export var dash_speed: float = 900.0
@export var dash_duration: float = 0.09
## Seconds to recharge ONE dash charge. With the base single charge this is
## the classic #198 cooldown (counted from dash start).
@export var dash_cooldown: float = 0.6

## #426: dash CHARGES. The base is one charge; owned relics add more through
## the DASH_CHARGES_KEY scalar effect (the boss-drop Twin Dash relic adds
## one, so the player can dash twice). Charges recharge ONE AT A TIME, each
## taking dash_cooldown; a dash spent while a recharge is already running
## does not restart it. Provisional rule - the issue left recharge timing
## open, and this keeps the single-charge behavior exactly as before.
const BASE_DASH_CHARGES := 1
const DASH_CHARGES_KEY := &"dash_charges"

var _dash_time_left := 0.0
var _dash_charges := BASE_DASH_CHARGES
## Time left on the charge currently recharging (0 = none recharging).
var _dash_recharge_left := 0.0
var _dash_dir := Vector2.DOWN
var _last_move_dir := Vector2.DOWN

## #305: spell launch state. Speed/duration come from the casting Spell
## resource (provisional tunings), not from the dash exports above.
var _launch_dir := Vector2.DOWN
var _launch_speed := 0.0
var _launch_time_left := 0.0

var terrain: TerrainMap = null

var hp: int
## #388 foundation: shield pool, separate from hp/max_hp and uncapped. Takes
## damage before HP. Owner-clarified rules: no cap, grants stack additively,
## and the pool decays after a timer - it holds for shield_decay_delay
## seconds, then gradually drains at shield_decay_rate per second. Any new
## grant refreshes that single pooled delay clock; damage does not. It
## absorbs the FINAL damage amount (after armor/damage reduction), since
## apply_damage already receives post-modifier damage.
var shield: int = 0
## #388: seconds a shield holds before it starts to decay. Engineering
## placeholder, not owner-approved tuning; adjust freely.
@export var shield_decay_delay: float = 3.0
## #388: shield points drained per second once decay starts. Engineering
## placeholder, not owner-approved tuning; adjust freely.
@export var shield_decay_rate: float = 10.0
## Seconds left before decay starts; reset by every add_shield.
var _shield_delay_left := 0.0
## Fractional decay carried between frames so the int pool drains smoothly.
var _shield_decay_carry := 0.0
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
	# #388: the shield soaks the hit first; only the overflow reaches HP. A
	# fully absorbed hit leaves HP untouched and emits no health_changed.
	if shield > 0 and amount > 0:
		var absorbed := mini(shield, amount)
		shield -= absorbed
		amount -= absorbed
		shield_changed.emit(shield)
		if amount == 0:
			# #390: a shield-soaked hit is ACCEPTED (unlike #205 iframes,
			# which refuse the hit entirely): it lands with hp_lost 0, the
			# same shape as an accepted 0-damage roll.
			OnHit.record(self, hp, hp)
			return
	var before := hp
	hp = clampi(hp - amount, 0, max_hp)
	OnHit.record(self, before, hp) # #390: outcome captured before died()/revive
	health_changed.emit(hp, max_hp)
	if hp == 0:
		died.emit()


## #388: grant shield. Uncapped and additive; ignored when dead or for
## non-positive amounts.
func add_shield(amount: int) -> void:
	if amount <= 0 or hp <= 0:
		return
	shield += amount
	# A new grant refreshes the pooled decay clock for the whole pool.
	_shield_delay_left = shield_decay_delay
	_shield_decay_carry = 0.0
	shield_changed.emit(shield)


## #388: drop the whole shield pool (for strip effects).
func clear_shield() -> void:
	_shield_delay_left = 0.0
	_shield_decay_carry = 0.0
	if shield == 0:
		return
	shield = 0
	shield_changed.emit(shield)


## #388: seconds until the shield starts decaying (0 once draining).
func shield_decay_delay_left() -> float:
	return _shield_delay_left if shield > 0 else 0.0


## #388: advance the shield decay clock. Called from _physics_process; public
## so harnesses can step it deterministically. Holds for the delay, then
## drains shield_decay_rate points/s (fractions carried) down to 0.
func tick_shield_decay(delta: float) -> void:
	if shield <= 0 or delta <= 0.0:
		return
	if _shield_delay_left > 0.0:
		if delta <= _shield_delay_left:
			_shield_delay_left -= delta
			return
		delta -= _shield_delay_left
		_shield_delay_left = 0.0
	_shield_decay_carry += maxf(shield_decay_rate, 0.0) * delta
	var drain := int(floor(_shield_decay_carry))
	if drain <= 0:
		return
	_shield_decay_carry -= drain
	shield = maxi(shield - drain, 0)
	if shield == 0:
		_shield_decay_carry = 0.0
	shield_changed.emit(shield)


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
	tick_shield_decay(delta)
	if hp <= 0:
		velocity = Vector2.ZERO
		if _dash_time_left > 0.0:
			_dash_time_left = 0.0
			_end_dash()
		# #305: death also cancels a spell launch - no launch_ended, so the
		# deferred attack is dropped (the cast committed when it started).
		if _launch_time_left > 0.0:
			_launch_time_left = 0.0
			launch_cancelled.emit()
		return
	var input_dir := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if input_dir != Vector2.ZERO:
		_last_move_dir = input_dir.normalized()
	_tick_dash_recharge(delta)
	if Input.is_action_just_pressed(&"dash"):
		try_dash(input_dir)
	var desired := input_dir * move_speed()
	if _dash_time_left > 0.0:
		# #450: the last tick only covers the remaining time, so the distance
		# is exactly dash_speed * dash_duration instead of rounding up to a
		# whole physics frame (0.09s is 5.4 frames at 60 fps).
		var dash_scale := minf(_dash_time_left, delta) / delta if delta > 0.0 else 1.0
		desired = _dash_dir * dash_speed * dash_scale
		_dash_time_left = maxf(_dash_time_left - delta, 0.0)
		_spawn_dash_ghost()
		if _dash_time_left == 0.0:
			_end_dash()
	# #305: a spell launch overrides desired velocity like the dash (and wins
	# over it while both run); it feeds the SAME resolve/move_and_slide call
	# below, so terrain clamps apply exactly like dashing. launch_ended emits
	# only AFTER movement resolves, so the deferred attack spawns at the
	# settled position.
	var launch_finished := false
	if _launch_time_left > 0.0:
		desired = _launch_dir * _launch_speed
		_launch_time_left = maxf(_launch_time_left - delta, 0.0)
		if _launch_time_left == 0.0:
			launch_finished = true
	velocity = TerrainMotion.resolve(terrain, global_position, velocity, desired, delta, can_swim)
	move_and_slide()
	if launch_finished:
		launch_ended.emit()
	if sprite != null:
		if input_dir != Vector2.ZERO:
			# 8-way -> 4-way: dominant axis wins, exact diagonals face vertically.
			if absf(input_dir.x) > absf(input_dir.y):
				facing = &"right" if input_dir.x > 0.0 else &"left"
			else:
				facing = &"down" if input_dir.y > 0.0 else &"up"
		_update_sprite(input_dir != Vector2.ZERO or is_dashing() or is_launching())

## #266: single entry point for instant movement that is not WASD/dash
## velocity: being pushed, spell movement (blinks, leaps), scripted shoves.
## Terrain clamps it, so the player stops at the edge of any blocking or
## falling cell instead of entering it. Returns the offset actually applied.
func displace(offset: Vector2) -> Vector2:
	var from := global_position
	global_position = TerrainMotion.clamp_displacement(terrain, from, from + offset, can_swim)
	return global_position - from

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

## #198: start a dash if not dead, not already dashing and a dash charge is
## available (#426). `input_dir` zero falls back to the last movement
## direction. Returns whether a dash started.
func try_dash(input_dir: Vector2 = Vector2.ZERO) -> bool:
	if hp <= 0 or _dash_time_left > 0.0 or _dash_charges <= 0 or _launch_time_left > 0.0:
		return false
	_dash_dir = input_dir.normalized() if input_dir != Vector2.ZERO else _last_move_dir
	_dash_time_left = dash_duration
	_dash_charges -= 1
	if _dash_recharge_left <= 0.0:
		_dash_recharge_left = dash_cooldown
	if sprite != null:
		sprite.modulate = Color(0.75, 0.9, 1.6)
	dash_started.emit(_dash_dir)
	return true


func is_dashing() -> bool:
	return _dash_time_left > 0.0


## Seconds until a dash is available again: 0 while any charge is ready.
func dash_cooldown_remaining() -> float:
	return 0.0 if _dash_charges > 0 else _dash_recharge_left


## #426: dash charges ready right now.
func dash_charges() -> int:
	return _dash_charges


## #426: charge cap = base + owned relics' DASH_CHARGES_KEY effects. Queried
## live (the OwnedRelics apply seam), so a relic gained mid-run counts at
## once and nothing goes stale. No OwnedRelics mounted = base charges.
func dash_max_charges() -> int:
	var relics := get_tree().get_first_node_in_group("owned_relics") as OwnedRelics if is_inside_tree() else null
	var extra := 0
	if relics != null:
		extra = int(relics.scalar_total(DASH_CHARGES_KEY))
	return maxi(BASE_DASH_CHARGES + extra, 1)


## #426: one charge recharges at a time; the next starts as soon as the
## previous lands. A newly gained charge slot (relic pickup) fills at once.
func _tick_dash_recharge(delta: float) -> void:
	var cap := dash_max_charges()
	if _dash_charges >= cap:
		_dash_charges = cap
		_dash_recharge_left = 0.0
		return
	_dash_recharge_left = maxf(_dash_recharge_left - delta, 0.0)
	if _dash_recharge_left == 0.0:
		_dash_charges += 1
		if _dash_charges < cap:
			_dash_recharge_left = dash_cooldown


## #305: start a spell launch (Mastery: launched forward BEFORE attacking).
## Same gate shape as try_dash: refuses when dead or already launching and
## consumes nothing on refusal. No cooldown of its own - the spell's
## cooldown governs. Zero direction falls back to the last movement
## direction, matching the dash.
func launch(direction: Vector2, speed: float, duration: float) -> bool:
	if hp <= 0 or _launch_time_left > 0.0:
		return false
	_launch_dir = direction.normalized() if direction != Vector2.ZERO else _last_move_dir
	_launch_speed = speed
	_launch_time_left = duration
	launch_started.emit(_launch_dir)
	return true


func is_launching() -> bool:
	return _launch_time_left > 0.0


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
