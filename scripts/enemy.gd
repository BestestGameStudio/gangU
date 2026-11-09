class_name Enemy
extends CharacterBody2D
## #5: basic enemy. Chases the player, deals contact damage, takes spell damage.
## Contract: died(), health_changed(), apply_damage() (clamps, emits inside only).
## #99 (Foundation E2): chase/contact behavior extracted into a per-enemy
## behavior instance (see enemy_behavior_chase_contact.gd); swappable via
## the definition's behavior slot. Behavior unchanged.
## #177: optional "Sprite" child (EnemySprite, Mustache Warrior art) drives
## idle/walk/attack/hurt animation; death hands off to a detached corpse
## that plays the death animation. Visual only - the contract is unchanged.

signal died()
signal health_changed(current: int, max_hp: int)

@export var max_hp: int = 30
@export var speed: float = 110.0
@export var contact_damage: int = 10
@export var contact_cooldown: float = 0.8
@export var contact_range: float = 40.0
@export var can_swim: bool = false
## #34: explicit target wiring FIRST - the production main.tscn Player is in no
## group, matching the RunManager/ReviveSatchel/HUD explicit-wiring convention.
## The "player" group lookup remains as a fallback so existing test scenes
## (which put the Player in the group) keep working unchanged.
@export var player_path: NodePath
## (A, #59) Reward drop: on death, roll this table and spawn the drop at my
## position. ADDITIVE hook only - no table assigned means no drop. Table
## contents, weights and drop chances are human-open (#59); placeholder data.
@export var reward_table: RewardTable
## #98 (Foundation E1): optional per-type definition. When assigned, its
## stats take effect as a set (applied in _ready before hp init; no
## per-field scalar mixing). Reward precedence: a directly assigned
## reward_table WINS over the definition's table (instance override); the
## definition's table applies only when no direct table is assigned.
## #99 (Foundation E2): the definition's behavior slot picks the behavior
## Script; unset = the current chase/contact implementation.
@export var definition: EnemyDefinition

var hp: int
var damage_modifiers := DamageModifiers.new()
var damage_rng := RandomNumberGenerator.new()
var terrain: TerrainMap = null
var _player: Player
## #99: per-enemy behavior instance (created in _ready). Owns the contact
## cooldown; never shared across enemies.
var _behavior: RefCounted
## #177: animated art, if this enemy scene carries one (null otherwise).
@onready var sprite: EnemySprite = get_node_or_null("Sprite") as EnemySprite

func _ready() -> void:
	if definition != null:
		max_hp = definition.max_hp
		speed = definition.speed
		contact_damage = definition.contact_damage
		contact_cooldown = definition.contact_cooldown
		contact_range = definition.contact_range
	hp = max_hp
	damage_rng.randomize()
	add_to_group("enemies")
	# #325: note the encounter in the cross-run hub bestiary (keyed by scene).
	Bestiary.record_enemy(self)
	# #99: instantiate MY OWN behavior (never a shared Resource). Slot unset
	# or no definition = the current chase/contact implementation; a slot
	# script without physics_step falls back to it with a warning.
	var behavior_script: Script = EnemyBehaviorChaseContact
	if definition != null and definition.behavior != null:
		behavior_script = definition.behavior
	_behavior = behavior_script.new()
	if not _behavior.has_method("physics_step"):
		push_warning("Enemy: definition behavior script lacks physics_step(enemy, player, delta); using the default chase/contact behavior.")
		_behavior = EnemyBehaviorChaseContact.new()
	if player_path != NodePath(""):
		_player = get_node_or_null(player_path) as Player
		if _player == null:
			push_warning("Enemy: player_path did not resolve to a Player; falling back to the 'player' group.")
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		push_warning("Enemy: no player target (no player_path and no 'player' group member); standing idle.")
	# #290: never physically block or push players (deferred so a Player added
	# in the same frame has registered its group first).
	_ignore_player_bodies.call_deferred()

## #290: collision exceptions with every Player (plus the resolved target).
## #279: also every Summon - enemies spawn continuously, so the late side
## pairs itself here (summon.gd covers the cast-time direction).
func _ignore_player_bodies() -> void:
	ActorCollision.ignore_group(self, ActorCollision.PLAYER_GROUP)
	ActorCollision.ignore_group(self, &"summons")
	if _player != null and is_instance_valid(_player):
		ActorCollision.ignore_pair(self, _player)

## #301: unpair on exit - a freed body otherwise leaves a stale entry in
## peers' collision exception lists, and the engine logs
## "Parameter \"body\" is null" the next time a peer reads its list.
func _exit_tree() -> void:
	for e in get_collision_exceptions():
		if is_instance_valid(e):
			e.remove_collision_exception_with(self)

## #109: hit feedback - brief over-bright flash so a registered hit is
## visible even when the enemy survives (25 dmg vs 30 hp). Additive only.
var _flash_t: float = 0.0
const FLASH_TIME: float = 0.12

## #110: combat feedback - code-drawn death burst + hit spark (visual only).
const CombatEffects = preload("res://scripts/combat_effects.gd")

## crit_tier (#208) only colors the damage number; HP math ignores it.
func apply_damage(amount: int, crit_tier: int = 0) -> void:
	if hp <= 0:
		return
	hp = clampi(hp - amount, 0, max_hp)
	_flash_t = FLASH_TIME
	modulate = Color(2.4, 2.4, 2.4)
	health_changed.emit(hp, max_hp)
	CombatEffects.damage_number(get_parent(), global_position, amount, crit_tier)
	if hp > 0:
		# #110: brief contact spark at the damage-apply site (ENEMY-CENTER,
		# not the exact physical impact point). Visual only.
		CombatEffects.hit_spark(get_parent(), global_position)
	if hp == 0:
		died.emit()
		_spawn_reward_drop()
		_spawn_death_burst()
		queue_free()

