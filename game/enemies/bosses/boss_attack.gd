class_name BossAttack
extends Resource
## #513: authored presentation, read-only during combat.
@export var next_state: int
@export var animation: StringName
@export var shape: int
@export var length: float
@export var width: float
@export var radius: float
@export var phase_ring: bool = false
@export var clear_on_start: bool = true
@export var start_ring: bool = false
@export var start_duration: float = 0.0
