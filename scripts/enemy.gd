class_name Enemy
extends CharacterBody2D
## #5: basic enemy. Chases the player, deals contact damage, takes spell damage.
## Contract: died(), health_changed(), apply_damage() (clamps, emits inside only).

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

var hp: int
var _player: Player
var _contact_timer: float = 0.0

func _ready() -> void:
	hp = max_hp
	add_to_group("enemies")
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
		queue_free()

func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player) or _player.hp <= 0:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	var to_player: Vector2 = _player.global_position - global_position
	velocity = to_player.normalized() * speed if to_player.length() > 8.0 else Vector2.ZERO
	move_and_slide()
	_contact_timer = maxf(0.0, _contact_timer - delta)
	if to_player.length() <= contact_range and _contact_timer <= 0.0:
		_player.apply_damage(contact_damage)
		_contact_timer = contact_cooldown