## #110: death burst - visual only; the effect owns its lifetime and is
## parented to my area, so it survives my queue_free. HP/drop/AI untouched.
## #177: sprite enemies burst in their own green and leave a corpse that
## plays the death animation (it frees itself).
const SPRITE_BURST_COLOR: Color = Color(0.62, 0.9, 0.24)

func _spawn_death_burst() -> void:
	var c: Color = Color(0.95, 0.42, 0.06)
	if has_node("Spikes"):
		c = $Spikes.color
	if sprite != null:
		c = sprite.burst_color
		EnemySprite.spawn_corpse(sprite, get_parent())
	CombatEffects.death_burst(get_parent(), global_position, c)

## #177: behaviors request animations through here (attack swing, boss
## wind-ups...). No-op for enemies without a Sprite. Visual only.
func play_action(anim: StringName, hold: bool = false) -> void:
	if sprite != null:
		sprite.play_action(anim, hold)

func clear_action() -> void:
	if sprite != null:
		sprite.clear_action()

func _process(delta: float) -> void:
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			modulate = Color.WHITE

## #209: target resolution. DEFAULT UNCHANGED: the resolved player. A
## standard chase/contact enemy may instead pick the nearest live summon
## whose definition allows enemy targeting ("enemies targeting is
## configurable", Daniel 2026-11-08). Boss behaviors (head/warlord) keep
## their Player-typed physics_step and stay player-only, so a summon is
## never passed to them. With no summons in the tree this returns _player
## exactly as before.
func _resolve_target() -> CharacterBody2D:
	if _behavior is EnemyBehaviorChaseContact:
		var best: Summon = null
		var best_d := INF
		for s in get_tree().get_nodes_in_group("summons"):
			var summon := s as Summon
			if summon == null or summon.hp <= 0:
				continue
			if summon.definition != null and not summon.definition.enemy_targetable:
				continue
			var d := global_position.distance_squared_to(summon.global_position)
			# #212: local taunt - a definition with taunt_range > 0 only draws
			# enemies within that radius; 0.0 keeps the #209 global semantics.
			if summon.definition != null and summon.definition.taunt_range > 0.0 and d > summon.definition.taunt_range * summon.definition.taunt_range:
				continue
			if d < best_d:
				best_d = d
				best = summon
		if best != null:
			return best
	return _player

## #305: Signature freeze. Reference-counted by FreezeBubble claims; while
## positive, the behavior physics_step (which accumulates ALL behavior
## clocks from delta) never runs, so the whole enemy freezes.
var _freeze_count := 0
var _spawn_claim_pending := true

## #305: Signature freeze contract. Claims are reference-counted so
## overlapping bubbles freeze and release independently. The animated
## sprite pauses while held - a frozen enemy must LOOK frozen.
func set_frozen(frozen: bool) -> void:
	var was := _freeze_count
	_freeze_count = maxi(_freeze_count + (1 if frozen else -1), 0)
	if sprite != null:
		if _freeze_count > 0 and was == 0:
			# pause() alone does not hold: the sprite driver's _process
			# replays locomotion every frame. Stop its processing too.
			sprite.pause()
			sprite.process_mode = Node.PROCESS_MODE_DISABLED
		elif _freeze_count == 0 and was > 0:
			sprite.process_mode = Node.PROCESS_MODE_INHERIT
			sprite.play()

func _physics_process(delta: float) -> void:
	if _spawn_claim_pending:
		# #305: spawn claim on the FIRST physics step, not _ready: production
		# spawns can set global_position after add_child, so a _ready hook
		# would claim against a stale position. Here the position is final
		# and movement has not started - an inside-spawn freezes with zero
		# motion (Area2D registration lags a frame, so the bubble's scan
		# alone can miss a mid-frame spawn).
		_spawn_claim_pending = false
		for bubble in get_tree().get_nodes_in_group(&"freeze_bubbles"):
			bubble.claim(self)
	if _freeze_count > 0:
		return
	# #331: a strong knockback owns the body until it decays below
	# KNOCKBACK_CONTROL, so the push reads; the behavior resumes after.
	if _knockback.length() > KNOCKBACK_CONTROL:
		move_and_collide(_knockback * delta)
		_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECEL * delta)
		return
	_knockback = Vector2.ZERO
	if _behavior != null:
		_behavior.physics_step(self, _resolve_target(), delta)

## #331 Water Ball bubble Mastery: push this enemy along `push` (px/s),
## decaying at KNOCKBACK_DECEL px/s^2. Walls stop it (move_and_collide).
## Stronger pushes replace weaker ones; they never stack.
const KNOCKBACK_DECEL := 1800.0
const KNOCKBACK_CONTROL := 60.0
var _knockback := Vector2.ZERO

func knockback(push: Vector2) -> void:
	if hp <= 0:
		return
	if push.length() > _knockback.length():
		_knockback = push

func is_knocked_back() -> bool:
	return _knockback.length() > KNOCKBACK_CONTROL

## (A, #59) Roll the table against the pool's granted set and defer-spawn the
## drop into my parent (the area), so an area swap frees it like any other
## area child. Null roll (pool exhausted / empty table) means no drop.
func _spawn_reward_drop() -> void:
	var table: RewardTable = reward_table
	if table == null and definition != null:
		table = definition.reward_table
	if table == null:
		return
	var pool := get_tree().get_first_node_in_group("reward_pool") as RewardPool
	var granted: Array = pool.granted() if pool != null else []
	var entry := table.roll(granted)
	if entry == null:
		return
	var drop: RewardDrop = preload("res://scenes/reward_drop.tscn").instantiate()
	drop.setup(entry)
	drop.global_position = global_position
	get_parent().call_deferred("add_child", drop)
