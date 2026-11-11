class_name Enemy
extends CharacterBody2D
## #5: basic enemy. Chases the player, deals contact damage, takes spell damage.
## Contract: died(), health_changed(), apply_damage() (clamps, emits inside only).
## #99 (Foundation E2): chase/contact behavior extracted into a per-enemy
## behavior instance (see enemy_behavior_chase_contact.gd); swappable via
## the definition's behavior slot.
## #177: optional "Sprite" child (EnemySprite, Mustache Warrior art) drives
## idle/walk/attack/hurt animation; death hands off to a detached corpse
## that plays the death animation. Visual only - the contract is unchanged.

signal died()
signal health_changed(current: int, max_hp: int)

## Runtime stats, copied from `definition` when it is assigned.
var max_hp: int
var speed: float
var contact_damage: int
var contact_cooldown: float
var contact_range: float
@export var can_swim: bool = false
## #406 (Daniel, 2026-11-09: "moustache men now seek cover... just regular
## mobs... any cover"): opt this enemy into the cover-seeking chase (see
## enemy_behavior_cover.gd). Data per scene: the Mustache Warrior scene
## (game/enemies/enemy.tscn) sets it; the Warlord boss and other types do not.
@export var cover_seek: bool = false
## #34: explicit target wiring FIRST (production always sets it); unset falls
## back to Player.find.
@export var player_path: NodePath
## (A, #59) Reward drop: on death, roll this table and spawn the drop at my
## position. ADDITIVE hook only - no table assigned means no drop. Table
## contents, weights and drop chances are human-open (#59); placeholder data.
@export var reward_table: RewardTable
## Required per-type data: stats, reward table and behavior slot. Every enemy
## scene carries one; _ready reports an error when it is missing. Reward
## precedence: a directly assigned reward_table WINS over the definition's
## table (instance override). A null behavior slot means the default
## chase/contact behavior.
## Stats are copied on assignment rather than in _ready, so code that tunes
## an instance between instantiate() and add_child keeps its values.
@export var definition: EnemyDefinition:
	set(value):
		definition = value
		if value != null:
			max_hp = value.max_hp
			speed = value.speed
			contact_damage = value.contact_damage
			contact_cooldown = value.contact_cooldown
			contact_range = value.contact_range

var hp: int
var damage_modifiers := DamageModifiers.new()
var damage_rng := RandomNumberGenerator.new()
var terrain: TerrainMap = null
var _player: Player
## #337: DEFENSE objective target (a DefenseCore), set by DungeonObjective on
## part of each wave. See _resolve_target.
var objective_target: DefenseCore = null
var objective_aggro_range: float = 150.0
## #367: grid pathfinding (maze defense waves). Null - every other enemy -
## keeps the straight-line chase. The chase/contact behavior steers through
## it toward whatever _resolve_target picked (core or player).
var nav: FlowNav = null
## #99: per-enemy behavior instance (created in _ready). Owns the contact
## cooldown; never shared across enemies.
var _behavior: EnemyBehavior
## #513: typed spawn context (WolfContext, BirdContext) set by the owner that
## spawns this enemy, before add_child; null for ordinary enemies.
var context: RefCounted = null
## #177: animated art, if this enemy scene carries one (null otherwise).
@onready var sprite: EnemySprite = get_node_or_null("Sprite") as EnemySprite

func _ready() -> void:
	if definition == null:
		push_error("Enemy '%s' (%s) has no EnemyDefinition; every enemy scene must carry one." % [name, scene_file_path])
	hp = max_hp
	damage_rng.randomize()
	add_to_group("enemies")
	# #325: note the encounter in the cross-run hub bestiary (keyed by scene).
	Bestiary.record_enemy(self)
	# The prototype is duplicated so no runtime state is shared by enemies.
	var prototype: Resource = definition.behavior if definition != null else null
	if prototype == null:
		_behavior = EnemyBehaviorChaseContact.new()
	elif _is_behavior_script(prototype.get_script() as Script):
		_behavior = prototype.duplicate(true) as EnemyBehavior
	else:
		push_error("Enemy '%s' (%s): definition behavior %s is not an EnemyBehavior; the enemy has no behavior." % [name, scene_file_path, prototype])
	if player_path != NodePath(""):
		_player = get_node_or_null(player_path) as Player
		if _player == null:
			push_warning("Enemy: player_path did not resolve to a Player; falling back to Player.find.")
	if _player == null:
		_player = Player.find(get_tree())
	if _player == null:
		push_warning("Enemy: no player target (no player_path and no Player in the tree); standing idle.")
	# #515: players never block enemies (or each other) - layers/masks in the
	# scene, see PhysicsLayers.

