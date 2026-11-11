class_name SummonDefinition
extends Resource
## #209: per-summon-type definition (foundation). "Enemies targeting is
## configurable" (Daniel, 2026-11-08): enemy_targetable gates whether standard
## chase/contact enemies may pick this summon as their target.
## #212: behavior + combat/follow stats arrive with the first concrete summon
## (the summon spell's guard ally). Defaults preserve the #209 foundation:
## null behavior = inert summon, taunt_range 0.0 = global retarget semantics.
## No lifetime, stat-scaling or acquisition fields: those stay open
## (#209 foundation excludes them; later issues own them).

@export var display_name: String = "Summon"
@export var max_hp: int = 30
## When false, standard enemies ignore this summon and keep chasing the player.
@export var enemy_targetable: bool = true
## Placeholder body color; real art is a later issue (no new art in #209).
@export var body_color: Color = Color(0.5, 0.7, 1.0)

## #212: behavior slot, same seam idiom as enemy_definition.behavior. Optional
## Script whose instances implement
## physics_step(summon: Summon, player: Node2D, delta: float)
## (summon_behavior_guard.gd documents the first concrete contract). Each
## Summon instantiates its OWN behavior instance in _ready, so per-summon
## state (the contact cooldown timer) is never shared. Null = the #209 inert
## foundation behavior (unchanged default).
@export var behavior: Script = null

## #212 combat/follow stats. Consumed by the behavior, never hardcoded there.
@export var speed: float = 110.0
@export var contact_damage: int = 5
@export var contact_cooldown: float = 0.8
@export var contact_range: float = 40.0
## Engage enemies only within this radius of the summon.
@export var aggro_range: float = 120.0
## Return-to-player overrides combat past this distance ("will follow if you
## get too far").
@export var follow_far: float = 160.0
## #212 local taunt: standard chase/contact enemies within this radius prefer
## this summon over the player. 0.0 = unlimited (#209 global semantics,
## unchanged default for foundation definitions). Boss behaviors never
## retarget regardless (structural, enemy.gd).
@export var taunt_range: float = 0.0
