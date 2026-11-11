class_name BossLungeData
extends Resource
## #513: authored boss attack tuning, read-only during combat.
@export var speed: float
@export var enraged_speed: float
@export var duration: float
@export var hit_range: float
@export var damage: int
## Optional enraged chain, after movement/contact on the duration boundary.
@export var enraged_chain: bool = false
@export var chain_pause: float = 0.0
@export var chain_length: float = 0.0
@export var chain_animation: StringName = &""