## Checks the prototype's script chain, not the instance: a behavior .tres
## loaded while its script is still compiling (a preload cycle through an
## owner such as WolfCave) holds a placeholder instance that fails
## `is EnemyBehavior`, but its duplicate is a real one.
static func _is_behavior_script(script: Script) -> bool:
	while script != null:
		if script == EnemyBehavior:
			return true
		script = script.get_base_script()
	return false

## The one path for every hit an enemy lands: DamageCalc with both sides'
## modifiers, then the OnHit capture and report. `target` is duck-typed
## (Player, Summon, DefenseCore): it needs damage_modifiers and
## apply_damage(amount). Returns the reported event, or null when refused.
func deal_hit(target, base: int, delivery: StringName) -> HitEvent:
	var hit := DamageCalc.compute(base, damage_modifiers, target.damage_modifiers, damage_rng)
	var receipt := OnHit.begin(target)
	target.apply_damage(hit.amount)
	OnHit.end(receipt, target)
	return OnHit.report(self, null, target, hit, delivery, receipt)

## #109: hit feedback - brief over-bright flash so a registered hit is
## visible even when the enemy survives (25 dmg vs 30 hp). Additive only.
var _flash_t: float = 0.0
const FLASH_TIME: float = 0.12

## #110: combat feedback - code-drawn death burst + hit spark (visual only).
const CombatEffects = preload("res://game/combat/combat_effects.gd")

## crit_tier (#208) only colors the damage number; HP math ignores it.
func apply_damage(amount: int, crit_tier: int = 0) -> void:
	if hp <= 0:
		return
	var before := hp
	hp = clampi(hp - amount, 0, max_hp)
	OnHit.record(self, before, hp) # #390: outcome captured before any emit
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
		_spawn_boss_relic_drop()
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
	visible = seen_by_player() # #461 tall grass
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
## #337: a DEFENSE wave enemy may carry an objective_target (the DefenseCore).
## It attacks the core, but turns on the player whenever the player comes
## within objective_aggro_range, and goes back to the core once they leave.
## Summon taunts still win (same priority as for any chase/contact enemy).
## Unset (every non-defense enemy): no change.
func _resolve_target() -> Node2D:
	if _behavior is EnemyBehaviorChaseContact:
		var best: Summon = null
		var best_d := INF
		for s in get_tree().get_nodes_in_group("summons"):
			var summon := s as Summon
			if summon == null or summon.hp <= 0:
				continue
			if summon.definition != null and not summon.definition.enemy_targetable:
				continue
			if not sees(summon): # #461: a summon hidden in tall grass
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
		if objective_target != null and is_instance_valid(objective_target) and objective_target.hp > 0:
			var player_alive := _player != null and is_instance_valid(_player) and _player.hp > 0
			if not (player_alive and sees(_player) and global_position.distance_to(_player.global_position) <= objective_aggro_range):
				return objective_target
	# #461: a player hidden in tall grass is no target at all - every behavior
	# already treats a null target as "no player" (idle / guards go home).
	if _player != null and is_instance_valid(_player) and not sees(_player):
		return null
	return _player

## #461: the tall-grass sight rule (TallGrass.can_see) from where I stand.
## The area's grid is mine, or the player's when I was mounted without one.
func sight_map() -> TerrainMap:
	if terrain != null and is_instance_valid(terrain):
		return terrain
	if _player != null and is_instance_valid(_player):
		return _player.terrain
	return null

func sees(other: Node2D) -> bool:
	# #499: a player who attacked from tall grass is revealed to every enemy,
	# at any range, until they leave the grass.
	if other is Player and (other as Player).is_grass_revealed():
		return true
	return TallGrass.can_see(sight_map(), global_position, other.global_position)

## #461: whether the player can currently see me. Drives my drawing: an enemy
## hidden in tall grass is not drawn until the player is in the grass with
## it, close by. Gameplay (hits, damage) is unaffected - only sight.
func seen_by_player() -> bool:
	if _player == null or not is_instance_valid(_player):
		return true
	return TallGrass.can_see(sight_map(), _player.global_position, global_position)

