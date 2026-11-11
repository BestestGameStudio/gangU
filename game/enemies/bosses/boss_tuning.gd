class_name BossTuning
extends Resource
## #513: authored boss-loop tuning. Runtime state remains per behavior.
@export var first_attack_delay: float = 1.0
@export var attack_interval: float = 1.8
@export var enraged_interval: float = 1.0
@export var recover_time: float = 0.5
@export var stun_time: float = 1.6
@export var has_stun_phase: bool = false
@export var arrival_color: Color = Enemy.SPRITE_BURST_COLOR
@export var windup_times: Dictionary = {}
@export var windup_anims: Dictionary = {}
@export var clear_glow_on_stun: bool = false
