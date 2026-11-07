class_name EnemyDefinition
extends Resource
## #98 (Foundation E1): per-enemy-type data - stats + reward table.
## #99 (Foundation E2): behavior slot.
##
## An Enemy WITHOUT an assigned definition behaves exactly as before (its
## own @export values). When a definition is assigned, ALL of its stats
## take effect as a set (no per-field scalar mixing). Reward precedence
## (rule agreed with lead before write): an explicitly assigned direct
## Enemy.reward_table WINS over the definition's table (instance
## override); the definition's table is used only when no direct table is
## assigned. Null everywhere = no drop (unchanged).
##
## NO visual fields (no settled schema or consumer - a future field lands
## with its real consumer). Defaults mirror the current enemy.gd @export
## defaults.

@export var max_hp: int = 30
@export var speed: float = 110.0
@export var contact_damage: int = 10
@export var contact_cooldown: float = 0.8
@export var contact_range: float = 40.0
@export var reward_table: RewardTable
## #99 (Foundation E2): behavior slot. Optional Script whose instances
## implement physics_step(enemy: Enemy, player: Player, delta: float)
## (enemy_behavior_chase_contact.gd documents the current contract).
## Each Enemy instantiates its OWN behavior instance in _ready, so
## per-enemy state (contact cooldown) is never shared across enemies.
## Null = the current chase/contact implementation (unchanged default);
## a script without physics_step falls back to it with a warning.
@export var behavior: Script
