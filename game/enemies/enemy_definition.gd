class_name EnemyDefinition
extends Resource
## #98 (Foundation E1): per-enemy-type data - stats + reward table.
## #99 (Foundation E2): behavior slot.
##
## Every Enemy requires one: assigning it copies ALL of its stats into the
## enemy as a set. Reward precedence (rule agreed with lead before write): an
## explicitly assigned direct Enemy.reward_table WINS over the definition's
## table (instance override); the definition's table is used only when no
## direct table is assigned. Null everywhere = no drop.
##
## NO visual fields (no settled schema or consumer - a future field lands
## with its real consumer).

@export var max_hp: int = 30
@export var speed: float = 110.0
@export var contact_damage: int = 10
@export var contact_cooldown: float = 0.8
@export var contact_range: float = 40.0
@export var reward_table: RewardTable
## EnemyBehavior prototype. Each Enemy duplicates it deeply, so no runtime
## state is shared by enemies. Null uses the default chase/contact behavior;
## anything that is not an EnemyBehavior is an error (see Enemy._ready).
## The editor restricts it to EnemyBehavior, but the variable stays Resource:
## a typed EnemyBehavior variable silently loads as null when a script that
## preloads an enemy scene (OverworldBird, WolfCave, AreaLoader) compiles
## before the behavior script, because the half-compiled behavior does not
## yet pass the type check.
@export_custom(PROPERTY_HINT_RESOURCE_TYPE, "EnemyBehavior") var behavior: Resource
