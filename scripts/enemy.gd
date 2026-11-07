class_name Enemy
extends CharacterBody2D
## #5: basic enemy. Chases the player, deals contact damage, takes spell damage.
## Contract: died(), health_changed(), apply_damage() (clamps, emits inside only).
## #99 (Foundation E2): chase/contact behavior extracted into a per-enemy
## behavior instance (see enemy_behavior_chase_contact.gd); swappable via
## the definition's behavior slot. Behavior unchanged.

signal died()
signal health_changed(current: int, max_hp: int)

@export var max_hp: int = 30
@export var speed: float = 110.0
@export var contact_damage: int = 10
@export var contact_cooldown: float = 0.8
@export var contact_range: float = 40.0
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
var _player: Player
## #99: per-enemy behavior instance (created in _ready). Owns the contact
## cooldown; never shared across enemies.
var _behavior: RefCounted

func _ready() -> void:
	if definition != null:
		max_hp = definition.max_hp
		speed = definition.speed
		contact_damage = definition.contact_damage
		contact_cooldown = definition.contact_cooldown
		contact_range = definition.contact_range
	hp = max_hp
	add_to_group("enemies")
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

func apply_damage(amount: int) -> void:
	if hp <= 0:
		return
	hp = clampi(hp - amount, 0, max_hp)
	health_changed.emit(hp, max_hp)
	if hp == 0:
		died.emit()
		_spawn_reward_drop()
		queue_free()

func _physics_process(delta: float) -> void:
	if _behavior != null:
		_behavior.physics_step(self, _player, delta)

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
