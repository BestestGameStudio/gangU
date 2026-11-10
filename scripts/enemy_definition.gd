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
## Optional EnemyBehavior Resource prototype, or legacy Script extending it.
## Enemy creates its own instance: prototypes duplicate deeply, Script slots
## instantiate fresh. No runtime state is shared by enemies.
## Null or unsupported resources use the default chase/contact behavior.
@export var behavior: Resource
