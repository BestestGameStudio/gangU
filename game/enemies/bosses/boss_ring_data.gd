class_name BossRingData
extends Resource
## #513: authored boss attack tuning, read-only during combat.
@export var radius: float
@export var enraged_radius: float
@export var damage: int
@export var display_time: float
@export var color: Color
## Head staggers two rings when enraged; Beast scales its first ring.
@export var phase_first_radius: bool = false
@export var enraged_second_ring: bool = false
@export var second_at: float = 0.0
@export var second_animation: StringName = &""
@export var duration: float = 0.5
@export var enraged_duration: float = 0.5