## #464: rally call. Another enemy (the Fishy, when it hooks the player)
## can ask nearby allies to drop what they are doing and converge on the
## target for `duration` seconds. Generic, type-free seam: behaviors read
## is_rallied() - the chase/contact cover machine skips cover and the
## overworld guard roles engage - and the chase moves RALLY_SPEED_MULT
## faster while it lasts. Enemies that never get rallied are unchanged.
const RALLY_SPEED_MULT := 1.35 ## PLACEHOLDER balance
var _rally_left := 0.0

func rally(duration: float) -> void:
	if hp > 0:
		_rally_left = maxf(_rally_left, duration)

func is_rallied() -> bool:
	return _rally_left > 0.0

## Chase speed with the rally bonus applied (plain speed when not rallied).
func chase_speed() -> float:
	return speed * (RALLY_SPEED_MULT if is_rallied() else 1.0)

## #305: Signature freeze. While held, the behavior physics_step (which
## accumulates ALL behavior clocks from delta) never runs, and the sprite
## pauses - a frozen enemy must LOOK frozen.
var freeze := FreezeHold.new()
var _spawn_claim_pending := true

func set_frozen(frozen: bool) -> void:
	freeze.apply(frozen, sprite)

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
	if freeze.is_frozen():
		return
	_rally_left = maxf(_rally_left - delta, 0.0)
	# #331: a strong knockback owns the body until it decays below
	# KNOCKBACK_CONTROL, so the push reads; the behavior resumes after.
	if _knockback.length() > KNOCKBACK_CONTROL:
		var before := global_position
		move_and_collide(_knockback * delta)
		# #367: maze walls are terrain, not colliders; keep a nav enemy out
		# of them (same clamp as the chase step). #396: dungeon arena walls
		# are terrain too, so every enemy on a terrain grid is clamped - a
		# Water Ball shove must not push a mob or boss out of the arena.
		if terrain != null:
			global_position = TerrainMotion.clamp_displacement(terrain, before, global_position, can_swim)
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

## #396: the terrain-aware move for scripted (boss) behaviors that set
## `velocity` directly - chases, lunges, charges, spins. The velocity goes
## through TerrainMotion.resolve (slides along walls, terrain speed rules)
## and the frame's displacement is clamped like a push, so a crowding shove
## cannot carry the body into a wall either. terrain == null is a plain
## move_and_slide, exactly as before. The behavior's own velocity is put
## back afterwards, so a behavior that sets it once per state (a lunge)
## never compounds a terrain speed multiplier frame after frame.
func terrain_move_and_slide() -> void:
	if terrain == null:
		move_and_slide()
		return
	var wanted := velocity
	velocity = TerrainMotion.resolve(terrain, global_position, wanted, wanted, get_physics_process_delta_time(), can_swim)
	var before := global_position
	move_and_slide()
	global_position = TerrainMotion.clamp_displacement(terrain, before, global_position, can_swim)
	velocity = wanted

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
	var pool := Run.reward_pool()
	var granted: Array = pool.granted() if pool != null else []
	var entry := table.roll(granted)
	if entry == null:
		return
	var drop: RewardDrop = preload("res://game/economy/reward_drop.tscn").instantiate()
	drop.setup(entry)
	drop.global_position = global_position
	get_parent().call_deferred("add_child", drop)

## #426: any boss (the "boss" group) rolls BossRelicDrop on death, separately
## from its reward table. The relic lands beside the table drop (offset so
## the two pickups do not overlap) as a walk-over pickup.
const BOSS_RELIC_OFFSET := Vector2(96, 0)

func _spawn_boss_relic_drop() -> void:
	if not is_in_group("boss") or get_parent() == null:
		return
	var owned := Run.relics()
	var relic := BossRelicDrop.pick(owned, randf())
	if relic == null:
		return
	var drop: RewardDrop = preload("res://game/economy/reward_drop.tscn").instantiate()
	drop.setup(BossRelicDrop.entry_for(relic))
	drop.global_position = global_position + BOSS_RELIC_OFFSET
	get_parent().call_deferred("add_child", drop)
	print("[rewards] boss dropped relic: ", relic.display_name)
